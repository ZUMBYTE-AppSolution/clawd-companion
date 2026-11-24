"""Claw’d Companion for Windows and Linux. All screen coordinates are Qt logical pixels."""
import datetime
import json
import math
import os
from pathlib import Path
import queue
import random
import sys
import time

# Claude launches this handler as a separate process. It should never open windows or start a second pet.
import code_link
if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] in ("--clawd-hook", "--clawd-quota", "--clawd-quota-pipe"):
    code_link.collect(sys.argv[1])
    sys.exit(0)

from PySide6.QtCore import Qt, QPoint, QRect, QSize, QTimer, QUrl
from PySide6.QtGui import (QColor, QCursor, QDesktopServices, QFont, QFontDatabase, QGuiApplication, QIcon,
                          QPainter, QPalette, QPixmap, QPolygon, QRegion)
from PySide6.QtMultimedia import QSoundEffect
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QDialog, QHBoxLayout, QLabel, QMenu,
                               QPushButton, QScrollArea, QSlider, QSystemTrayIcon, QTabWidget, QVBoxLayout, QWidget)

from arcade import Arcade
from desktop_core import (ACTIVITIES, ASSETS, DEFAULTS, LANGUAGES, ROOT, SOUNDS, BrowserBridge, Language,
                          PointerVolley, Preferences, iso_time, pairing_token, projectile_ink, ranked_terminal)
import platform_host
from updates import UpdateController

W, A = Qt.WindowType, Qt.WidgetAttribute
FAST = Qt.TransformationMode.FastTransformation
PLAIN = Qt.TextFormat.PlainText
POSE_LABELS = dict(idle="Startklar", thinking="Denkt nach", typing="Schreibt eine Antwort", planning="Plant die nächsten Schritte",
                   researching="Recherchiert", reading="Liest eine Datei", executing="Führt Code aus", drawing="Erstellt ein Artefakt",
                   juggling="Claw’d jongliert mit Agents", awaitingApproval="Wartet auf deine Freigabe", happy="Freut sich",
                   perched="Sitzt auf der Titelleiste", perchThinking="Grübelt auf der Titelleiste", virusFight="Virenarena",
                   grave="Claw’d ruht unter einem GIT-Grabstein", reviving="Auferstehung", sleeping="Hält ein Nickerchen",
                   letterBlaster="Zielt mit dem Buchstabenblaster", archery="Spannt den Codebogen", climbing="Klettert",
                   rappelling="Seilt sich ab", jumping="Springt ab", falling="Ist in der Luft", walking="Ist unterwegs")
POSE_SOUND = {"walking":"steps","climbing":"climb","rappelling":"rappel","jumping":"jump","landing":"land","juggling":"juggle",
              "dancing":"celebrate","happy":"celebrate","peek":"peek","typing":"typing","thinking":"thinking","reviving":"arcadeRevive"}
BATTLE_SOUND = dict(fire="arcadeFire", enemyHit="arcadeHit", heroHurt="arcadeHit", enemyDefeated="arcadeHit", boss="arcadeBoss",
                    powerup="arcadePickup", victory="arcadeVictory", death="arcadeDefeat")


class Atlas:
    def __init__(self, basename):
        self.image = QPixmap(str(ASSETS / (basename + ".png")))
        self.info = json.loads((ASSETS / (basename + ".json")).read_text(encoding="utf-8"))
        self.w, self.h = self.info["cellWidth"], self.info["cellHeight"]
        if self.image.isNull() or self.image.size() != QSize(self.w*self.info["columns"], self.h*self.info["rows"]):
            raise RuntimeError("Invalid sprite atlas: " + basename)
        self.cache = {}

    def sprite(self, pose, age, scale=1, left=False, still=False):
        pose = pose if pose in self.info["poses"] else "idle"
        record = self.info["poses"][pose]
        n = record["frames"]
        frame = 0 if still else int(max(0, age)*self.info["fps"])
        durations = record.get("durations")
        if durations and not still:
            position = age % sum(durations) if record["loop"] else max(0, age)
            frame = n-1
            for i, seconds in enumerate(durations):
                if position < seconds:
                    frame = i
                    break
                position -= seconds
        frame = frame % n if record["loop"] else min(n-1, frame)
        key = (pose, frame, scale, left)
        if key not in self.cache:
            pix = self.image.copy(frame*self.w, record["row"]*self.h, self.w, self.h)
            if left:
                from PySide6.QtGui import QTransform
                pix = pix.transformed(QTransform.fromScale(-1,1), FAST)
            self.cache[key] = pix.scaled(self.w*scale, self.h*scale, Qt.AspectRatioMode.IgnoreAspectRatio, FAST)
        return self.cache[key]


class Audio:
    def __init__(self, prefs):
        self.prefs, self.effects, self.last = prefs, {}, {}
        self.music_name, self.music_effect = "", None

    def effect(self, name):
        if name not in self.effects:
            effect = QSoundEffect()
            effect.setSource(QUrl.fromLocalFile(str(ASSETS / "sounds" / (name + ".wav"))))
            self.effects[name] = effect
        return self.effects[name]

    def enabled(self, name):
        return self.prefs["sound"] and name not in self.prefs["muted"] and self.prefs["volume"] > 0

    def play(self, name, sample=False):
        if not name or not self.enabled(name):
            return
        now = time.monotonic()
        gap = {"letters":.1, "arcadeFire":.2, "arcadeHit":.18, "steps":.5, "climb":.5}.get(name,.7)
        if not sample and now-self.last.get(name,0) < gap:
            return
        self.last[name] = now
        effect = self.effect(name)
        effect.setVolume(self.prefs["volume"]/100)
        effect.play()

    def music(self, phase=""):
        target = phase if phase and self.enabled("arcadeMusic") else ""
        if target == self.music_name:
            if self.music_effect:
                self.music_effect.setVolume(.6*self.prefs["volume"]/100)
            return
        if self.music_effect:
            self.music_effect.stop()
        self.music_effect = None
        self.music_name = target
        if target:
            self.music_effect = self.effect(target+"-loop")
            self.music_effect.setLoopCount(-2)
            self.music_effect.setVolume(.6*self.prefs["volume"]/100)
            self.music_effect.play()

    def stop(self):
        self.music()
        for sound in self.effects.values():
            sound.stop()


