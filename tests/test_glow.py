import unittest

from harness import Env

# Slot 1 and 2 are Poor, slot 3 is Common (not eligible unless allowed).
BAG = [
    ("Chipped Claw", 0, 4, 1, 15),
    ("Broken Boar Tusk", 0, 6, 1, 15),
    ("Linen Cloth", 1, 5, 20, 7),
]
EMPTY = '{ "", -1, 0, 0, 0 }'
RED = (1.0, 0.12, 0.08)


class Glow(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.env.bag(BAG)
        self.env.run("ResetState(); BagsOpen = true; FireEvents()")  # fires PLAYER_LOGIN
        self.repaint()

    def repaint(self):
        self.env.run("EUI_Bags.RefreshInventory()")

    def lit(self):
        return self.env.ev("GlowingSlots()")

    def refresh(self):
        """What the addon does after a bag or setting change."""
        self.env.next_frame()
        self.env.run("Refreshes = 0; NS.RefreshGlow()")
        return self.env.ev("Refreshes")

    def test_registers_a_painter_at_login(self):
        self.assertTrue(self.env.ev("Painters['JunkDrop'] ~= nil"))

    def test_only_the_first_stack_in_drop_order_glows_and_pulses(self):
        self.assertEqual(self.lit(), "1")
        self.assertTrue(self.env.ev("GlowPulsing(1)"))

    def test_is_drawn_as_a_red_halo_and_a_solid_border(self):
        halos = self.env.ev("(function() local o = {} for _, t in ipairs(Textures) do if rawget(t, '_path') then o[#o+1] = t end end return o end)()")
        edges = self.env.ev("(function() local o = {} for _, t in ipairs(Textures) do if rawget(t, '_solid') then o[#o+1] = t end end return o end)()")
        halos, edges = list(halos.values()), list(edges.values())
        self.assertEqual(len(halos), 2)
        self.assertEqual({tuple(round(v, 2) for v in h._color.values()) for h in halos}, {RED})
        self.assertEqual({h._blend for h in halos}, {"ADD"})
        self.assertEqual({(round(h._w, 1), round(h._h, 1)) for h in halos}, {(77.7, 77.7)})  # 37 x 2.1
        self.assertEqual(len(edges), 4)
        self.assertEqual({tuple(round(v, 2) for v in e._solid.values()) for e in edges}, {RED + (1.0,)})
        self.assertEqual(sorted((e._w, e._h) for e in edges), [(0, 2), (0, 2), (2, 0), (2, 0)])

    def test_moves_when_the_target_changes_and_repaints_once(self):
        self.env.run("bag[1] = %s" % EMPTY)
        self.assertEqual(self.refresh(), 1)
        self.assertEqual(self.lit(), "2")

    def test_does_not_repaint_when_nothing_changed(self):
        self.assertEqual(self.refresh(), 0)

    def test_turning_it_off_clears_it_and_on_brings_it_back(self):
        self.env.run("Refreshes = 0")
        self.env.set(Glow=False)
        self.assertEqual((self.env.ev("Refreshes"), self.lit()), (1, ""))
        self.env.next_frame()
        self.env.set(Glow=True)
        self.assertEqual(self.lit(), "1")

    def test_follows_the_quality_order_and_protect_settings(self):
        self.env.next_frame()
        self.env.set(Include1=True, Protect="claw, tusk")
        self.assertEqual(self.lit(), "3")  # both Poor items protected, so the Common stack is next
        self.env.next_frame()
        self.env.set(Protect="claw")
        self.assertEqual(self.lit(), "2")

    def test_nothing_glows_when_nothing_is_eligible(self):
        self.env.run("for i = 1, #bag do bag[i] = %s end" % EMPTY)
        self.refresh()
        self.assertEqual(self.lit(), "")

    def test_does_not_force_a_repaint_in_combat_then_catches_up(self):
        self.env.run("bag[1] = %s; InCombat = true" % EMPTY)
        self.assertEqual(self.refresh(), 0)
        self.env.run("InCombat = false")
        self.assertEqual(self.refresh(), 1)
        self.assertEqual(self.lit(), "2")

    def test_closed_bags_are_not_repainted_but_paint_the_glow_when_opened(self):
        self.env.run("BagsOpen = false")
        self.env.next_frame()
        self.env.run("Refreshes = 0")
        self.env.set(Glow=False)
        self.env.next_frame()
        self.env.set(Glow=True)
        self.assertEqual(self.env.ev("Refreshes"), 0)
        self.repaint()
        self.assertEqual(self.lit(), "1")

    def test_a_slot_without_an_overlay_frame_is_skipped(self):
        self.env.run("Buttons[1]._textOverlay = nil")
        self.env.next_frame()
        self.repaint()  # must not raise
        self.assertEqual(self.env.ev("Refreshes >= 1"), True)

    def test_one_bag_scan_per_frame_not_per_slot(self):
        self.env.run("""
            Scans = 0
            local real = NS.GetJunkStacks
            NS.GetJunkStacks = function(...) Scans = Scans + 1; return real(...) end
            Now = Now + 1
            for slot, button in ipairs(Buttons) do Painters['JunkDrop'](button, { bag = 0, slot = slot }) end
        """)
        self.assertEqual(self.env.ev("Scans"), 1)
        self.env.run("Now = Now + 1; Scans = 0; for slot, b in ipairs(Buttons) do Painters['JunkDrop'](b, { bag = 0, slot = slot }) end")
        self.assertEqual(self.env.ev("Scans"), 1)  # a new frame looks again, so changes are seen


if __name__ == "__main__":
    unittest.main()
