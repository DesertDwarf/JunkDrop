import unittest

from harness import Env, default_bag, quality_dots


class Fresh(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag())
        self.env.run("ResetState()")


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
        self.env.set(Include1=True, ConfirmHigher=False)
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


if __name__ == "__main__":
    unittest.main()