class Layer(QWidget):
    def __init__(self, host, interactive=False):
        flags = W.Widget if host.stage is not None else W.Tool | W.FramelessWindowHint | W.WindowStaysOnTopHint | W.WindowDoesNotAcceptFocus
        if host.stage is None and not interactive:
            flags |= W.WindowTransparentForInput
        super().__init__(host.stage,flags)
        self.host = host
        self.setAttribute(A.WA_TranslucentBackground)
        self.setAttribute(A.WA_ShowWithoutActivating)
        if not interactive:
            self.setAttribute(A.WA_TransparentForMouseEvents)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)


class Pet(Layer):
    def __init__(self, host):
        super().__init__(host,True)
        self.pix = None
        self.drag = None
        self.dragged = False
        self.setAccessibleName("Claw’d")
        self.setCursor(Qt.CursorShape.OpenHandCursor)

    def display(self, pix):
        if self.pix is None or self.pix.cacheKey() != pix.cacheKey():
            self.pix = pix
            self.resize(pix.size())
            self.setMask(pix.mask())
            self.update()

    def paintEvent(self, event):
        if self.pix:
            p = QPainter(self)
            p.drawPixmap(0,0,self.pix)
            p.end()

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.RightButton:
            self.host.menu(event.globalPosition().toPoint())
        elif event.button() == Qt.MouseButton.LeftButton:
            self.drag = event.globalPosition().toPoint(), self.pos()
            self.dragged = False

    def mouseMoveEvent(self, event):
        if self.drag and not self.host.game_visible:
            delta = event.globalPosition().toPoint()-self.drag[0]
            if delta.manhattanLength()>QApplication.startDragDistance():
                self.dragged = True
                self.host.cancel_motion()
                self.host.pin = None
                self.move(self.drag[1] + delta)

    def mouseReleaseEvent(self,event):
        if self.drag and event.button() == Qt.MouseButton.LeftButton:
            if self.dragged:
                self.host.save_position()
            else:
                self.host.show_settings()
            self.drag = None


