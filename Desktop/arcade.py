"""Claw'd's transparent, fixed-step 300 × 160 arcade. Coordinates start at the top left.

The simulation runs without Qt. draw() paints into the caller's existing QPainter.
hit_rects() describes interactive ink for window masks; click() tests the same pixels.
"""

from dataclasses import dataclass
from functools import lru_cache
from math import ceil, floor, hypot, inf, isfinite, sin, tau
from random import Random


@dataclass
class Enemy:
    kind: str
    x: float
    y: float
    radius: int
    hp: int
    max_hp: int
    home_x: float
    home_y: float
    swing: float
    angle: float
    next_fire: float
    serial: int
    hurt: float = 0.0
    manual_damage: int = 0


@dataclass
class Pickup:
    kind: str
    x: float
    y: float
    serial: int
    radius: int = 7


@dataclass
class Shot:
    x: float
    y: float
    vx: float
    vy: float
    damage: int
    hostile: bool


class Arcade:
    width, height = 300, 160
    step = 1 / 60

    def __init__(self, seed=None, translate=None):
        self.random = Random(seed)
        self.translate = translate or str
        self.phase, self.wave, self.player_hp = "wave", 1, 100
        self.hero = (43.0, 83.0)
        self.time = self.remainder = 0.0
        self.last_tick = None
        self.enemies, self.shots, self.pickups = [], [], []
        self._cues = []
        self._serial = self.kills = 0
        self._assists = self._manual_damage = self._manual_pickups = 0
        self._personal_kills = self._last_hits = self._kill_bonus = 0
        self._personal_boss = self._boss_last_hit = False
        self._drop_order = []
        self.next_assist = self.shield_until = self.rapid_until = 0.0
        self.hurt_until = self.fire_until = 0.0
        self.next_hero_fire = 0.5
        self._dodge = self.random.uniform(0, tau)
        self._start_wave()

    @property
    def playing(self):
        return self.phase in ("wave", "boss")

    @property
    def shield(self):
        return max(0.0, self.shield_until - self.time)

    @property
    def rapid_fire(self):
        return max(0.0, self.rapid_until - self.time)

    @property
    def stats(self):
        """Detached run snapshot. An unassisted game always has zero personal score."""
        engaged = self._manual_damage > 0 or self._manual_pickups > 0
        victory, death = self.phase == "victory", self.phase == "dead"
        return {
            "assists": self._assists, "manualDamage": self._manual_damage, "manualPickups": self._manual_pickups,
            "kills": self.kills, "personalKills": self._personal_kills, "lastHits": self._last_hits,
            "killBonus": self._kill_bonus, "bossDefeated": victory, "personalBoss": self._personal_boss,
            "bossLastHit": self._boss_last_hit,
            "deaths": int(death), "victories": int(victory), "engaged": engaged,
            "personalDeaths": int(engaged and death), "personalVictories": int(engaged and victory),
            "score": self._manual_damage + 5*self._manual_pickups + self._kill_bonus,
        }

    def tick(self, now):
        """Return new sound cues once. Long gaps never advance unseen gameplay."""
        if not isfinite(now):
            self.pause()
        elif self.last_tick is None:
            self.last_tick = now
        elif now >= self.last_tick:
            delta, self.last_tick = now - self.last_tick, now
            if self.playing and delta <= 0.35:
                self.remainder += delta
                while self.remainder + 1e-10 >= self.step and self.playing:
                    self.remainder = max(0, self.remainder - self.step)
                    self._advance(self.step)
            else:
                self.remainder = 0
        cues, self._cues = self._cues, []
        return cues

    def pause(self):
        self.last_tick = None
        self.remainder = 0.0

    def _cue(self, cue):
        if cue not in self._cues:
            self._cues.append(cue)

    def _id(self):
        self._serial += 1
        return self._serial

    def _start_wave(self):
        self.spawned = self.defeated = 0
        self.next_wave = inf
        if self.wave == 3:
            self.phase, self.total = "boss", 1
            self._cue("boss")
        else:
            self.total = self.random.randint(self.wave + 1, self.wave + 3)
        self._spawn()

    def _spawn(self):
        r = self.random
        boss = self.phase == "boss"
        kind = "boss" if boss else r.choice(("bug", "worm", "spore"))
        radius = r.randint(16, 20) if boss else r.randint(6, 11)
        hp = r.randint(95, 145) if boss else r.randint(8 + self.wave * 2, 18 + self.wave * 4)
        home_x, home_y = r.uniform(166, 258), r.uniform(47, 115)
        self.enemies.append(Enemy(kind, 279, home_y, radius, hp, hp, home_x, home_y,
                                  r.uniform(7, 17), r.uniform(0, tau), self.time + r.uniform(.55, 1.55), self._id()))
        self.spawned += 1
        self.next_spawn = self.time + r.uniform(1, 1.65)

    def _advance(self, dt):
        self.time += dt
        if self.time >= self.next_wave:
            self.wave += 1
            self._start_wave()
        elif self.time >= self.next_spawn and self.spawned < self.total and len(self.enemies) < 3:
            self._spawn()
        self._move_hero(dt)
        hx, hy = self.hero
        for enemy in self.enemies:
            enemy.hurt = max(0.0, enemy.hurt - dt / .22)
            enemy.x = max(enemy.home_x, enemy.x - 29 * dt)
            enemy.y = enemy.home_y - enemy.swing * sin(self.time * 1.05 + enemy.angle)
            if self.time >= enemy.next_fire:
                boss = enemy.kind == "boss"
                for offset in ((-19, 0, 19) if boss else (0,)):
                    aim = (hx, hy + offset + self.random.uniform(-4, 4))
                    damage = self.random.randint(10, 17) if boss else self.random.randint(6, 11)
                    self._fire(enemy.x, enemy.y, aim, 133 if boss else 112, damage, True)
                enemy.next_fire = self.time + (self.random.uniform(1.1, 1.65) if boss else self.random.uniform(1.7, 2.8))
        if self.time >= self.next_hero_fire and self.enemies:
            target = min(self.enemies, key=lambda enemy: enemy.x)
            self._fire(hx + 8, hy, (target.x, target.y), 259, self.random.randint(6, 10), False)
            self.next_hero_fire = self.time + (.27 if self.rapid_fire else .78)
            self.fire_until = self.time + .18
            self._cue("fire")
        self._move_shots(dt)

    def _move_hero(self, dt):
        hx, hy = self.hero
        desired = 83 - 27 * sin(self.time * .86 + self._dodge)
        nearest = min(self.pickups, key=lambda item: item.x, default=None)
        if nearest and nearest.x < hx + 50:
            desired = nearest.y
        hy += max(-33 * dt, min(33 * dt, desired - hy))
        self.hero = (hx, hy)
        for item in self.pickups[:]:
            item.x -= 62 * dt
            if hypot(hx - item.x, hy - item.y) <= item.radius + 8:
                self._collect(item)
            elif item.x < 0:
                self.pickups.remove(item)

    def _fire(self, x, y, target, speed, damage, hostile):
        dx, dy = target[0] - x, target[1] - y
        factor = speed / max(.001, hypot(dx, dy))
        self.shots.append(Shot(x, y, dx * factor, dy * factor, damage, hostile))

    def _move_shots(self, dt):
        moving, self.shots = self.shots, []
        hx, hy = self.hero
        for shot in moving:
            shot.x += shot.vx * dt
            shot.y += shot.vy * dt
            if shot.hostile and hypot(shot.x - hx, shot.y - hy) <= 10:
                if not self.shield:
                    self.player_hp = max(0, self.player_hp - shot.damage)
                    self.hurt_until = self.time + .32
                    self._cue("heroHurt")
                    if self.player_hp == 0:
                        self._finish("dead")
                        return
                continue
            if not shot.hostile:
                target = next((e for e in self.enemies if hypot(shot.x - e.x, shot.y - e.y) <= e.radius + 2), None)
                if target:
                    self._damage(target, shot.damage)
                    if not self.playing:
                        return
                    continue
            if -4 <= shot.x <= self.width + 4 and -4 <= shot.y <= self.height + 4:
                self.shots.append(shot)

    def _damage(self, enemy, amount, manual=False):
        effective_damage = min(enemy.hp, amount)
        if manual and effective_damage > 0:
            self._assists += 1
            self._manual_damage += effective_damage
            enemy.manual_damage += effective_damage
        enemy.hp, enemy.hurt = enemy.hp - effective_damage, 1
        self._cue("enemyHit")
        if enemy.hp:
            return
        self.enemies.remove(enemy)
        self.defeated += 1
        self.kills += 1
        if manual:
            self._last_hits += 1
        if enemy.manual_damage:
            self._personal_kills += 1
            bonus = 50 if enemy.kind == "boss" else 10
            self._kill_bonus += bonus * enemy.manual_damage // enemy.max_hp
        self._cue("enemyDefeated")
        if enemy.kind == "boss":
            self._personal_boss = enemy.manual_damage > 0
            self._boss_last_hit = manual
            self._finish("victory")
            return
        if (self.kills % 2 == 0 or self.random.randrange(5) == 0) and len(self.pickups) < 3:
            if not self._drop_order:
                self._drop_order = ["restore", "shield", "rapidFire"]
                self.random.shuffle(self._drop_order)
            self.pickups.append(Pickup(self._drop_order.pop(), enemy.x, enemy.y, self._id()))
        if self.defeated == self.total:
            self.next_wave = self.time + 1.15

    def _collect(self, item, manual=False):
        self.pickups.remove(item)
        if item.kind == "restore":
            useful = self.player_hp < 100
            self.player_hp = min(100, self.player_hp + 25)
        elif item.kind == "shield":
            useful = self.shield_until < self.time + 4
            self.shield_until = self.time + 4
        else:
            useful = self.rapid_until < self.time + 5
            self.rapid_until = self.time + 5
            self.next_hero_fire = min(self.next_hero_fire, self.time + .15)
        if manual and useful:
            self._manual_pickups += 1
        self._cue("powerup")

    def _finish(self, phase):
        self.phase = phase
        self.shots.clear()
        self.pickups.clear()
        self.fire_until = self.shield_until = self.rapid_until = 0
        self._cue("death" if phase == "dead" else "victory")

    def _target(self, x, y):
        if self.playing and isfinite(x) and isfinite(y):
            for items in (self.pickups, self.enemies):
                for item in reversed(items):
                    sprite = self._sprite(item)
                    left, top, step = _layout(sprite, item.x, item.y, item.radius)
                    row, col = floor((y-top) / step), floor((x-left) / step)
                    if 0 <= row < len(sprite) and 0 <= col < len(sprite[row]) and sprite[row][col] != ".":
                        return item
        return None

    def target_at(self, x, y):
        return self._target(x, y) is not None

    def click(self, x, y):
        target = self._target(x, y)
        if isinstance(target, Pickup):
            self._collect(target, manual=True)
            return True
        if target is not None and self.time >= self.next_assist:
            self.next_assist = self.time + .16
            self._damage(target, 9, manual=True)
            return True
        return False

    def _sprite(self, item):
        frames = SPRITES[item.kind]
        return frames[(int(self.time*3) + item.serial) % len(frames)]

    def hit_rects(self):
        """Disjoint from transparent holes, health bars, labels, effects, and shots."""
        if self.playing:
            for items in (self.enemies, self.pickups):
                for item in items:
                    sprite = self._sprite(item)
                    x, y, step = _layout(sprite, item.x, item.y, item.radius)
                    for row, start, length, _ in _runs(sprite, True):
                        yield x+start*step, y+row*step, length*step, step

    def draw(self, painter):
        from PySide6.QtCore import QRectF
        from PySide6.QtGui import QColor, QFont, QPainter

        @lru_cache(maxsize=None)
        def color(value):
            return QColor(value)

        def fill(x, y, w, h, value):
            painter.fillRect(QRectF(x, y, w, h), color(value))

        def text(x, baseline, label):
            from PySide6.QtCore import QPointF
            painter.drawText(QPointF(x, baseline), label)

        painter.save()
        try:
            painter.setRenderHint(QPainter.RenderHint.Antialiasing, False)
            font = QFont("monospace")
            font.setStyleHint(QFont.StyleHint.Monospace)
            font.setPixelSize(8)
            font.setBold(True)
            painter.setFont(font)
            painter.setPen(color(CREAM))
            self.paint(fill, text, painter.fontMetrics().horizontalAdvance)
        finally:
            painter.restore()

    def paint(self, fill, text, measure):
        """Vector-free pixel ops, shared by the native Qt surface and raster tests."""
        hx, hy = map(round, self.hero)
        if self.shield:
            for side in (-1, 1):
                fill(hx + side*20, hy-6, 2, 11, BLUE)
                for offset in (-10, 5):
                    fill(hx + side*18, hy+offset, 2, 4, BLUE)
        if self.hurt_until > self.time:
            fill(hx-21, hy-10, 3, 2, CORAL)
            fill(hx+4, hy-20, 2, 3, GOLD)
        if self.rapid_fire and self.time < self.fire_until:
            fill(hx+20, hy-3, 4, 2, GOLD)
            fill(hx+24, hy-5, 2, 1, CREAM)
        for shot in self.shots:
            x, y = round(shot.x), round(shot.y)
            if shot.hostile:
                fill(x-3, y-1, 6, 3, INK)
                fill(x-1, y-3, 3, 6, INK)
                fill(x-2, y, 4, 1, CORAL)
                fill(x, y-2, 1, 4, GOLD)
            else:
                fill(x-4, y-2, 8, 4, INK)
                fill(x-3, y-1, 5, 2, MINT)
                fill(x+2, y-1, 1, 2, CREAM)
        for e in self.enemies:
            _paint_sprite(fill, self._sprite(e), e.x, e.y, e.radius, e.kind, hurt=e.hurt > .55)
            boss = e.kind == "boss"
            w = max(36, e.radius*2) if boss else max(11, round(e.radius*1.7))
            _meter(fill, round(e.x-w/2), round(e.y+e.radius+2), w, 5 if boss else 4,
                   e.hp, e.max_hp, GOLD if boss else COLORS[e.kind]["h"])
            if e.hurt > .25:
                d = e.radius + 2 + 3*(1-e.hurt)
                fill(round(e.x-d), round(e.y-3), 2, 1, CREAM)
                fill(round(e.x+d), round(e.y+1), 1, 2, GOLD)
        for item in self.pickups:
            _paint_sprite(fill, self._sprite(item), item.x, item.y, item.radius, item.kind)
            side = 1 if (int(self.time*3) + item.serial) % 2 == 0 else -1
            x, y = round(item.x + side*(item.radius+1)), round(item.y-item.radius-1)
            fill(x, y, 1, 3, CREAM)
            fill(x-1, y+1, 3, 1, CREAM)
        _panel(fill, 7, 5, 62, 15)
        _paint_sprite(fill, SPRITES["heart"][0], 15, 12, 4.5, "heart")
        _meter(fill, 22, 10, 24, 5, self.player_hp, 100, CORAL if self.player_hp <= 25 else MINT)
        text(47, 16, f"{self.player_hp}%")
        x = 7
        for kind, seconds in (("shield", self.shield), ("rapidFire", self.rapid_fire)):
            if seconds > 0:
                _panel(fill, x, 21, 25, 11)
                _paint_sprite(fill, SPRITES[kind][0], x+6, 26, 4.5, kind)
                text(x+13, 29, str(ceil(seconds)))
                x += 27
        label = self.translate("Boss") if self.phase == "boss" else self.translate("Welle {0}").replace("{0}", str(self.wave))
        width = ceil(measure(label)) + 10
        _panel(fill, self.width-7-width, 5, width, 15)
        text(self.width-2-width, 16, label)


