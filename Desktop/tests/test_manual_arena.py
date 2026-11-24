"""Manual Highscores rounds use the local engine even with ambient play disabled."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from arcade import Arcade
from desktop_core import Preferences
from local_arena import LocalArenaRound


class ManualArenaTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.prefs = Preferences(Path(tmp.name) / "settings.json")
        self.round = LocalArenaRound(str)

    def start(self, now=5, existing=None, online=False):
        return self.round.start(now=now, grave_until=self.prefs["graveUntil"], online_playing=online, existing=existing)

    def test_start_in_foreground_offline_with_ambient_disabled(self):
        self.prefs.update(arcade=False, visible=False, activePlay=False, reduce=True)
        self.assertTrue(self.start())
        self.assertFalse(self.start())
        self.assertFalse(self.round.click(1, 1))
        x, y, w, h = next(self.round.scene.hit_rects())
        self.assertTrue(self.round.click(x+w/2, y+h/2))
        self.assertGreater(self.round.scene.stats["manualDamage"], 0)
        self.assertFalse(self.prefs["activePlay"] or self.prefs["arcade"])
        self.assertEqual(self.prefs["rankedFinished"], [])
        self.assertFalse(self.round.finish(self.prefs, 5))

    def test_cleanup_and_clock_pause_when_tab_is_hidden(self):
        self.start()
        self.round.tick(1, True)
        self.round.tick(1.2, True)
        last = self.round.scene.time
        self.round.tick(15, False)
        self.round.tick(30, True)
        self.assertEqual(self.round.scene.time, last)
        self.round.tick(30.1, True)
        self.assertTrue(self.round.paused)
        self.assertEqual(self.round.scene.time, last)
        x, y, w, h = next(self.round.scene.hit_rects())
        self.assertFalse(self.round.click(x+w/2, y+h/2))
        self.round.resume(50)
        self.round.tick(50.1, True)
        self.assertFalse(self.round.paused)
        self.assertGreater(self.round.scene.time, last)
        self.round.clear()
        self.assertIsNone(self.round.scene)
        self.assertFalse(self.round.finish(self.prefs, 5))
        self.assertEqual(self.prefs["highscore"], {})

    def test_transferred_overlay_run_preserves_id_and_counts_once_outside_online(self):
        scene = Arcade(seed=43)
        scene.wave, scene.enemies = 3, []
        scene._start_wave()
        scene.enemies[0].hp = 1
        self.assertFalse(self.start(existing=(scene, "old"), online=True))
        self.assertTrue(self.start(existing=(scene, "old")))
        self.assertIs(self.round.scene, scene)
        x,y,w,h = next(scene.hit_rects())
        self.round.click(x+w/2, y+h/2)
        self.assertEqual(self.round.phase, "victory")
        self.assertTrue(self.round.finish(self.prefs, 30))
        self.assertFalse(self.round.finish(self.prefs, 35))
        self.assertEqual(self.prefs["finished"], ["old"])
        self.assertEqual(self.prefs["highscore"]["personalKills"], 1)
        self.assertEqual(self.prefs["highscore"]["personalVictories"], 1)
        self.assertEqual(self.prefs["rankedFinished"], [])
        self.assertEqual(self.prefs["graveUntil"], 0)

    def test_grave_deadline_survives_restart_and_freezes_exactly_five_minutes(self):
        self.start()
        self.round.scene._finish("dead")
        self.assertTrue(self.round.finish(self.prefs, 10))
        self.assertFalse(self.round.finish(self.prefs, 250))
        self.assertEqual(self.prefs["graveUntil"], 310)
        self.assertEqual(Preferences(self.prefs.path)["graveUntil"], 310)
        self.assertFalse(self.start(now=309.999))
        self.assertTrue(self.start(now=310))
        self.assertEqual(self.prefs["highscore"], {})  # unattended round

if __name__ == "__main__":
    unittest.main()
