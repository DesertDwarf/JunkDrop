import unittest

from harness import Env, default_bag

TOOLS = [
    ("Skinning Knife", 1, 2, 1, 2),
    ("Fishing Pole", 1, 4, 1, 2),
    ("Large Black Bag", 1, 1, 1, 1),
]
EVERYTHING = "Chipped Claw, Broken Boar Tusk, Large Black Bag, Skinning Knife, Wooden Sword, Fishing Pole, Linen Cloth"


class Filter(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag() + TOOLS)
        self.env.run("ResetState()")
        self.env.set(Include1=True)

    def test_nothing_is_protected_by_default(self):
        self.assertEqual(self.env.order(), EVERYTHING)

    def test_protects_by_partial_name(self):
        self.env.set(Protect="knife, fishing pole, bag")
        self.assertEqual(self.env.order(), "Chipped Claw, Broken Boar Tusk, Wooden Sword, Linen Cloth")

    def test_ignores_case_spaces_and_empty_words(self):
        self.env.set(Protect="  KNIFE ,, fish  ,")
        self.assertEqual(
            self.env.order(),
            "Chipped Claw, Broken Boar Tusk, Large Black Bag, Wooden Sword, Linen Cloth",
        )

    def test_applies_to_poor_items_too(self):
        self.env.set(Protect="claw")
        self.assertNotIn("Chipped Claw", self.env.order())

    def test_words_are_plain_text_not_patterns(self):
        self.env.set(Protect="a.*e")
        self.assertEqual(self.env.order(), EVERYTHING)

    def test_an_empty_filter_protects_nothing(self):
        self.env.set(Protect="")
        self.assertEqual(self.env.order(), EVERYTHING)

    def test_all_leaves_protected_items_alone(self):
        self.env.set(Protect="knife, fishing pole, bag", ConfirmHigher=False)
        self.env.cmd("all")
        self.assertEqual(self.env.deleted(), "Chipped Claw, Broken Boar Tusk, Wooden Sword, Linen Cloth")

    def test_the_bar_item_never_offers_a_protected_item(self):
        self.env.set(Protect="knife")
        self.env.run('LDB.OnClick(nil, "LeftButton")')
        self.assertNotIn("Skinning Knife", self.env.ev("Popups[1] and Popups[1].text or ''"))
        self.env.set(Protect="claw, tusk, sword, cloth, bag, pole, knife")
        self.assertTrue(self.env.bar_text().endswith("no junk"))


class TestButton(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(default_bag() + TOOLS)
        self.env.run("ResetState()")

    def press_test(self, words):
        self.env.lua.eval("NS.TestFilter")(words)
        return self.env.ev("FlushChat()")

    def test_says_whether_a_match_is_being_kept_safe(self):
        self.env.set(Include1=True)
        out = self.press_test("knife, bag")
        self.assertIn("matches 2 stack(s)", out)
        self.assertIn("[Skinning Knife] x1 - kept safe", out)
        self.assertIn("[Large Black Bag] x1 - kept safe", out)

    def test_says_when_an_item_was_not_on_the_list_anyway(self):
        self.assertIn("not on the drop list anyway", self.press_test("knife"))

    def test_no_match_and_empty_input(self):
        self.assertIn("matches nothing", self.press_test("zzz"))
        self.assertIn("Type one or more words", self.press_test("   "))


if __name__ == "__main__":
    unittest.main()