INK, CREAM, CORAL, MINT, GOLD, BLUE = "#312936", "#ffedc9", "#ef9278", "#97d7b3", "#f8c477", "#98cddd"
MUTED = "#584550"


def _layout(sprite, cx, cy, radius):
    width = max(map(len, sprite))
    step = 2*radius/max(width, len(sprite))
    return round(cx-step*width/2), round(cy-step*len(sprite)/2), step


@lru_cache(maxsize=None)
def _runs(sprite, solid):
    """Merge neighboring color cells when painting and any neighboring ink cells when masking."""
    runs = []
    for row, line in enumerate(sprite):
        col = 0
        while col < len(line):
            color = line[col]
            end = col+1
            if color != ".":
                while end < len(line) and (line[end] != "." if solid else line[end] == color):
                    end += 1
                runs.append((row, col, end-col, color))
            col = end
    return tuple(runs)


def _paint_sprite(fill, sprite, cx, cy, radius, kind, hurt=False):
    x, y, step = _layout(sprite, cx, cy, radius)
    colors = COLORS[kind]
    for row, col, length, symbol in _runs(sprite, False):
        color = colors[symbol]
        if hurt:
            color = CORAL if symbol == "b" else CREAM if symbol in "ch" else color
        fill(x+col*step, y+row*step, length*step, step, color)


