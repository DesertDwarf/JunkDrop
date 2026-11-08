import unittest

from harness import Env, default_bag, quality_dots


class Fresh(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag())
        self.env.run("ResetState()")
        self.env.set(AckDrop=True)  # past the one-time warning, which has its own tests


class Ranking(Fresh):
    def test_only_poor_by_default(self):
        self.assertEqual(self.env.order(), "Chipped Claw, Broken Boar Tusk")

    def test_lowest_quality_first_then_cheapest(self):
        self.env.set(Include1=True, Include2=True)
        self.assertEqual(
            self.env.order(),
            "Chipped Claw, Broken Boar Tusk, Wooden Sword, Linen Cloth, Green Cloak",
        )

    def test_cheapest_price_first_ignores_quality(self):
        self.env.set(Include1=True, Include2=True, Order="price")
        self.assertEqual(
            self.env.order(),
            "Wooden Sword, Chipped Claw, Broken Boar Tusk, Green Cloak, Linen Cloth",
        )

    def test_a_quality_can_be_left_out(self):
        self.env.set(Include0=False, Include1=True, Include2=True)
        self.assertEqual(self.env.order(), "Wooden Sword, Linen Cloth, Green Cloak")

    def test_unpriced_and_quest_items_are_never_picked(self):
        self.env.set(Include1=True)
        names = self.env.order()
        self.assertNotIn("Hearthstone", names)
        self.assertNotIn("Crate of Quest Stuff", names)

    def test_a_stack_is_valued_as_a_whole(self):
        self.env.bag([("Wolf Pelts", 0, 2, 6, 15), ("Spare Fang", 0, 10, 1, 15)])
        self.assertEqual(self.env.order(), "Spare Fang, Wolf Pelts")  # 10c beats 6 x 2c = 12c


class Commands(Fresh):
    def test_list_shows_one_line_and_deletes_nothing(self):
        out = self.env.cmd("list")
        self.assertEqual(out, "JunkDrop: Next to drop: [Chipped Claw] x 1 @ 4c")
        self.assertEqual(self.env.deleted(), "")

    def test_list_count_and_all(self):
        self.env.set(Include1=True)
        self.assertIn("The next 3 stack(s) to drop:", self.env.cmd("list 3"))
        self.assertIn("All 4 stack(s), in drop order:", self.env.cmd("list all"))

    def test_debug_marks_what_would_be_dropped(self):
        out = self.env.cmd("list debug")
        self.assertIn("1. [Chipped Claw] x 1 @ 4c <-- would drop", out)
        self.assertNotIn("<-- would drop", out.split("\n")[-1])

    def test_unknown_option_deletes_nothing(self):
        for text in ("dyr", "dry"):
            self.assertIn("Unknown option '%s'" % text, self.env.cmd(text))
        self.assertEqual(self.env.deleted(), "")

    def test_bad_counts_are_refused(self):
        self.assertIn("must be 1 or more", self.env.cmd("0"))
        self.assertIn("cannot be combined", self.env.cmd("2 all"))
        self.assertEqual(self.env.deleted(), "")

    def test_help_lists_the_options(self):
        out = self.env.cmd("help")
        for word in ("list", "debug", "options", "help", "Never drop"):
            self.assertIn(word, out)

    def test_poor_items_are_deleted_without_asking(self):
        self.env.cmd("2")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")
        self.assertEqual(self.env.popup_count(), 0)

    def test_deleting_is_reported_in_chat(self):
        self.assertIn("Deleted [Chipped Claw] x 1 @ 4c", self.env.cmd(""))


class Confirmation(Fresh):
    def setUp(self):
        super().setUp()
        self.env.set(Include1=True)

    def test_a_better_item_asks_first_and_lists_exactly_what_goes(self):
        self.env.cmd("3")
        self.assertEqual(self.env.ev("#Deleted"), 0)
        self.assertEqual(self.env.popup_count(), 1)
        text = self.env.ev("Popups[1].text")
        self.assertEqual(text, "[Chipped Claw] x1\n[Broken Boar Tusk] x1\n[Wooden Sword] x1")

    def test_accepting_deletes_exactly_those_stacks(self):
        self.env.cmd("3")
        self.env.accept_popup()
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk, Wooden Sword")

    def test_a_slot_that_changed_while_asking_is_skipped(self):
        self.env.cmd("3")
        self.env.run('bag[5] = { "Something Else", 0, 1, 1, 15 }')  # the Wooden Sword's slot
        self.env.accept_popup()
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")

    def test_confirmation_can_be_turned_off(self):
        self.env.set(ConfirmHigher=False)
        self.env.cmd("3")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk, Wooden Sword")
        self.assertEqual(self.env.popup_count(), 0)

    def test_list_never_deletes_or_asks(self):
        self.env.cmd("list 5")
        self.assertEqual((self.env.ev("#Deleted"), self.env.popup_count()), (0, 0))


