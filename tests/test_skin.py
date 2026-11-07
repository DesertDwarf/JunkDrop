"""EllesmereUI theming: the options window and the loot note share one skin registration."""
import unittest

from harness import Env

FULL = [("Chipped Claw", 0, 4, 1, 15), ("Broken Boar Tusk", 0, 6, 1, 15), ("Hearthstone", 1, 0, 1, 15)]
TEXT_PARTS = 1 + 4 * 4  # the header, and four pieces of text in each of four item slots


class Themed(unittest.TestCase):
    def setUp(self):
        self.env = Env(ellesmere=True)
        self.env.run("ResetState()")
        self.env.bag(FULL)

    def open_loot(self):
        self.env.loot([dict(name="Silk Cloth", quality=1, price=30)])
        self.env.fire("LOOT_OPENED")

    def hidden(self, expression):
        return self.env.ev("rawget(%s, '_shown') == false" % expression)


class Registration(Themed):
    def test_one_registration_under_one_name_is_shared_by_every_window(self):
        # EllesmereUI ignores a second registration of the same name, so there must be only one.
        self.assertEqual(self.env.ev("#Registrations"), 1)
        self.assertEqual(self.env.ev("Registrations[1].name"), "JunkDrop")

    def test_the_options_window_is_themed(self):
        self.env.apply_skin()
        self.env.cmd("options")
        self.assertTrue(self.env.ev("SkinHas('Shell', OptionsWindow)"))

    def test_the_options_window_is_themed_when_it_is_built_before_the_skin_is_ready(self):
        self.env.cmd("options")
        self.env.apply_skin()
        self.assertTrue(self.env.ev("SkinHas('Shell', OptionsWindow)"))


class LootNote(Themed):
    def test_themed_when_the_skin_is_ready_before_the_note_is_built(self):
        self.env.apply_skin()
        self.open_loot()
        self.assertTrue(self.env.ev("SkinHas('Panel', LootNote)"))
        self.assertTrue(self.env.ev("SkinHas('Button', LootNote.DropButton)"))
        self.assertEqual(self.env.ev("SkinCount('Font')"), TEXT_PARTS)

    def test_themed_when_the_skin_arrives_after_the_note_exists(self):
        self.open_loot()
        self.assertFalse(self.env.ev("SkinHas('Panel', LootNote)"))
        self.env.apply_skin()
        self.assertTrue(self.env.ev("SkinHas('Panel', LootNote)"))
        self.assertEqual(self.env.ev("SkinCount('Font')"), TEXT_PARTS)

    def test_our_own_background_and_edge_step_aside_for_the_theme(self):
        self.env.apply_skin()
        self.open_loot()
        self.assertTrue(self.hidden("LootNote.Background"))
        for index in range(1, 5):
            self.assertTrue(self.hidden("LootNote.Edges[%d]" % index))

    def test_the_dialog_border_is_removed_so_the_theme_is_not_drawn_over_it(self):
        self.env.apply_skin()
        self.open_loot()
        self.assertTrue(self.env.ev("rawget(LootNote, '_backdrop') == false"))

    def test_the_dialog_border_is_removed_when_the_skin_arrives_later_too(self):
        self.open_loot()
        self.assertTrue(self.env.ev("type(LootNote._backdrop) == 'table'"))
        self.env.apply_skin()
        self.assertTrue(self.env.ev("rawget(LootNote, '_backdrop') == false"))

    def test_a_theme_that_fails_is_reported_and_the_note_still_works(self):
        self.env.apply_skin(fail_on="Panel")
        self.open_loot()
        self.assertTrue(self.env.ev("LootNote ~= nil and rawget(LootNote, '_shown') == true"))
        self.assertIn("simulated EllesmereUI failure", self.env.ev("Errors[1]"))
        self.assertEqual(self.env.ev("rawget(LootNote.Items[1].Top, '_text') ~= nil"), True)


class WithoutEllesmere(unittest.TestCase):
    def setUp(self):
        self.env = Env()  # no EllesmereUI at all
        self.env.run("ResetState()")
        self.env.bag(FULL)

    def open_loot(self, env=None):
        env = env or self.env
        env.loot([dict(name="Silk Cloth", quality=1, price=30)])
        env.fire("LOOT_OPENED")

    def test_the_note_looks_like_one_of_blizzards_dialog_windows(self):
        self.open_loot()
        self.assertTrue(self.env.ev("LootNote ~= nil and rawget(LootNote, '_shown') == true"))
        self.assertEqual(self.env.ev("LootNote._template"), "BackdropTemplate")  # modern clients need it
        # The exact paths, not just a name inside them: a mangled path draws nothing at all.
        self.assertEqual(self.env.ev("LootNote._backdrop.edgeFile"), "Interface/DialogFrame/UI-DialogBox-Border")
        self.assertEqual(self.env.ev("LootNote._backdrop.bgFile"), "Interface/DialogFrame/UI-DialogBox-Background")
        # The dark fill stays under the border, so the text is readable even if the art fails to draw.
        self.assertTrue(self.env.ev("rawget(LootNote.Background, '_shown') ~= false"))
        for index in range(1, 5):  # but the red edge lines are replaced by the border
            self.assertTrue(self.env.ev("rawget(LootNote.Edges[%d], '_shown') == false" % index))
        self.assertEqual(self.env.ev("#Errors"), 0)

    def test_a_client_that_cannot_draw_a_backdrop_keeps_a_plain_look(self):
        env = Env(setup="NoBackdrop = true")
        env.run("ResetState()")
        env.bag(FULL)
        self.open_loot(env)
        self.assertTrue(env.ev("LootNote ~= nil and rawget(LootNote, '_shown') == true"))
        self.assertTrue(env.ev("rawget(LootNote.Background, '_shown') == true"))
        for index in range(1, 5):
            self.assertTrue(env.ev("rawget(LootNote.Edges[%d], '_shown') == true" % index))

    def test_nothing_registers_and_there_is_no_skin(self):
        self.assertEqual(self.env.ev("#Registrations"), 0)
        self.assertIsNone(self.env.ev("NS.Skin"))


if __name__ == "__main__":
    unittest.main()
