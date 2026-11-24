import importlib.util
import math
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from arcade import Arcade, Pickup, Shot


def run_game(seed, hz=30, assist=False):
    game = Arcade(seed)
    cues, waves = [], set()
    for frame in range(120 * hz):
        if assist:
            for enemy in game.enemies[:]:
                game.click(enemy.x, enemy.y)
        cues.extend(game.tick(frame / hz))
        waves.add(game.wave)
        if not game.playing:
            break
    return game, cues, waves


class ArcadeTests(unittest.TestCase):
    def test_seeded_games_reach_boss_and_can_win_or_die(self):
        win, cues, waves = run_game(0)
        self.assertEqual((win.phase, waves), ("victory", {1, 2, 3}))
        self.assertEqual(cues.count("boss"), 1)
        self.assertEqual(cues.count("victory"), 1)
        for cue in ("fire", "enemyHit", "enemyDefeated", "heroHurt", "powerup"):
            self.assertIn(cue, cues)
        loss, cues, waves = run_game(2)
        self.assertEqual((loss.phase, loss.player_hp), ("dead", 0))
        self.assertEqual(cues.count("death"), 1)
        self.assertFalse(loss.click(*loss.hero))
        self.assertFalse(list(loss.hit_rects()))
        self.assertEqual(loss.tick(500), [])
        assisted, _, _ = run_game(2, assist=True)
        self.assertEqual(assisted.phase, "victory")
        self.assertGreater(assisted.player_hp, 0)

    def test_tick_rate_pause_sleep_and_invalid_clock(self):
        for hz in (15, 60):
            game, cues, _ = run_game(2, hz)
            self.assertEqual((game.phase, game.player_hp), ("dead", 0))
            self.assertEqual(cues.count("death"), 1)
        game = Arcade(3)
        game.tick(5)
        game.tick(5.2)
        prior = game.time
        for clock in (4, 1000, float("nan"), 5000):
            game.tick(clock)
            self.assertEqual(game.time, prior)
        game.pause()
        game.tick(9000)
        self.assertEqual(game.time, prior)
        game.tick(9000.2)
        self.assertAlmostEqual(game.time-prior, .2)

    def test_randomized_counts_sizes_health_and_concurrent_limit(self):
        samples = [Arcade(seed) for seed in range(35)]
        self.assertEqual({s.total for s in samples}, {2, 3, 4})
        self.assertGreater(len({s.enemies[0].max_hp for s in samples}), 5)
        self.assertGreater(len({s.enemies[0].radius for s in samples}), 3)
        for game in samples:
            self.assertEqual(game.player_hp, 100)
            for frame in range(450):
                game.tick(frame/15)
                self.assertLessEqual(len(game.enemies), 3)
                self.assertLessEqual(len(game.pickups), 3)
                if not game.playing:
                    break

    def test_personal_score_requires_real_contribution_including_terminal_runs(self):
        for seed in (0, 2):
            auto, _, _ = run_game(seed)
            stats = auto.stats
            self.assertGreater(stats["kills"], 0)
            self.assertEqual(stats["deaths"] + stats["victories"], 1)
            self.assertEqual(stats["score"], 0)
            self.assertFalse(stats["engaged"] or stats["personalBoss"] or stats["bossLastHit"])
            self.assertEqual(stats["personalDeaths"] + stats["personalVictories"], 0)
        active, _, _ = run_game(2, assist=True)
        self.assertTrue(active.stats["personalBoss"])
        self.assertGreater(active.stats["personalKills"], 1)
        self.assertEqual(active.stats["personalVictories"], 1)
        self.assertEqual(active.stats["score"], active.stats["manualDamage"] + active.stats["killBonus"])

    def test_kill_credit_is_proportional_and_limited_to_remaining_hp(self):
        for manual_last in (False, True):
            game = Arcade(1)
            enemy = game.enemies[0]
            enemy.hp, enemy.max_hp = 13, 13
            enemy.kind = "boss"
            self.assertTrue(game.click(enemy.x, enemy.y))
            self.assertFalse(game.click(enemy.x, enemy.y))
            self.assertFalse(game.click(enemy.x+30, enemy.y))
            game.tick(0)
            game.tick(.2)
            if manual_last:
                game.click(enemy.x, enemy.y)
            else:
                game._damage(enemy, 9)
            stats = game.stats
            damage = 13 if manual_last else 9
            self.assertEqual(stats["assists"], 2 if manual_last else 1)
            self.assertEqual(stats["manualDamage"], damage)
            self.assertEqual(stats["personalKills"], 1)
            self.assertEqual(stats["lastHits"], int(manual_last))
            self.assertTrue(stats["personalBoss"])
            self.assertEqual(stats["bossLastHit"], manual_last)
            self.assertEqual(stats["killBonus"], 50*damage//13)
            self.assertEqual(stats["score"], damage+50*damage//13)

    def test_manual_pickups_score_only_if_they_improve_health_or_buff(self):
        game = Arcade(4)
        for i, kind in enumerate(("restore", "shield", "shield", "rapidFire")):
            item = Pickup(kind, 155, 75, 55+i)
            game.pickups.append(item)
            self.assertTrue(game.click(item.x, item.y))
            self.assertFalse(game.click(item.x, item.y))
        self.assertEqual(game.stats["manualPickups"], 2)
        self.assertEqual(game.stats["score"], 10)
        game.player_hp = 70
        item = Pickup("restore", *game.hero, 60)
        game.pickups.append(item)
        game.tick(0)
        game.tick(.1)
        self.assertEqual(game.player_hp, 95)
        self.assertEqual(game.stats["manualPickups"], 2)

    def test_click_uses_visible_sprite_and_powerups_in_front(self):
        game = Arcade(5)
        enemy = game.enemies[0]
        before = enemy.hp
        self.assertFalse(game.click(enemy.x + 50, enemy.y))
        self.assertFalse(game.click(enemy.x, enemy.y + enemy.radius + 3))
        self.assertLessEqual(9, before)
        self.assertTrue(game.click(enemy.x, enemy.y))
        self.assertEqual(enemy.hp, before-9)
        self.assertFalse(game.click(enemy.x, enemy.y), "Assist has a cooldown")
        game.player_hp = 85
        for i, kind in enumerate(("restore", "shield", "rapidFire")):
            game.pickups.append(Pickup(kind, enemy.x, enemy.y, i+100))
            self.assertTrue(game.click(enemy.x, enemy.y))
            self.assertEqual(len(game.pickups), 0)
        self.assertEqual((game.player_hp, game.shield, game.rapid_fire), (100, 4, 5))
        hx, hy = game.hero
        game.shots.append(Shot(hx, hy, 0, 0, 12, True))
        game.tick(0)
        game.tick(.1)
        self.assertEqual(game.player_hp, 100)
        self.assertEqual(len(game.shots), 0)
        self.assertLess(game.shield, 4)
        self.assertLess(game.rapid_fire, 5)

    def test_masks_match_rendered_enemy_ink_and_spare_hud_and_shots(self):
        game = Arcade(1, translate=lambda key: {"Welle {0}": "Wave {0}", "Boss": "Boss"}[key])
        enemy = game.enemies[0]
        enemy.x, enemy.y, enemy.radius = 150, 80, 15
        labels = []
        for kind in ("bug", "worm", "spore", "boss"):
            enemy.kind = kind
            pixels = set()

            def fill(x, y, w, h, color):
                for col in range(math.ceil(x-.5), math.ceil(x+w-.5)):
                    for row in range(math.ceil(y-.5), math.ceil(y+h-.5)):
                        pixels.add((col, row))

            game.paint(fill, lambda x, y, label: labels.append(label), lambda label: len(label)*5)
            for x in range(132, 168):
                for y in range(65, 96):
                    hit = game.target_at(x+.5, y+.5)
                    self.assertEqual(hit, (x, y) in pixels, (kind, x, y))
            strips = list(game.hit_rects())
            self.assertGreater(len(strips), 1)
            for x, y, w, h in strips:
                self.assertTrue(game.target_at(x+w/2, y+h/2))
            self.assertFalse(game.target_at(25, 12), "HUD is mouse-transparent")
            self.assertFalse(game.target_at(enemy.x, enemy.y+enemy.radius+3), "HP bar is mouse-transparent")
        self.assertIn("Wave 1", labels)
        self.assertIn("100%", labels)

    @unittest.skipUnless(importlib.util.find_spec("PySide6"), "PySide6 not installed")
    def test_real_qpainter_draws_ink_on_a_transparent_image(self):
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QImage, QPainter
        from PySide6.QtWidgets import QApplication
        app = QApplication.instance() or QApplication([])
        game = Arcade(0)
        image = QImage(300, 160, QImage.Format.Format_ARGB32_Premultiplied)
        image.fill(Qt.GlobalColor.transparent)
        painter = QPainter(image)
        try:
            game.draw(painter)
        finally:
            painter.end()
        self.assertEqual(image.pixelColor(100, 78).alpha(), 0)
        self.assertEqual(image.pixelColor(16, 12).alpha(), 255)
        enemy = game.enemies[0]
        self.assertEqual(image.pixelColor(int(enemy.x), int(enemy.y)).alpha(), 255)
        self.assertIsNotNone(app)


if __name__ == "__main__":
    unittest.main()
