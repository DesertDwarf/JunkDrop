import unittest

from harness import Env

EMPTY = ("", -1, 0, 0, 0)

# A full bag: no empty slot. The Poor items are what JunkDrop would drop (4c, then 6c).
FULL = [
    ("Chipped Claw", 0, 4, 1, 15),
    ("Broken Boar Tusk", 0, 6, 1, 15),
    ("Hearthstone", 1, 0, 1, 15),
]

PLAN = """
function PlanSummary()
  local bags, room = NS.ReadBags()
  local out = {}
  for _, r in ipairs(NS.PlanLoot(NS.ReadLoot(), bags, room, NS.GetJunkStacks())) do
    out[#out + 1] = (r.Item.Name or r.Item.Link) .. ":" .. r.Action .. (r.Candidate and ("<" .. r.Candidate.Name) or "")
  end
  return table.concat(out, " | ")
end
"""


def thing(name, price, **extra):
    """A loot item worth `price` copper each."""
    return dict(name=name, quality=1, price=price, **extra)


class LootCase(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.run("ResetState()")
        self.env.run(PLAN)
        self.env.bag(FULL)

    def open(self, *items):
        self.env.loot(list(items))
        self.env.fire("LOOT_OPENED")

    def plan(self):
        return self.env.ev("PlanSummary()")

    def shown(self):
        return self.env.ev("LootNote ~= nil and rawget(LootNote, '_shown') == true")

    def parts(self, index=1):
        """One item's slot in the note: ((top label, top text), (bottom label, bottom text))."""
        def text(part):
            return self.env.ev("LootNote.Items[%d].%s._text" % (index, part))
        return (text("TopLabel"), text("Top")), (text("BottomLabel"), text("Bottom"))

    def row(self, index=1):
        """Everything one item's slot says, as a single string."""
        return " ".join(piece for pair in self.parts(index) for piece in pair)

    def line_heights(self):
        """How far down the note each text line sits, top to bottom (only lines that have text)."""
        return [int(y) for y in self.env.ev(
            "(function() local t = {} for _, s in ipairs(LootNote.Items) do"
            " for _, line in ipairs({ s.Top, s.Bottom }) do"
            "  if line._text ~= '' and rawget(line, '_points') then t[#t+1] = -line._points[1][5] end"
            " end end return table.concat(t, ',') end)()").split(",")]

    def button_shown(self):
        return self.env.ev("rawget(LootNote.DropButton, '_shown') == true")


class WhenBagsAreFull(LootCase):
    def test_nothing_to_say_when_the_loot_fits(self):
        self.env.bag(FULL + [EMPTY])
        self.open(thing("Silk Cloth", 30))
        self.assertFalse(self.shown())

    def test_better_loot_is_worth_taking_and_names_what_to_drop(self):
        self.open(thing("Silk Cloth", 30))
        self.assertEqual(self.plan(), "Silk Cloth:swap<Chipped Claw")
        self.assertTrue(self.shown())
        # A checklist in the order to do it: drop the bag item first, then take the loot below it.
        (top_label, top), (bottom_label, bottom) = self.parts()
        self.assertIn("Drop", top_label)
        self.assertIn("[Chipped Claw]", top)
        self.assertIn("Take", bottom_label)
        self.assertIn("[Silk Cloth]", bottom)

    def test_cheaper_loot_is_to_be_skipped_and_offers_no_drop(self):
        self.open(thing("Frayed Rag", 2))
        self.assertEqual(self.plan(), "Frayed Rag:skip<Chipped Claw")
        (top_label, top), (_, bottom) = self.parts()
        self.assertIn("Skip", top_label)
        self.assertIn("[Frayed Rag]", top)
        self.assertIn("not worth more than", bottom)
        self.assertIn("[Chipped Claw]", bottom)
        self.assertFalse(self.button_shown())

    def test_loot_worth_the_same_is_skipped(self):
        self.open(thing("Spare Claw", 4))
        self.assertEqual(self.plan(), "Spare Claw:skip<Chipped Claw")

    def test_a_stack_is_valued_as_a_whole(self):
        self.open(thing("Wolf Pelts", 2, qty=6))  # 12c beats the 4c claw
        self.assertEqual(self.plan(), "Wolf Pelts:swap<Chipped Claw")

    def test_the_best_loot_gets_the_first_stacks_to_go(self):
        self.open(thing("Frayed Rag", 5), thing("Silk Cloth", 50))
        self.assertEqual(self.plan(), "Silk Cloth:swap<Chipped Claw | Frayed Rag:skip<Broken Boar Tusk")

    def test_two_good_items_replace_two_stacks(self):
        self.open(thing("Silk Cloth", 50), thing("Wool Cloth", 20))
        self.assertEqual(self.plan(), "Silk Cloth:swap<Chipped Claw | Wool Cloth:swap<Broken Boar Tusk")

    def test_when_nothing_is_left_to_drop_it_says_so(self):
        self.open(thing("Silk Cloth", 50), thing("Wool Cloth", 20), thing("Linen Cloth", 10))
        self.assertTrue(self.plan().endswith("Linen Cloth:none"))

    def test_a_quest_item_is_always_worth_taking(self):
        self.open(dict(name="Strange Note", quality=1, price=0, quest=True))
        self.assertEqual(self.plan(), "Strange Note:swap<Chipped Claw")
        (top_label, _), (bottom_label, bottom) = self.parts()
        self.assertEqual((("Drop" in top_label), ("Take" in bottom_label)), (True, True))
        self.assertIn("(quest item)", bottom)

    def test_an_item_with_no_price_is_left_to_the_player(self):
        self.open(thing("Odd Trinket", 0))
        self.assertEqual(self.plan(), "Odd Trinket:unknown")
        self.assertIn("your call", self.row())

    def test_money_and_looted_slots_are_ignored(self):
        self.open(dict(name="Coins", quality=1, price=0, slot=2), dict(name="Taken", quality=1, price=9, slot=0))
        self.assertFalse(self.shown())

    def test_protected_items_are_never_offered_for_dropping(self):
        self.env.set(Protect="claw")
        self.open(thing("Silk Cloth", 50))
        self.assertEqual(self.plan(), "Silk Cloth:swap<Broken Boar Tusk")


class FullMeansNoRoom(LootCase):
    def test_joining_a_partly_filled_stack_needs_no_slot(self):
        self.env.bag(FULL + [("Linen Cloth", 1, 5, 15, 7, 20)])  # room for 5 more
        self.open(thing("Linen Cloth", 5, qty=5, max=20))
        self.assertFalse(self.shown())

    def test_too_many_for_the_stack_needs_a_slot(self):
        self.env.bag(FULL + [("Linen Cloth", 1, 5, 15, 7, 20)])
        self.open(thing("Linen Cloth", 5, qty=6, max=20))
        self.assertTrue(self.shown())

    def test_one_free_slot_takes_only_one_of_two_items(self):
        self.env.bag(FULL + [EMPTY])
        self.open(thing("Silk Cloth", 50), thing("Wool Cloth", 20))
        self.assertEqual(self.plan(), "Wool Cloth:swap<Chipped Claw")

    def test_a_specialty_bag_with_room_takes_matching_items_only(self):
        self.env.bag(FULL + [EMPTY])
        self.env.run("BagFamilies[0] = 4")  # the only free slot is in a herb-type bag
        self.open(thing("Silverleaf", 9, family=4))
        self.assertFalse(self.shown())
        self.open(thing("Silk Cloth", 50))  # an ordinary item cannot use it
        self.assertTrue(self.shown())

    def test_dropping_from_a_specialty_bag_does_not_make_room_for_other_items(self):
        self.env.run("BagFamilies[0] = 4")
        self.open(thing("Silk Cloth", 50))
        self.assertEqual(self.plan(), "Silk Cloth:none")


class TheNoteAndItsButton(LootCase):
    def test_it_goes_away_when_the_loot_window_closes(self):
        self.open(thing("Silk Cloth", 30))
        self.env.fire("LOOT_CLOSED")
        self.assertFalse(self.shown())

    def test_it_can_be_turned_off(self):
        self.env.set(LootNote=False)
        self.open(thing("Silk Cloth", 30))
        self.assertFalse(self.shown())

    def test_turning_it_off_while_open_hides_it(self):
        self.open(thing("Silk Cloth", 30))
        self.env.set(LootNote=False)
        self.assertFalse(self.shown())

    def test_the_button_appears_only_for_suggested_drops(self):
        self.open(thing("Silk Cloth", 30))
        self.assertTrue(self.button_shown())

    def test_the_button_can_be_turned_off(self):
        self.env.set(LootDrop=False)
        self.open(thing("Silk Cloth", 30))
        self.assertTrue(self.shown())
        self.assertFalse(self.button_shown())

    def test_the_button_drops_the_suggested_stack_and_the_note_then_clears(self):
        self.open(thing("Silk Cloth", 30))
        self.env.run("LootNote.DropButton._OnClick()")
        self.assertEqual(self.env.deleted(), "Chipped Claw")
        self.env.fire("BAG_UPDATE_DELAYED")  # there is room now
        self.assertFalse(self.shown())

    def test_the_button_keeps_the_confirmation_for_better_items(self):
        self.env.bag([("Wooden Sword", 1, 3, 1, 2)])
        self.env.set(Include0=False, Include1=True)
        self.open(thing("Silk Cloth", 30))
        self.env.run("LootNote.DropButton._OnClick()")
        self.assertEqual((self.env.deleted(), self.env.popup_count()), ("", 1))
        self.env.accept_popup()
        self.assertEqual(self.env.deleted(), "Wooden Sword")

    def test_looting_the_item_clears_the_note(self):
        self.open(thing("Silk Cloth", 30))
        self.env.run("Loot[1].slot = 0")
        self.env.fire("LOOT_SLOT_CLEARED")
        self.assertFalse(self.shown())

    def test_an_item_whose_data_arrives_late_is_judged_when_it_does(self):
        self.open(thing("Silk Cloth", 30, uncached=True))
        self.assertEqual(self.plan(), "[Silk Cloth]:pending")  # the client does not know the item yet
        self.assertIn("Checking this item", self.row())
        self.env.run("Loot[1].uncached = false")
        self.env.fire("GET_ITEM_INFO_RECEIVED")
        self.assertEqual(self.plan(), "Silk Cloth:swap<Chipped Claw")
        self.assertTrue(self.shown())

    def test_lines_never_overlap_and_the_note_is_tall_enough_for_them_and_the_button(self):
        self.open(thing("Silk Cloth", 50), thing("Wool Cloth", 20))
        heights = self.line_heights()
        self.assertEqual(len(heights), 4)  # two lines for each of two items
        self.assertEqual(heights, sorted(heights))
        for above, below in zip(heights, heights[1:]):
            self.assertGreaterEqual(below - above, 16)  # a line is 16 tall
        self.assertTrue(self.button_shown())
        # The last line, then a gap and the button, then the padding, must all fit.
        self.assertGreaterEqual(self.env.ev("LootNote._h"), heights[-1] + 16 + 8 + 22 + 14)

    def test_the_note_is_as_wide_as_the_loot_window_but_not_narrower_than_it_can_read(self):
        self.env.run("LootFrame = CreateFrame('Frame'); LootFrame:SetSize(400, 200)")
        self.open(thing("Silk Cloth", 30))
        self.assertEqual(self.env.ev("LootNote._w"), 400)
        self.env.run("LootFrame:SetSize(200, 200)")
        self.env.fire("LOOT_SLOT_CLEARED")
        self.assertEqual(self.env.ev("LootNote._w"), 340)

    def test_more_items_than_rows_says_how_many_are_hidden(self):
        self.open(*[thing("Item %d" % n, 100 - n) for n in range(1, 9)])
        self.assertIn("...and 5 more", self.row(4))  # three items shown, five not


if __name__ == "__main__":
    unittest.main()
