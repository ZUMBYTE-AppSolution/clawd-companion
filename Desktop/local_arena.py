"""One explicitly started local round for the Highscores panel."""
from uuid import uuid4

from arcade import Arcade
from desktop_core import record_round


class LocalArenaRound:
    def __init__(self, translate):
        self.translate = translate
        self.scene = self.run_id = None
        self.settled = self.paused = False

    @property
    def phase(self):
        return self.scene.phase if self.scene is not None else None

    @property
    def playing(self):
        return self.scene is not None and self.scene.playing

    def start(self, *, now, grave_until, online_playing, existing=None):
        if self.playing or online_playing or grave_until > now:
            return False
        if existing is None:
            self.scene, self.run_id = Arcade(translate=self.translate), uuid4().hex
        else:
            self.scene, self.run_id = existing
        self.scene.pause()
        self.settled = self.paused = False
        return True

    def clear(self):
        self.scene = self.run_id = None
        self.settled = self.paused = False

    def pause(self):
        if self.playing:
            self.scene.pause()
            self.paused = True

    def resume(self, now):
        if self.playing and self.paused:
            self.paused = False
            self.scene.tick(now)

    def tick(self, now, visible):
        if self.scene is None or self.settled:
            return []
        if not visible:
            self.pause()
        if self.paused:
            return []
        return self.scene.tick(now)

    def click(self, x, y):
        return self.playing and not self.paused and self.scene.click(x, y)

    def finish(self, prefs, wall_time):
        if self.scene is None or self.playing or self.settled:
            return False
        self.settled = True
        record_round(prefs, self.run_id, self.scene.stats)
        if self.phase == "dead":
            prefs["graveUntil"] = wall_time + 300
        prefs.save()
        return True