def _meter(fill, x, y, w, h, hp, max_hp, color):
    fill(x, y, w, h, INK)
    fill(x+1, y+1, w-2, h-2, MUTED)
    if hp > 0 and max_hp > 0:
        fill(x+1, y+1, min(w-2, max(1, round((w-2)*hp/max_hp))), h-2, color)


def _panel(fill, x, y, w, h):
    fill(x+2, y, w-4, h, INK)
    fill(x, y+2, w, h-4, INK)


def _palette(shadow, body, light):
    return dict(x=INK, w=CREAM, g=GOLD, r=CORAL, b=shadow, c=body, h=light)


COLORS = {
    "bug": _palette("#66755f", "#96bc83", "#d0e9a8"),
    "worm": _palette("#855375", "#bb83ad", "#e7accc"),
    "spore": _palette("#457e83", "#6eada8", "#b4e2c7"),
    "boss": _palette("#79516f", "#b86c90", "#e89abb"),
    "restore": _palette("#628a73", MINT, CREAM),
    "shield": _palette("#508b9c", BLUE, CREAM),
    "rapidFire": _palette("#b27c51", GOLD, CREAM),
    "heart": _palette("#b27c51", CORAL, CREAM),
}

# Row strings correspond to the original macOS arcade cels, from top to bottom.
SPRITES = {
    "bug": (
        tuple("..x...x.. .xhx.xhx. ..xxxxx.. .xhhccbx. xbwxxwbcx .xccccbx. ..xbbbx.. .xx...xx.".split()),
        tuple(".x.....x. ..x...x.. ..xxxxx.. .xhhccbx. xbwxxwbcx .xccccbx. .xxbbbxx. x..xxx..x".split()),
    ),
    "worm": (
        tuple(".......xx.. ......xhcx. .xxxx..xcbx xhhccx..xcx xwxxwxx.xbx xcccbccxcbx .xbbccbbbx. ..xxxxxxx..".split()),
        tuple("........... .xxxx...xx. xhhccx.xhcx xwxxwxx.xcx xcccbccxcbx .xbbccbbbx. ..xxxxxxx.. ...........".split()),
    ),
    "spore": (
        tuple("....xhx.... .xx..x..xx. .xhxxxxxhx. ..xhcccbx.. .xbwwxxcbx. xhcwxwxccbx .xbwwwcbbx. ..xbbbbbx.. .xhxxxxxhx. .xx..x..xx. ....xbx....".split()),
        tuple(".....x..... ..x.xhx.x.. .xhxxxxxhx. ..xhcccbx.. xxbwwxxcbxx .hcwxwxccb. xxbwwwcbbxx ..xbbbbbx.. .xhxxxxxhx. ..x.xbx.x.. .....x.....".split()),
    ),
    "boss": (
        tuple(".......x....... ...x..xgx..x... ..xgxxgwgxxgx.. ...xgggggggx... ...xgrgggrgx... ...xxxxxxxxx... .xxhhccccccbbx. xhhwwxwwxwwcbcx .xcwxwwxwwxcbx. ..xcccbbccbbx.. .xbxxwwwxxbcbx. xbx.xxbbxx.xcbx .x.xbx..xbx..x. ..xx......xx...".split()),
        tuple(".......x....... ...x..xgx..x... ..xgxxgwgxxgx.. ...xgggggggx... ...xgrgggrgx... ...xxxxxxxxx... .xxhhccccccbbx. xhhwwxwwxwwcbcx .xcwxwwxwwxcbx. ..xcccbbccbbx.. .xbxxwwwxxbcbx. .xbx.xbbx.xbx.. ..xbx.xx.xbx... .xx........xx..".split()),
    ),
    "restore": (
        tuple("..xxxxx.. .xhcccxx. xhccwccbx xccwwwcbx xcccwccbx .xbcccxx. ..xxxxx..".split()),
    ),
    "shield": (
        tuple(".xxxxxxx. xhwwcccbx xhwccccbx xccccccbx .xccbcbx. ..xcbbx.. ...xbx... ....x....".split()),
    ),
    "rapidFire": (
        tuple("...xxxxx. ..xgggx.. .xgwgx... xgggggggx .xxxgggx. ...xggx.. ..xggx... ..xxx....".split()),
    ),
    "heart": (
        tuple(".xx.xx. xrrxrrx xhrcrrx .xrrrx. ..xrx.. ...x...".split()),
    ),
}