class BarItem(Fresh):
    def test_poor_target_with_confirm_click_asks_once(self):
        self.env.set(ConfirmClick=True)
        self.env.run('LDB.OnClick(nil, "LeftButton")')
        self.assertEqual(self.env.ev("Popups[1].which"), "JUNKDROP_CONFIRM")
        self.assertEqual(self.env.ev("#Deleted"), 0)

    def test_better_target_gets_only_the_run_confirmation(self):
        self.env.set(ConfirmClick=True, Include0=False, Include1=True)
        self.env.run('LDB.OnClick(nil, "LeftButton")')
        self.assertEqual(self.env.popup_count(), 1)
        self.assertEqual(self.env.ev("Popups[1].which"), "JUNKDROP_CONFIRM_RUN")

    def test_the_bar_item_is_a_data_source_with_live_text(self):
        self.assertEqual(self.env.ev("LDB.type"), "data source")

    def test_bar_text_and_dots(self):
        dot0 = quality_dots(0)
        self.assertEqual(self.env.bar_text(), "JunkDrop %s: Chipped Claw 4c" % dot0)
        self.env.set(Label="short", Include2=True, Include4=True)
        self.assertEqual(self.env.bar_text(), "JD %s: Chipped Claw 4c" % quality_dots(0, 2, 4))

    def test_dots_can_be_turned_off(self):
        self.env.set(Dots=False)
        self.assertEqual(self.env.bar_text(), "JunkDrop: Chipped Claw 4c")

    def test_dots_show_without_a_label(self):
        self.env.set(Label="none", Include1=True)
        self.assertEqual(self.env.bar_text(), "%s Chipped Claw 4c" % quality_dots(0, 1))
        self.env.set(Dots=False)
        self.assertEqual(self.env.bar_text(), "Chipped Claw 4c")

    def test_value_only(self):
        self.env.set(Show="value", Include3=True)
        self.assertEqual(self.env.bar_text(), "JunkDrop %s: 4c" % quality_dots(0, 3))

    def test_no_selected_qualities_leaves_no_stray_space(self):
        self.env.set(Include0=False, Label="short")
        self.assertEqual(self.env.bar_text(), "JD: no junk")
        self.env.set(Label="none")
        self.assertEqual(self.env.bar_text(), "no junk")

    def test_letters_style_coins(self):
        self.env.set(Coins="letters")
        self.assertEqual(
            self.env.ev("NS.FormatCoins(12345)"),
            "1|cffffd700g|r 23|cffc7c7cfs|r 45|cffeda55fc|r",
        )

    def test_reset_restores_the_defaults(self):
        self.env.set(Label="short", Include3=True)
        self.env.run("NS.Reset()")
        self.assertEqual(self.env.ev("NS.Get('Label')"), "full")
        self.assertFalse(self.env.ev("NS.Get('Include3')"))


class OptionsWindow(Fresh):
    def test_first_open_shows_the_window_and_it_toggles(self):
        # Real frames start visible; the window must start hidden or the first open hides it.
        shown = []
        for _ in range(3):
            self.env.cmd("options")
            shown.append(self.env.ev("OptionsWindow._shown == true"))
        self.assertEqual(shown, [True, False, True])

    def test_right_click_opens_it_too(self):
        self.env.run('LDB.OnClick(nil, "RightButton")')
        self.assertTrue(self.env.ev("OptionsWindow._shown == true"))


# Fields: name, quality, price, count, item class, max stack, family, quest flag, ID of a quest it starts.
QUEST_BAG = [
    ("Chipped Claw", 0, 4, 1, 15),
    ("Grey Quest Thing", 0, 1, 1, 12),  # the Quest item class
    ("Odd Grey Note", 0, 1, 1, 15, 1, 0, True),  # another class, but the game flags it as a quest item
    ("Torn Page", 0, 1, 1, 15, 1, 0, False, 1234),  # starts a quest
    ("Flagged Common", 1, 10, 1, 15, 1, 0, True),
]