class Bubble(Layer):
    def __init__(self, host):
        super().__init__(host)
        self.value = ""
        self.end = 0
        self.setFont(QFont(host.dialogue_font,11))
    def say(self, text, now):
        self.value = text
        bounds = self.fontMetrics().boundingRect(QRect(0,0,245,420), Qt.TextFlag.TextWordWrap.value, text)
        self.resize(max(68,bounds.width()+26),max(41,bounds.height()+26))
        self.end = now + min(15,max(4,len(text)/12))
        self.follow()
        self.show()
        self.raise_()
        self.update()
    def follow(self):
        pet, screen = self.host.pet.geometry(), self.host.screen()
        x = max(screen.left(), min(screen.right()-self.width()+1,pet.center().x()-self.width()//2))
        y = pet.top()-self.height()+7
        if y < screen.top():
            y = pet.bottom()+1
        self.move(x,y)
    def paintEvent(self,event):
        p=QPainter(self)
        w,h=self.width(),self.height()
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor("#483030"))
        poly=QPolygon([QPoint(x,y) for x,y in [(4,0),(w-5,0),(w-5,3),(w-1,3),(w-1,h-13),(w-5,h-13),(w-5,h-9),
                                             (w//2+9,h-9),(w//2+1,h-1),(w//2-2,h-1),(w//2-2,h-9),(4,h-9),(4,h-12),(0,h-12),(0,3),(4,3)]])
        p.drawPolygon(poly)
        p.fillRect(4,4,w-8,h-17,QColor("#fff1d8"))
        p.setPen(QColor("#483030"))
        p.drawText(QRect(11,6,w-22,h-19), Qt.TextFlag.TextWordWrap.value | Qt.AlignmentFlag.AlignVCenter.value, self.value)
        p.end()


class Arena(Layer):
    def paintEvent(self,event):
        if self.host.game_visible:
            p=QPainter(self)
            p.scale(self.width()/300,self.height()/160)
            self.host.game.draw(p)
            p.end()


class Targets(Layer):
    def __init__(self,host):
        super().__init__(host,True)
    def paintEvent(self,event):
        # A nearly transparent backing allows Windows layered-window input inside our visible-pixel mask.
        p=QPainter(self)
        p.fillRect(self.rect(),QColor(0,0,0,1))
        p.end()
    def mousePressEvent(self,event):
        if self.host.game_visible and event.button()==Qt.MouseButton.LeftButton:
            self.host.game.click(event.position().x()*300/self.width(),event.position().y()*160/self.height())


class Letters(Layer):
    def paintEvent(self,event):
        g=self.host.volley
        if not g:
            return
        p=QPainter(self)
        p.setFont(QFont("Monospace",9,QFont.Weight.Bold))
        for x,y,_,_,_,text in g.shots:
            px,py=round(x)-self.x(),round(y)-self.y()
            outline,fill=projectile_ink(text,g.blaster)
            for layer,color in ((outline,"#483030"),(fill,"#ffcc8c")):
                for dx,dy,w,h in layer:
                    p.fillRect(px+dx,py+dy,w,h,QColor(color))
            if not g.blaster:
                dx,dy,w,h=outline[0]
                p.setPen(QColor("#483030"))
                p.drawText(QRect(px+dx,py+dy,w,h),Qt.AlignmentFlag.AlignCenter.value,text)
        p.end()


class Companion:
    def __init__(self, app, test_directory=None):
        self.testing = test_directory is not None
        self.app, self.prefs = app, Preferences(test_directory / "desktop.json" if self.testing else None)
        self.language = Language(self.prefs["language"])
        self.tr = self.language
        self.mascots, self.icons = Atlas("mascot-atlas"), Atlas("menu-atlas")
        loaded = QFontDatabase.addApplicationFont(str(ROOT/"Resources/ClawdDialogue.ttf"))
        families = QFontDatabase.applicationFontFamilies(loaded)
        self.dialogue_font = families[0] if families else "Monospace"
        self.audio = Audio(self.prefs)
        self.stage = None
        if app.platformName().startswith("wayland"):
            # Wayland applications cannot position arbitrary top levels or query foreign windows/cursors.
            # Keep every game, click and animation available in one regular compositor-managed window.
            self.stage = QWidget()
            self.stage.setWindowTitle("Claw’d Companion")
            self.stage.setMinimumSize(490,300)
            self.stage.resize(620,400)
            self.stage.setStyleSheet("background-color:#e7d7bc")
            self.stage.show()
        self.pet, self.bubble, self.arena, self.targets, self.letters = Pet(self), Bubble(self), Arena(self), Targets(self), Letters(self)
        self.dialog = None
        self.labels = {}
        self.pending = []
        self.motion = None
        self.pin = None
        self.ledge = None
        self.task_window = None
        self.focus_window = None
        self.volley = None
        self.game = None
        self.game_visible = False
        self.requested = False
        self.pin_offset = QPoint()
        self.pin_origin = None
        self.arcade_origin = QPoint()
        self.next_arcade = time.monotonic()+random.uniform(100,180)
        self.next_idle = time.monotonic()+5
        self.last_slow = -1
        self.pose_start = time.monotonic()
        self.pose = "idle"
        self.left = False
        self.transient = ("idle",0)
        self.browser_state = ("idle",0)
        self.agent_times = {}
        self.approvals = {}
        self.sessions = {}
        self.browser_seen = 0
        self.idle = None
        self.tray_pix = {}
        self.tray_key = None
        self.last_tray = -1
        self.last_pose_sound = -1
        self.browser = None
        self.token = pairing_token(test_directory)
        try:
            if not self.testing:
                self.browser = BrowserBridge(self.token)
        except OSError:
            pass
        self.tts = None
        self.center_initial()
        self.pet.setVisible(self.prefs["visible"])
        self.tray = QSystemTrayIcon(QIcon(self.mascots.sprite("idle",0)), app)
        self.tray.activated.connect(self.tray_action)
        self.traymenu = QMenu()
        self.traymenu.aboutToShow.connect(lambda: self.populate_menu(self.traymenu))
        self.tray.setContextMenu(self.traymenu)
        self.tray.show()
        self.updater = UpdateController(self.stage or self.pet, self.tr, language=lambda: self.language.code)
        self.updater.available.connect(lambda version: self.say(self.tr("Version {0} ist verfügbar.", version)))
        if not self.testing:
            self.updater.start()
        self.timer = QTimer()
        self.timer.setInterval(33)
        self.timer.timeout.connect(self.tick)
        self.timer.start()
        self.app.aboutToQuit.connect(self.close)
        self.tick()
        if not self.prefs["visible"] and not QSystemTrayIcon.isSystemTrayAvailable():
            self.show_settings()

    def screen(self):
        if self.stage:
            return self.stage.rect()
        screen = self.app.screenAt(self.pet.geometry().center()) or self.app.primaryScreen()
        return screen.availableGeometry()

    def cursor(self):
        pos = QCursor.pos()
        return self.stage.mapFromGlobal(pos) if self.stage else pos

    def center_initial(self):
        sc = self.screen()
        scale = self.prefs["scale"]
        self.pet.display(self.mascots.sprite("idle",0,scale))
        pos = QPoint(self.prefs.get("x", sc.right()-148*scale), self.prefs.get("y", sc.bottom()-66*scale))
        screen = sc if self.stage else next((s.availableGeometry() for s in self.app.screens() if s.availableGeometry().contains(pos)),sc)
        self.pet.move(self.bound(pos, screen))

    def bound(self, pt, screen=None):
        r = screen or self.screen()
        return QPoint(round(max(r.left(),min(r.right()-self.pet.width()+1,pt.x()))),
                      round(max(r.top(),min(r.bottom()-self.pet.height()+1,pt.y()))))

    def save_position(self):
        self.prefs["x"], self.prefs["y"] = self.pet.x(), self.pet.y()
        self.prefs.save()

    def set_pref(self,key,value):
        self.prefs[key]=value
        if key == "visible":
            self.pet.setVisible(value)
            if not value:
                self.bubble.hide()
                self.volley=None
                self.letters.hide()
                self.cancel_motion()
        if key == "reduce" and value:
            self.cancel_motion()
            self.volley = None
            self.letters.hide()
        if key == "language":
            self.language.select(value)
            QTimer.singleShot(0, self.rebuild_settings)
        if key in ("arcade","activePlay","visible") and self.game:
            self.game.pause()
        if key == "arcade" and not value:
            self.hide_arena()
            self.game = None
            self.requested = False
        if key == "sound" and not value:
            self.audio.stop()
        self.prefs.save()

    def say(self,text):
        if self.prefs["bubbles"] and self.prefs["visible"]:
            self.bubble.say(text, time.monotonic())
        self.audio.play("notification")
        if self.prefs["voice"]:
            try:
                from PySide6.QtTextToSpeech import QTextToSpeech
                from PySide6.QtCore import QLocale
                if self.tts is None:
                    self.tts = QTextToSpeech()
                self.tts.setLocale(QLocale(self.language.code))
                self.tts.say(text)
            except (ImportError, RuntimeError):
                pass

    def close(self):
        self.timer.stop()
        self.updater.stop()
        self.audio.stop()
        if self.browser:
            self.browser.close()
        self.tray.hide()
        if not self.game:
            self.save_position()

    def cancel_motion(self):
        self.pending.clear()
        self.motion = None
        self.ledge = None

    def flash(self,pose,duration=2):
        self.transient = (pose,time.monotonic()+duration)
        self.audio.play(POSE_SOUND.get(pose))

    def schedule(self,route):
        self.pending = list(route)
        self.motion = None

    def ledge_point(self, handle):
        rect = platform_host.window_rect(handle) if not self.stage else None
        if not rect:
            return None
        x,y,w,h = rect
        s = self.prefs["scale"]
        # The perched sprite's sitting row is 38 of 48 logical sprite pixels.
        return QPoint(round(x + max(20, min(w*.45,65*s)) - 28*s), round(y - 38*s))

    def window_route(self, rest=False, for_task=False):
        if not self.focus_window:
            self.say(self.tr("Dieses Fenster hat auf diesem Bildschirm gerade keine freie Sitzkante."))
            return
        handle,x,y,w,h = self.focus_window
        top = self.ledge_point(handle)
        if top is None:
            return
        s=self.prefs["scale"]
        sc = self.app.screenAt(QPoint(round(x+w/2), round(y+h/2)))
        screen = sc.availableGeometry() if sc else self.screen()
        can_sit=top.y() >= screen.top()
        if rest and not can_sit and not for_task:
            self.say(self.tr("Dieses Fenster hat auf diesem Bildschirm gerade keine freie Sitzkante."))
            return
        edge = x-51*s if x-51*s >= screen.left() else x+w-5*s
        edge = round(edge)
        wall=QPoint(edge,round(max(screen.top()-6*s,y-14*s)))
        foot=QPoint(edge,round(min(y+h-36*s,screen.bottom()-48*s)))
        self.pin = None
        self.ledge = handle
        path=[("walking",foot, max(.3,math.dist(self.xy(self.pet.pos()),self.xy(foot))/250)),
              ("climbing",wall,max(.6,(foot.y()-wall.y())/145))]
        if can_sit:
            path.append(("climbing",top,.38))
        else:
            top=wall
        if not for_task:
            path.extend([("perched" if can_sit else "peek",top,random.uniform(3,6)),
                         ("perchThinking" if can_sit else "peek",top,random.uniform(2,4))])
        if not rest:
            path += [("jumping",top+QPoint(30,-15),.25),("falling",self.bound(foot+QPoint(70,5),screen),.65),
                     ("landing",self.bound(foot+QPoint(70,5),screen),.3)]
        self.schedule(path)

    def pin_candidate(self):
        if self.stage:
            return None
        point=self.pet.geometry().center()
        probe=getattr(platform_host,"window_at",None)
        if probe:
            candidate=probe(point.x(),point.y())
            if candidate:
                return candidate
        if self.focus_window:
            handle,x,y,w,h=self.focus_window
            if QRect(x,y,w,h).contains(point):
                return self.focus_window
        return None

    def toggle_pin(self):
        if self.pin is not None:
            self.pin=None
            self.pin_origin=None
            return
        target=self.pin_candidate()
        if target:
            self.cancel_motion()
            handle,x,y,w,h=target
            self.pin=handle
            self.pin_origin=QPoint(round(x),round(y))
            self.pin_offset=self.pet.pos()-self.pin_origin
        else:
            self.say(self.tr("Zieh mich auf das gewünschte Fenster oder an seine Kante und wähle den Pin erneut."))

    def track_pin(self):
        rect=platform_host.window_rect(self.pin)
        if not rect:
            self.pin=None
            self.pin_origin=None
            return
        origin=QPoint(round(rect[0]),round(rect[1]))
        delta=origin-self.pin_origin if self.pin_origin is not None else QPoint()
        self.pin_origin=origin
        if self.motion or self.pending:
            if delta!=QPoint():
                self.pet.move(self.pet.pos()+delta)
                self.pending=[(name,target+delta,duration) for name,target,duration in self.pending]
                if self.motion:
                    name,start,target,began,duration=self.motion
                    self.motion=(name,start+delta,target+delta,began,duration)
        else:
            self.pet.move(origin+self.pin_offset)

    def rappel(self):
        home=self.pet.pos()
        self.schedule([("rappelling",self.bound(home+QPoint(0,120)),1),("peek",self.bound(home+QPoint(0,120)),1),
                       ("climbing",home,1)])

    def walk(self, chase=False):
        if self.pin is not None or self.prefs["reduce"]:
            return
        self.ledge=None
        sc=self.screen()
        target=self.cursor()-QPoint(self.pet.width()//2,self.pet.height()//2) if chase else QPoint(
            random.randint(sc.left(),max(sc.left(),sc.right()-self.pet.width())),self.pet.y()+random.randint(-44,44))
        target=self.bound(target)
        self.schedule([("walking",target,max(.35,math.dist(self.xy(target),self.xy(self.pet.pos()))/150))])

    @staticmethod
    def xy(point):
        return point.x(), point.y()

    def moving_pose(self, now):
        if self.motion is None and self.pending:
            name,target,duration=self.pending.pop(0)
            self.motion=(name,self.pet.pos(),target,now,duration)
            self.audio.play(POSE_SOUND.get(name))
        if self.motion:
            name,start,target,began,duration=self.motion
            if self.ledge and name in ("perched","perchThinking"):
                live=self.ledge_point(self.ledge)
                if live is not None:
                    target=live
            u=max(0,min(1,(now-began)/duration))
            if target.x()!=start.x():
                self.left=target.x()<start.x()
            self.pet.move(round(start.x()+(target.x()-start.x())*u),round(start.y()+(target.y()-start.y())*u))
            if u>=1:
                self.motion=None
            return name
        return None

    def shoot(self,blaster=True):
        if self.game_visible or not self.prefs["projectile"] or self.prefs["reduce"] or self.prefs["graveUntil"]>time.time():
            return
        self.cancel_motion()
        self.volley=PointerVolley(blaster)

    def projectiles(self,now):
        g=self.volley
        cursor=self.cursor()
        self.left=cursor.x()<self.pet.geometry().center().x()
        center=self.pet.geometry().center()
        x=center.x() + (-1 if self.left else 1)*self.prefs["scale"]*16
        outcomes,released=g.tick(now,(x,center.y()),self.xy(cursor))
        if released:
            self.audio.play("letters" if g.blaster else "bow")
        if outcomes:
            self.prefs["hits"]+=sum(outcomes)
            self.prefs["dodges"]+=len(outcomes)-sum(outcomes)
            self.prefs.save()
        if g.shots:
            xs,ys=zip(*[(shot[0],shot[1]) for shot in g.shots])
            self.letters.setGeometry(math.floor(min(xs))-22,math.floor(min(ys))-12,max(44,math.ceil(max(xs)-min(xs))+44),
                                     max(24,math.ceil(max(ys)-min(ys))+24))
            self.letters.show()
            self.letters.update()
        else:
            self.letters.hide()
        if not g.running:
            self.say(self.tr("HIT {0}/{1}",g.hits,g.total))
            self.volley=None
            self.next_idle=now+4
        return "letterBlaster" if g.blaster else "archery"

    def hide_arena(self):
        self.game_visible=False
        self.arena.hide()
        self.targets.hide()
        self.audio.music()

    def request_game(self):
        if self.prefs["arcade"]:
            self.requested=True
            self.next_arcade=time.monotonic()

    def drive_arena(self,now,busy):
        from desktop_core import record_round
        import uuid
        grave=self.prefs["graveUntil"]
        if grave:
            if time.time()<grave:
                return "grave"
            self.prefs["graveUntil"]=0
            self.prefs.save()
            self.flash("reviving",1.5)
            return "reviving"
        if self.transient[0]=="reviving" and self.transient[1]>now:
            return "reviving"
        eligible=(self.prefs["arcade"] and self.prefs["visible"] and not self.prefs["reduce"] and not busy
                  and (self.prefs["activePlay"] or (self.idle is not None and self.idle>=90)))
        if not eligible:
            if self.game:
                self.game.pause()
                self.hide_arena()
            return None
        if self.game is None:
            if now<self.next_arcade or (not self.requested and self.idle is not None and self.idle<90):
                return None
            self.game=Arcade(translate=self.tr)
            self.run_id=uuid.uuid4().hex
            self.requested=False
            self.cancel_motion()
            sc=self.screen()
            pos=self.pet.geometry().center()
            self.arena_scale=min(1.4,sc.width()/300,sc.height()/160)
            width,height=round(300*self.arena_scale),round(160*self.arena_scale)
            x=max(sc.left(),min(sc.right()-width+1,pos.x()-40))
            y=max(sc.top(),min(sc.bottom()-height+1,pos.y()-80))
            self.arcade_rect=QRect(x,y,width,height)
        self.game_visible=True
        self.game_scale=self.arcade_rect.width()/300
        for cue in self.game.tick(now):
            self.audio.play(BATTLE_SOUND.get(cue))
        if self.game.phase in ("dead","victory"):
            dead=self.game.phase=="dead"
            record_round(self.prefs,self.run_id,self.game.stats)
            if dead:
                self.prefs["graveUntil"]=time.time()+300
            self.prefs.save()
            self.game=None
            self.next_arcade=now+random.uniform(150,300)
            self.hide_arena()
            if dead:
                return "grave"
            self.flash("virusVictory",3)
            return "virusVictory"
        self.audio.music(self.game.phase)
        self.arena.setGeometry(self.arcade_rect)
        if not self.arena.isVisible():
            self.arena.show()
            self.pet.raise_()
        self.arena.update()
        hx,hy=self.game.hero
        size=self.prefs["scale"]
        self.pet.move(round(self.arcade_rect.x()+hx*self.game_scale-28*size),
                      round(self.arcade_rect.y()+hy*self.game_scale-24*size))
        self.left=False
        if self.prefs["activePlay"]:
            self.targets.setGeometry(self.arcade_rect)
            region=QRegion()
            for x,y,w,h in self.game.hit_rects():
                sx,sy=math.floor(x*self.game_scale),math.floor(y*self.game_scale)
                region=region.united(QRegion(QRect(sx,sy,math.ceil((x+w)*self.game_scale)-sx,math.ceil((y+h)*self.game_scale)-sy)))
            if not region.isEmpty():
                self.targets.setMask(region)
                if not self.targets.isVisible():
                    self.targets.show()
            else:
                self.targets.hide()
        else:
            self.targets.hide()
        return "virusFight"

    def apply_event(self,event,now):
        typ=event.get("type")
        if typ!="code" and event.get("source")!="Claude Code":
            self.browser_seen=now
        if typ=="activity":
            state=event["state"]
            if state=="done" and self.browser_state[0] not in ("happy","idle"):
                self.say(self.tr("Deine Antwort ist fertig."))
            if state!="connected" or self.browser_state[1]<now:
                self.browser_state=(ACTIVITIES[state],now+(12 if state=="done" else 125))
        elif typ=="notice":
            self.say(event["title"]+"\n"+event["message"])
            self.flash("worried" if event["kind"] in ("warning","error","attention") else "happy",3)
        elif typ=="usage":
            previous=self.prefs["quota"]
            observed=iso_time(event.get("observedAt"))
            if observed is not None and observed <= time.time()+300 and observed >= (iso_time(previous.get("observedAt")) or 0):
                self.prefs["quota"]=event
                self.prefs.save()
        elif typ=="approval":
            key=("browser",event["sourceID"])
            if event["waiting"]:
                self.approvals[key]=now+125
            else:
                self.approvals.pop(key,None)
        elif typ=="code":
            key=event["session"]; act=event["action"]
            if act=="SubagentStart":
                self.agent_times[(key,event["agent"])]=now+1800
            elif act=="SubagentStop":
                self.agent_times.pop((key,event["agent"]),None)
            elif act=="PermissionRequest" or (act=="Notification" and event.get("waiting")):
                self.approvals[("code",key)]=now+900
            elif act in ("Stop","SessionEnd","StopFailure"):
                self.approvals.pop(("code",key),None)
                self.sessions.pop(key,None)
                self.agent_times={k:t for k,t in self.agent_times.items() if k[0]!=key}
                self.flash("worried" if act=="StopFailure" else "happy",3)
            elif act in ("UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure"):
                self.approvals.pop(("code",key),None)
                pose=event.get("pose", "worried" if act=="PostToolUseFailure" else "thinking")
                self.sessions[key]=(pose,now+300)

    def detect(self,now):
        self.last_slow=now
        if self.testing:
            self.idle=0
            return
        self.idle=platform_host.idle_seconds()
        if not self.stage and not (self.dialog and self.dialog.isActiveWindow()):
            foreground=platform_host.active_window()
            if foreground is not None:
                self.focus_window=foreground
        if self.browser:
            while True:
                try:
                    self.apply_event(self.browser.events.get_nowait(),now)
                except queue.Empty:
                    break
        for event in code_link.drain():
            self.apply_event(event,now)
        self.sessions={k:v for k,v in self.sessions.items() if v[1]>now}
        self.approvals={k:t for k,t in self.approvals.items() if t>now}
        self.agent_times={k:t for k,t in self.agent_times.items() if t>now}
        if self.dialog and self.dialog.isVisible():
            self.update_status()

    def tick(self):
        now=time.monotonic()
        if now-self.last_slow>(.16 if self.game_visible else .5):
            self.detect(now)
        activity=self.browser_state[0] if self.browser_state[1]>now else "idle"
        if self.sessions:
            activity=max(self.sessions.values(),key=lambda v:v[1])[0]
        if self.agent_times:
            activity="juggling"
        if self.approvals:
            activity="awaitingApproval"
        if activity in ("idle","happy"):
            self.task_window=None
        busy=activity not in ("idle","happy") or bool(self.volley) or bool(self.pet.drag)
        if getattr(self,"online",None) and self.online.is_playing():
            busy=True
        if self.pin is not None and not self.game_visible and not self.pet.drag:
            self.track_pin()
        game_pose=self.drive_arena(now,busy)
        if game_pose:
            pose=game_pose
        elif self.volley and not self.prefs["reduce"] and not self.pet.drag:
            pose=self.projectiles(now)
        elif activity not in ("idle","happy"):
            pose=activity
            if self.pin is not None:
                self.moving_pose(now)
            elif self.focus_window and self.prefs["follow"] and self.prefs["climbing"] and not self.prefs["reduce"] and self.prefs["visible"] and not self.pet.drag:
                handle=self.focus_window[0]
                if self.task_window!=handle:
                    self.cancel_motion()
                    self.window_route(True,for_task=True)
                    self.task_window=handle
                moving=self.moving_pose(now)
                if moving:
                    pose=moving
                else:
                    top=self.ledge_point(handle)
                    if top and top.y()>=self.screen().top():
                        self.pet.move(top)
            elif self.motion or self.pending:
                self.cancel_motion()
        elif self.transient[1]>now:
            pose=self.transient[0]
        else:
            moving=None if self.pet.drag else self.moving_pose(now)
            pose=moving or activity
            if now>=self.next_idle and not self.motion and not self.pending and not self.pet.drag and self.prefs["visible"]:
                self.next_idle=now+random.uniform(6,14)
                choice=random.random()
                if not self.prefs["reduce"]:
                    if self.pin is not None:
                        if choice<.22:
                            self.rappel()
                    elif choice<.18 and self.prefs["climbing"] and self.focus_window:
                        self.window_route()
                    elif choice<.26 and self.prefs["projectile"]:
                        self.shoot(random.random()<.7)
                    elif choice<.38 and self.prefs["chase"]:
                        self.walk(True)
                    elif choice<.77 and self.prefs["roaming"]:
                        self.walk()
                    else:
                        self.flash(random.choice(["peek","perchThinking","happy","thinking","sleeping"]),3)
        if pose!=self.pose:
            self.pose=pose
            self.pose_start=now
        if pose in ("typing","juggling","walking","climbing") and now-self.last_pose_sound>2.2 and self.prefs["visible"]:
            self.audio.play(POSE_SOUND[pose])
            self.last_pose_sound=now
        age=now-self.pose_start
        display=pose
        left=self.left
        if pose=="idle":
            delta=self.cursor()-self.pet.geometry().center()
            if abs(delta.x())>16 or abs(delta.y())>16:
                display=("idleLeft" if delta.x()<0 else "idleRight") if abs(delta.x())>abs(delta.y()) else ("idleUp" if delta.y()<0 else "idleDown")
            left=False
        if self.prefs["visible"]:
            self.pet.display(self.mascots.sprite(display,age,self.prefs["scale"],left,self.prefs["reduce"]))
        if self.bubble.isVisible():
            if self.bubble.end<now or not self.prefs["visible"]:
                self.bubble.hide()
            else:
                self.bubble.follow()
        if now-self.last_tray>=.125:
            self.last_tray=now
            icon=self.icons.sprite(pose,age,1,left,self.prefs["reduce"])
            key=icon.cacheKey()
            if key not in self.tray_pix:
                # Tint the original menu silhouettes for contrast on light and dark taskbars.
                face=QPixmap(icon)
                paint=QPainter(face)
                paint.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
                paint.fillRect(face.rect(),QColor("#ffb48e"))
                paint.end()
                rim=QPixmap(icon.width()+2,icon.height()+2)
                rim.fill(Qt.GlobalColor.transparent)
                paint=QPainter(rim)
                for x,y in ((0,1),(2,1),(1,0),(1,2)):
                    paint.drawPixmap(x,y,icon)
                paint.drawPixmap(1,1,face)
                paint.end()
                self.tray_pix[key]=QIcon(rim)
            if key!=self.tray_key:
                self.tray_key=key
                self.tray.setIcon(self.tray_pix[key])
                self.tray.setToolTip("Claw’d · "+self.tr(POSE_LABELS.get(pose,"Startklar")))
        fast=bool(self.game_visible or self.volley or self.motion or self.pending or self.pet.drag)
        next_interval=33 if fast else 125
        if self.timer.interval()!=next_interval:
            self.timer.setInterval(next_interval)

    def tray_action(self,reason):
        if reason in (QSystemTrayIcon.ActivationReason.Trigger,QSystemTrayIcon.ActivationReason.DoubleClick):
            self.show_settings()

    def populate_menu(self,menu):
        menu.clear()
        def action(key,callback,enabled=True):
            act=menu.addAction(self.tr(key))
            act.setEnabled(enabled)
            act.triggered.connect(lambda checked=False: callback())
        action("Status öffnen",self.show_settings)
        action("Figur ausblenden" if self.prefs["visible"] else "Figur einblenden",lambda:self.set_pref("visible",not self.prefs["visible"]))
        action("Fenster-Pin lösen" if self.pin is not None else "Pin to Window · An Fenster heften",self.toggle_pin,
               self.pin is not None or self.pin_candidate() is not None)
        idle=self.game is None and not self.prefs["graveUntil"] and not self.prefs["reduce"]
        menu.addSeparator()
        action("Spazieren",self.walk,idle)
        action("Auf Titelleiste setzen",lambda:self.window_route(True),idle and self.focus_window is not None)
        action("Hochklettern",self.window_route,idle and self.focus_window is not None)
        action("Abseilen",self.rappel,idle)
        action("Freuen",lambda:self.flash("happy"),idle)
        action("Codebogen spannen",lambda:self.shoot(False),idle and self.prefs["projectile"])
        action("Buchstabensalve testen",self.shoot,idle and self.prefs["projectile"])
        action("Arcade starten" if self.prefs["activePlay"] else "Für den Leerlauf vormerken", self.request_game,
               idle and self.prefs["arcade"])
        menu.addSeparator()
        action("Highscores",lambda:self.show_settings(3))
        action("Info & Updates",self.updater.show)
        action("Claw’d beenden",self.app.quit)

    def menu(self,point):
        menu=QMenu()
        self.populate_menu(menu)
        menu.exec(point)

    def ranked_available(self):
        return bool(self.prefs["activePlay"] and self.prefs["arcade"] and self.prefs["visible"] and not self.prefs["reduce"]
                    and not self.game and not self.volley and not self.prefs["graveUntil"] and not self.agent_times
                    and not self.approvals and not self.sessions and (self.browser_state[0] in ("idle","happy") or self.browser_state[1]<=time.monotonic()))

    def rebuild_settings(self):
        old=self.dialog
        selected=old.tabs.currentIndex() if old else 0
        if hasattr(self,"online"):
            self.online.setParent(None)
        if old:
            old.hide()
            old.deleteLater()
        self.dialog=None
        self.show_settings(selected)

    def show_settings(self,selected=None):
        if self.dialog is None:
            self.build_settings()
        if selected is not None:
            self.dialog.tabs.setCurrentIndex(selected)
        self.update_status()
        self.dialog.show()
        self.dialog.raise_()
        self.dialog.activateWindow()

    def build_settings(self):
        dlg=self.dialog=QDialog(self.stage)
        dlg.setWindowTitle("Claw’d Companion")
        dlg.resize(620,560)
        dlg.setLayoutDirection(Qt.LayoutDirection.RightToLeft if self.language.code in ("ar","ur") else Qt.LayoutDirection.LeftToRight)
        outer=QVBoxLayout(dlg)
        tabs=dlg.tabs=QTabWidget()
        outer.addWidget(tabs)
        self.labels={}
        def page(title):
            scroll=QScrollArea()
            scroll.setWidgetResizable(True)
            content=QWidget()
            layout=QVBoxLayout(content)
            layout.setAlignment(Qt.AlignmentFlag.AlignTop)
            scroll.setWidget(content)
            tabs.addTab(scroll,self.tr(title))
            return layout
        def label(layout,text="",key=None):
            widget=QLabel(text)
            widget.setTextFormat(PLAIN)
            widget.setWordWrap(True)
            layout.addWidget(widget)
            if key:
                self.labels[key]=widget
            return widget
        def button(layout,title,handler):
            b=QPushButton(self.tr(title))
            b.clicked.connect(lambda checked=False:handler())
            layout.addWidget(b)
            return b
        def check(layout,key,title):
            c=QCheckBox(self.tr(title))
            c.setChecked(self.prefs[key])
            c.toggled.connect(lambda value:self.set_pref(key,value))
            layout.addWidget(c)
        def heading(layout,key):
            title=label(layout,self.tr(key))
            font=title.font()
            font.setBold(True)
            title.setFont(font)

        home=page("Begleiter")
        label(home,"", "activity")
        heading(home,"Kontingent")
        label(home,"","quota")
        button(home,"Nutzungsseite öffnen",lambda:QDesktopServices.openUrl(QUrl("https://claude.ai/settings/usage")))
        heading(home,"Mit Claw’d spielen")
        label(home,"","arcade")
        button(home,"Arcade starten",self.request_game)
        button(home,"Streicheln",lambda:self.flash("happy"))
        button(home,"Buchstabensalve testen",self.shoot)
        label(home,"","hits")
        heading(home,"Sprache")
        langs=QComboBox()
        langs.addItem(self.tr("Systemsprache"),"system")
        for code,name in LANGUAGES.items():
            langs.addItem(name,code)
        langs.setCurrentIndex(max(0,langs.findData(self.prefs["language"])))
        langs.currentIndexChanged.connect(lambda index:self.set_pref("language",langs.itemData(index)))
        home.addWidget(langs)
        button(home,"Info & Updates",self.updater.show)

        overlay=page("Overlay")
        for key,title in (("roaming","Spazieren"),("climbing","An Fenstern klettern"),("follow","Aktives Fenster für Claude-Aktionen"),("chase","Mauszeiger jagen"),
                          ("projectile","Codebogen und Buchstabenblaster"),("bubbles","Sprechblasen"),
                          ("voice","Eigene Meldungen vorlesen"),("reduce","Bewegung reduzieren"),("arcade","Im Leerlauf spielen"),
                          ("activePlay","Auch bei aktiver Nutzung spielen")):
            check(overlay,key,title)
        label(overlay,self.tr("Nach 90 Sekunden ohne Maus oder Tastatur darf Claw’d eine Runde beginnen."))
        heading(overlay,"Figurgröße")
        size=QSlider(Qt.Orientation.Horizontal)
        size.setRange(1,4)
        size.setValue(self.prefs["scale"])
        size.valueChanged.connect(lambda v:self.set_pref("scale",v))
        overlay.addWidget(size)
        button(overlay,"Sprechblase testen",lambda:self.say(self.tr("Hier melde ich mich, wenn Claude deine Antwort fertig hat.")))
        button(overlay,"Figur zurückholen",self.reset_position)
        heading(overlay,"Soundeffekte")
        check(overlay,"sound","Töne")
        volume=QSlider(Qt.Orientation.Horizontal)
        volume.setRange(0,100)
        volume.setValue(self.prefs["volume"])
        volume.setAccessibleName(self.tr("Lautstärke"))
        volume.valueChanged.connect(lambda v:self.set_pref("volume",v))
        overlay.addWidget(volume)
        for name,title in SOUNDS.items():
            row=QHBoxLayout()
            overlay.addLayout(row)
            c=QCheckBox(self.tr(title))
            c.setChecked(name not in self.prefs["muted"])
            c.toggled.connect(lambda enabled,key=name:self.mute(key,enabled))
            row.addWidget(c)
            button(row,"Hörprobe für „{0}“",lambda key=name:self.audio.play(key,True)).setText("▶ "+self.tr(title))

        links=page("Verbindungen")
        heading(links,"Claude.ai verbinden")
        label(links,"","bridge")
        label(links,self.tr("Aktiviere auf der Erweiterungsseite deines Browsers den Entwicklermodus. Wähle „Entpackte Erweiterung laden“."))
        button(links,"Erweiterungsordner zeigen und Pfad kopieren",self.open_extension)
        button(links,"Kopplungscode kopieren",self.copy_pairing)
        label(links,self.tr("Öffne Claw’d in der Browser-Symbolleiste und füge den Kopplungscode ein. Lade offene Claude-Tabs einmal neu."))
        heading(links,"Claude Code verbinden")
        for key,title in (("hooks","Aktivität und Subagents"),("quota","Kontingent")):
            label(links,self.tr(title))
            b=button(links,"Entfernen" if code_link.installed(key) else "Einrichten",lambda kind=key:self.configure(kind))
            self.labels["button-"+key]=b
        label(links,"","hookMessage")

        scores=page("Highscores")
        heading(scores,"Meine Arena-Statistik")
        label(scores,"","score")
        label(scores,self.tr("Nur abgeschlossene Runden, in denen du selbst einen Gegner getroffen oder ein wirksames Power-up eingesammelt hast, zählen."))
        from online_arena import OnlineArenaWidget
        if not hasattr(self,"online"):
            self.online=OnlineArenaWidget(self.tr,self.ranked_available)
            self.online.roundEnded.connect(self.ranked_finished)
        else:
            self.online.refresh_language()
        scores.addWidget(self.online)
        dlg.finished.connect(lambda n:self.online.stop())
        dlg.setStyleSheet("QDialog {background:#302831;} QScrollArea,QScrollArea>QWidget>QWidget {background:#3a3035;} "
                          "QLabel,QCheckBox {color:#fff0d8;padding:4px;} QTabBar::tab {padding:8px;} "
                          "QPushButton {padding:5px 9px;} QSlider {min-height:22px;}")

    def quota_text(self):
        quota=self.prefs["quota"]
        rows=[]
        now=time.time()
        for win in quota.get("windows",[]):
            reset=iso_time(win.get("resetAt"))
            if reset is not None and reset<=now:
                continue
            observed=iso_time(quota.get("observedAt"))
            if observed is None or (not reset and now-observed>86400):
                continue
            name=self.tr("Sitzung" if win["kind"]=="session" else "Woche")
            when=(datetime.datetime.fromtimestamp(reset).astimezone().strftime("%x %H:%M") if reset is not None else win.get("resetLabel"))
            reset_label=self.tr("Reset ca." if win.get("resetApproximate") else "Reset")+" "+when if when else self.tr("Reset unbekannt")
            rows.append(name+" · "+self.tr("{0} % frei",win["remainingPercent"])+" · "+reset_label)
        if rows:
            observed=iso_time(quota.get("observedAt"))
            stamp=datetime.datetime.fromtimestamp(observed).astimezone().strftime("%x %H:%M")
            rows.append(quota.get("source","Claude.ai")+" · "+self.tr("Stand {0}",stamp))
        return "\n".join(rows) or self.tr("Kein aktueller Messwert")

    def update_status(self):
        if not self.labels:
            return
        description=self.tr(POSE_LABELS.get(self.pose,"Startklar"))
        if self.pose=="juggling":
            description=self.tr("Jongliert mit einem Agenten") if len(self.agent_times)==1 else self.tr("Jongliert mit {0} Agenten",len(self.agent_times))
        self.labels["activity"].setText("Claw’d · "+description)
        self.labels["quota"].setText(self.quota_text())
        if self.prefs["graveUntil"]>time.time():
            seconds=math.ceil(self.prefs["graveUntil"]-time.time())
            arcade=self.tr("Auferstehung in {0}",f"{seconds//60}:{seconds%60:02d}")
        elif self.game:
            arcade=(self.tr("Runde pausiert · {0} LP",self.game.player_hp) if not self.game_visible else
                    self.tr("Endboss · {0} LP",self.game.player_hp) if self.game.phase=="boss" else
                    self.tr("Welle {0} · {1} LP",self.game.wave,self.game.player_hp))
        else:
            arcade=self.tr("Ausgeschaltet" if not self.prefs["arcade"] else "Bereit für eine Runde" if self.prefs["activePlay"] else "Wartet auf den Leerlauf")
        self.labels["arcade"].setText(arcade)
        self.labels["hits"].setText(self.tr("Treffer")+" "+str(self.prefs["hits"])+" · "+self.tr("Ausgewichen")+" "+str(self.prefs["dodges"]))
        self.labels["bridge"].setText(self.tr("Der Browser-Port 49217 konnte nicht gebunden werden." if not self.browser else "Erweiterung verbunden" if self.browser_seen else "Wartet auf die Erweiterung"))
        stats=self.prefs["highscore"]
        k,d=stats.get("personalKills",0),stats.get("personalDeaths",0)
        values=(("Persönliche Punkte",stats.get("score",0)),("Persönliche Kills",k),("Tode",d),("K/D",f"{k/d:.2f}" if d else "—"),
                ("Siege",stats.get("personalVictories",0)),("Boss-Kills",stats.get("personalBoss",0)),("Gespielte Runden",stats.get("rounds",0)))
        self.labels["score"].setText("\n".join(self.tr(title)+"  "+str(value) for title,value in values))

    def ranked_finished(self,run_id,phase):
        if not ranked_terminal(self.prefs,run_id,phase,time.time()):
            return
        self.cancel_motion()
        self.audio.play("arcadeDefeat" if phase=="dead" else "arcadeVictory")
        if phase=="victory":
            self.flash("virusVictory",3)
        self.tick()

    def reset_position(self):
        self.cancel_motion()
        self.pin=None
        self.prefs.pop("x",None)
        self.prefs.pop("y",None)
        self.center_initial()
        self.set_pref("visible",True)
        self.save_position()

    def mute(self,name,enabled):
        muted=set(self.prefs["muted"])
        if enabled:
            muted.discard(name)
        else:
            muted.add(name)
            if name in self.audio.effects:
                self.audio.effects[name].stop()
        self.set_pref("muted",sorted(muted))

    def open_extension(self):
        path=ROOT/"BrowserExtension"
        self.app.clipboard().setText(str(path))
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def copy_pairing(self):
        self.app.clipboard().setText(self.token)
        self.say(self.tr("Kopplungscode kopiert. Füge ihn im Browser in die Claw’d-Erweiterung ein."))

    def configure(self,feature):
        try:
            code_link.configure(feature,not code_link.installed(feature))
            self.labels["button-"+feature].setText(self.tr("Entfernen" if code_link.installed(feature) else "Einrichten"))
            message="Änderung gespeichert. Öffne eine neue Claude-Code-Sitzung, damit sie wirksam wird."
        except (ValueError,OSError) as e:
            message=str(e)
        self.labels["hookMessage"].setText(self.tr(message))


def main():
    testing="--self-test" in sys.argv
    if testing and not os.environ.get("QT_QPA_PLATFORM") and not os.environ.get("DISPLAY") and sys.platform.startswith("linux"):
        os.environ["QT_QPA_PLATFORM"]="offscreen"
    app=QApplication(sys.argv)
    app.setApplicationName("ClawdCompanion")
    app.setOrganizationName("Zumbyte")
    app.setQuitOnLastWindowClosed(False)
    if testing:
        from PySide6.QtGui import QImage
        from online_arena import OnlineArenaWidget
        for name in ("mascot-atlas","menu-atlas"):
            atlas=Atlas(name)
            for pose in atlas.info["poses"]:
                assert not atlas.sprite(pose,.5).isNull()
        game=Arcade(1)
        sample=QImage(300,160,QImage.Format.Format_ARGB32_Premultiplied)
        sample.fill(Qt.GlobalColor.transparent)
        p=QPainter(sample)
        game.tick(0)
        game.draw(p)
        p.end()
        tr=Language("en")
        assert tr("Spazieren")!="Spazieren"
        assert all((ASSETS/"sounds"/(key+".wav")).is_file() for key in SOUNDS)
        assert (ROOT/"BrowserExtension/manifest.json").is_file()
        import tempfile
        with tempfile.TemporaryDirectory(prefix="clawd-self-test-") as path:
            desktop=Companion(app,Path(path))
            desktop.show_settings()
            desktop.set_pref("sound",False)
            desktop.set_pref("activePlay",True)
            desktop.request_game()
            desktop.tick()
            assert desktop.game_visible and desktop.game is not None
            assert desktop.labels["score"].text() and desktop.dialog.tabs.count()==4
            QTimer.singleShot(100,app.quit)
            return app.exec()
    from PySide6.QtCore import QLockFile
    from desktop_core import config_dir
    path=config_dir()
    path.mkdir(parents=True,exist_ok=True)
    lock=QLockFile(str(path/"desktop.lock"))
    if not lock.tryLock(0):
        return 0
    desktop=Companion(app)
    return app.exec()


if __name__=="__main__":
    sys.exit(main())