class QuestItems(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(QUEST_BAG)
        self.env.run("ResetState()")

    def test_poor_quest_items_are_never_picked_whichever_way_they_are_marked(self):
        self.assertEqual(self.env.order(), "Chipped Claw")

    def test_nor_are_better_ones(self):
        self.env.set(Include1=True)
        self.assertEqual(self.env.order(), "Chipped Claw")

    def test_all_leaves_them_alone(self):
        self.env.set(Include1=True, ConfirmHigher=False, AckAll=True)  # past the one-time warning
        self.env.cmd("all")
        self.assertEqual(self.env.deleted(), "Chipped Claw")

    def test_the_bar_never_offers_one(self):
        self.assertEqual(self.env.bar_text(), "JunkDrop %s: Chipped Claw 4c" % quality_dots(0))

    def test_the_test_button_says_they_are_not_on_the_drop_list(self):
        self.env.lua.eval("NS.TestFilter")("quest, note, page")
        out = self.env.ev("FlushChat()")
        # The quest-class item, the flagged one and the quest starter: all three are left alone.
        self.assertEqual(out.count("not on the drop list anyway"), 3)

    def test_the_game_reports_the_flag_as_a_table_or_as_separate_values(self):
        for expression, expected in [
            ("{ isQuestItem = true }", True),
            ("{ questID = 5 }", True),
            ("{ isQuestItem = false, questID = 0 }", False),
            ("{}", False),
            ("true, nil, false", True),
            ("false, 7, false", True),
            ("false, nil, false", False),
            ("nil", False),
        ]:
            self.assertEqual(self.env.ev("NS.IsQuestFlag(%s)" % expression), expected, expression)

    def test_a_client_without_the_quest_info_call_still_excludes_the_quest_class(self):
        env = Env(setup="C_Container.GetContainerItemQuestInfo = nil")
        env.bag(QUEST_BAG)
        env.run("ResetState()")
        # Only the class can be checked there, so the flagged and quest-starting items are not known.
        # They are 1c each, so they come ahead of the 4c claw. The Quest-class item is still left out.
        self.assertEqual(env.order(), "Odd Grey Note, Torn Page, Chipped Claw")


class Acknowledgements(unittest.TestCase):
    """The one-time warnings before a delete that would otherwise happen with no question asked."""

    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag())
        self.env.run("ResetState()")

    def click(self):
        self.env.run('LDB.OnClick(nil, "LeftButton")')

    def popup(self, index=1):
        return self.env.ev("Popups[%d].which" % index)

    def text(self, index=1):
        return self.env.ev("Popups[%d].text" % index)

    def flag(self, key):
        return self.env.ev("NS.Get('%s')" % key)

    # An ordinary drop: a click on the bar item, or a typed /jd. One warning, one memory.

    def test_the_first_click_warns_and_deletes_nothing(self):
        self.click()
        self.assertEqual(self.popup(), "JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "")
        self.assertIn("[Chipped Claw]", self.text())  # it says exactly what would go
        self.assertIn("cannot be recovered", self.text())
        self.assertIn("won't be warned about this again", self.text())

    def test_typing_jd_the_first_time_gives_the_same_warning(self):
        self.env.cmd("")
        self.assertEqual(self.popup(), "JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "")
        self.assertIn("[Chipped Claw]", self.text())

    def test_the_warning_reads_the_same_from_a_click_and_from_typing(self):
        typed = Env()
        typed.bag(default_bag())
        typed.run("ResetState()")
        typed.cmd("")
        self.click()
        self.assertEqual(typed.ev("Popups[1].text"), self.text())

    def test_accepting_after_a_click_covers_typing_jd(self):
        self.click()
        self.env.accept_popup("JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "Chipped Claw")
        self.env.cmd("")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")  # at once
        self.assertEqual(self.env.popup_count(), 1)

    def test_accepting_after_typing_covers_a_click(self):
        self.env.cmd("")
        self.env.accept_popup("JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "Chipped Claw")
        self.click()
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")
        self.assertEqual(self.env.popup_count(), 1)

    def test_jd_with_a_count_is_warned_too_and_lists_every_stack(self):
        self.env.cmd("2")
        self.assertEqual(self.popup(), "JUNKDROP_ACK")
        self.assertIn("[Chipped Claw]", self.text())
        self.assertIn("[Broken Boar Tusk]", self.text())
        self.assertEqual(self.env.deleted(), "")
        self.env.accept_popup("JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")

    def test_accepting_remembers(self):
        self.click()
        self.env.accept_popup("JUNKDROP_ACK")
        self.assertTrue(self.flag("AckDrop"))

    def test_cancelling_deletes_nothing_and_it_asks_again_next_time(self):
        self.click()  # the pop-up is dismissed without pressing "I understand"
        self.env.cmd("")
        self.assertEqual(self.env.popup_count(), 2)
        self.assertEqual(self.env.deleted(), "")
        self.assertFalse(self.flag("AckDrop"))

    def test_listing_never_warns(self):
        self.env.cmd("list")
        self.env.cmd("list all")
        self.env.cmd("debug list")
        self.assertEqual(self.env.popup_count(), 0)

    def test_a_player_who_confirms_every_click_is_not_also_given_the_warning_on_a_click(self):
        self.env.set(ConfirmClick=True)
        self.click()
        self.assertEqual(self.popup(), "JUNKDROP_CONFIRM")
        self.assertEqual(self.env.popup_count(), 1)
        self.assertFalse(self.flag("AckDrop"))

    def test_a_better_than_poor_target_gets_only_its_own_confirmation(self):
        self.env.set(Include0=False, Include1=True)
        self.click()
        self.assertEqual(self.popup(), "JUNKDROP_CONFIRM_RUN")
        self.env.cmd("")
        self.assertEqual(self.popup(2), "JUNKDROP_CONFIRM_RUN")
        self.assertEqual(self.env.popup_count(), 2)
        self.assertFalse(self.flag("AckDrop"))

    def test_nothing_to_drop_shows_nothing(self):
        self.env.bag([("Linen Cloth", 1, 5, 20, 7)])
        self.click()
        self.env.cmd("")
        self.assertEqual(self.env.popup_count(), 0)

    # "/jd all": its own warning, and its own memory

    def test_all_warns_first_and_lists_what_it_would_delete(self):
        self.env.cmd("all")
        self.assertEqual(self.popup(), "JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "")
        self.assertIn("/jd all", self.text())
        self.assertIn("[Chipped Claw]", self.text())
        self.assertIn("[Broken Boar Tusk]", self.text())
        self.assertFalse(self.flag("AckAll"))

    def test_accepting_it_deletes_everything_and_it_never_asks_again(self):
        self.env.cmd("all")
        self.env.accept_popup("JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk")
        self.assertTrue(self.flag("AckAll"))
        self.env.bag([("Wolf Pelts", 0, 2, 6, 15)])
        self.env.cmd("all")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk, Wolf Pelts")
        self.assertEqual(self.env.popup_count(), 1)

    def test_all_with_nothing_to_drop_shows_nothing(self):
        self.env.bag([("Linen Cloth", 1, 5, 20, 7)])
        self.env.cmd("all")
        self.assertEqual(self.env.popup_count(), 0)

    def test_all_with_better_items_asks_its_own_question_instead(self):
        self.env.set(Include1=True)
        self.env.cmd("all")
        self.assertEqual(self.popup(), "JUNKDROP_CONFIRM_RUN")
        self.assertEqual(self.env.popup_count(), 1)

    def test_the_two_warnings_are_independent(self):
        self.click()
        self.env.accept_popup("JUNKDROP_ACK")
        self.env.cmd("all")
        self.assertEqual(self.popup(2), "JUNKDROP_ACK")  # accepting the drop warning did not cover "all"
        self.assertFalse(self.flag("AckAll"))

    def test_the_loot_note_button_is_not_covered_by_either(self):
        self.env.bag([("Chipped Claw", 0, 4, 1, 15)])
        self.env.loot([dict(name="Silk Cloth", quality=1, price=30)])
        self.env.fire("LOOT_OPENED")
        self.env.run("LootNote.DropButton._OnClick()")
        self.assertEqual(self.env.deleted(), "Chipped Claw")  # it deletes at once, as before
        self.assertEqual(self.env.popup_count(), 0)


class ResetConfirmation(unittest.TestCase):
    """Reset to defaults clears everything, so the button and /jd reset both ask first."""

    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag())
        self.env.run("ResetState()")
        # A player who has changed things and accepted both warnings.
        self.env.set(Label="short", Include2=True, Protect="knife", AckDrop=True, AckAll=True)

    def get(self, key):
        return self.env.ev("NS.Get('%s')" % key)

    def press_button(self):
        self.env.cmd("options")
        self.env.run("OptionsWindow.ResetButton._OnClick()")

    def changed(self):
        return (self.get("Label"), self.get("Include2"), self.get("Protect")) == ("short", True, "knife")

    def test_the_button_asks_first_and_changes_nothing_yet(self):
        self.press_button()
        self.assertEqual(self.env.ev("Popups[1].which"), "JUNKDROP_CONFIRM_RESET")
        self.assertTrue(self.changed())
        self.assertTrue(self.get("AckDrop"))

    def test_typing_jd_reset_asks_first_and_changes_nothing_yet(self):
        self.assertEqual(self.env.cmd("reset"), "")  # no chat line: the pop-up is the answer
        self.assertEqual(self.env.ev("Popups[1].which"), "JUNKDROP_CONFIRM_RESET")
        self.assertTrue(self.changed())

    def test_the_question_says_what_will_be_lost(self):
        text = self.env.ev("StaticPopupDialogs['JUNKDROP_CONFIRM_RESET'].text")
        self.assertIn("Never drop words", text)
        self.assertIn("one-time warnings", text)

    def test_confirming_from_the_button_resets_everything_including_both_warnings(self):
        self.press_button()
        self.env.accept_popup("JUNKDROP_CONFIRM_RESET")
        self.assertFalse(self.changed())
        self.assertEqual((self.get("Label"), self.get("Include2"), self.get("Protect")), ("full", False, ""))
        self.assertFalse(self.get("AckDrop"))
        self.assertFalse(self.get("AckAll"))

    def test_confirming_after_typing_jd_reset_does_the_same(self):
        self.env.cmd("reset")
        self.env.accept_popup("JUNKDROP_CONFIRM_RESET")
        self.assertEqual((self.get("Label"), self.get("Include2"), self.get("Protect")), ("full", False, ""))
        self.assertFalse(self.get("AckDrop"))

    def test_cancelling_changes_nothing(self):
        self.press_button()  # the pop-up is dismissed without pressing Reset
        self.env.cmd("reset")
        self.assertTrue(self.changed())
        self.assertTrue(self.get("AckDrop"))

    def test_the_warnings_really_return_after_a_confirmed_reset(self):
        self.env.cmd("reset")
        self.env.accept_popup("JUNKDROP_CONFIRM_RESET")
        self.env.run('LDB.OnClick(nil, "LeftButton")')
        self.assertEqual(self.env.ev("Popups[2].which"), "JUNKDROP_ACK")
        self.assertEqual(self.env.deleted(), "")

    def test_an_open_options_window_shows_the_defaults_afterwards(self):
        self.env.cmd("options")
        self.env.run("OptionsWindow.FilterBox:SetText('knife')")  # what the box shows now
        self.env.run("OptionsWindow.ResetButton._OnClick()")
        self.env.accept_popup("JUNKDROP_CONFIRM_RESET")
        self.assertEqual(self.env.ev("OptionsWindow.FilterBox._text"), "")

    def test_resetting_with_no_options_window_open_is_fine(self):
        self.env.cmd("reset")
        self.env.accept_popup("JUNKDROP_CONFIRM_RESET")
        self.assertEqual(self.env.ev("#Errors"), 0)

    def test_help_lists_it(self):
        self.assertIn("reset", self.env.cmd("help"))


# What a new player gets. Changing one of these changes everyone's first experience, so a test
# pins them: change the value here on purpose, together with the README and the options window.
EXPECTED_DEFAULTS = {
    "Label": "full", "Show": "both", "Dots": True, "ShowCount": True, "Coins": "icons", "TooltipRows": 5,
    "ConfirmClick": False, "ReportDrops": True,
    "Include0": True, "Include1": False, "Include2": False, "Include3": False, "Include4": False,
    "Order": "quality", "ConfirmHigher": True, "Protect": "",
    "Glow": True, "LootNote": True, "LootDrop": True,
    "AckDrop": False, "AckAll": False,
}


class Defaults(unittest.TestCase):
    def setUp(self):
        self.env = Env()

    def get(self, key):
        return self.env.ev("NS.Get('%s')" % key)

    def test_every_setting_starts_as_intended(self):
        for key, want in EXPECTED_DEFAULTS.items():
            self.assertEqual(self.get(key), want, key)

    def test_there_is_no_setting_without_a_pinned_default(self):
        count = self.env.ev("(function() local n = 0 for _ in pairs(NS.Defaults) do n = n + 1 end return n end)()")
        self.assertEqual(count, len(EXPECTED_DEFAULTS))

    def test_only_poor_items_can_be_dropped_until_the_player_chooses_otherwise(self):
        self.assertEqual([self.get("Include%d" % q) for q in range(5)], [True, False, False, False, False])

    def test_reset_to_defaults_restores_every_one(self):
        # Flip every setting away from its default, then reset.
        for key, want in EXPECTED_DEFAULTS.items():
            other = (not want) if isinstance(want, bool) else ("x" if isinstance(want, str) else want + 1)
            self.env.set(**{key: other})
        self.env.run("NS.Reset()")
        for key, want in EXPECTED_DEFAULTS.items():
            self.assertEqual(self.get(key), want, key)


if __name__ == "__main__":
    unittest.main()
