"""Shared desktop state, desktop resource lookup, pointer game and paired browser receiver."""
import csv
from functools import lru_cache
import datetime as dt
import hmac
import json
import locale
import math
import os
from pathlib import Path
import queue
import random
import re
import secrets
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
ASSETS = ROOT / "Desktop" / "assets"
LANGUAGES = {"de":"Deutsch", "en":"English", "zh-Hans":"简体中文", "hi":"हिन्दी", "es":"Español",
             "ar":"العربية", "fr":"Français", "bn":"বাংলা", "pt":"Português", "id":"Bahasa Indonesia", "ur":"اردو"}
SOUNDS = {"steps":"Schritte", "climb":"Klettern", "jump":"Absprung", "land":"Landung", "rappel":"Abseilen",
          "bow":"Codebogen", "letters":"Buchstabensalve", "juggle":"Jonglieren", "celebrate":"Freudentanz",
          "notification":"Sprechblase", "peek":"Hervorlugen", "typing":"Tippen", "thinking":"Nachdenken",
          "arcadeMusic":"Arcade-Musik", "arcadeFire":"Arcade-Schüsse", "arcadeHit":"Arcade-Treffer",
          "arcadePickup":"Power-up einsammeln", "arcadeBoss":"Auftritt des Endbosses",
          "arcadeDefeat":"Arcade-Niederlage", "arcadeVictory":"Arcade-Sieg", "arcadeRevive":"Auferstehung"}
ACTIVITIES = {"working":"typing", "thinking":"thinking", "searching":"researching", "planning":"planning",
              "reading":"reading", "executing":"executing", "drawing":"drawing", "done":"happy",
              "idle":"idle", "connected":"idle"}
DEFAULTS = dict(language="system", roaming=True, chase=True, projectile=True, climbing=True, follow=True, bubbles=True,
                reduce=False, visible=True, arcade=True, activePlay=False, sound=True, voice=False, volume=28,
                scale=2, hits=0, dodges=0, graveUntil=0.0, muted=[], quota={}, highscore={}, finished=[], rankedFinished=[])


def config_dir():
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming"))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return base / "ClawdCompanion"


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as temp:
            temp_name = temp.name
            json.dump(value, temp, ensure_ascii=False, indent=2, allow_nan=False)
            temp.flush()
            os.fsync(temp.fileno())
        os.replace(temp_name, path)
    finally:
        if temp_name is not None:
            Path(temp_name).unlink(missing_ok=True)



class Preferences(dict):
    def __init__(self, path=None):
        super().__init__({k:v.copy() if isinstance(v,(list,dict)) else v for k,v in DEFAULTS.items()})
        self.path = path or config_dir() / "desktop.json"
        try:
            settings = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            settings = {}
        if isinstance(settings, dict):
            for key, default in DEFAULTS.items():
                value = settings.get(key)
                if type(default) is type(value):
                    self[key] = value
            if type(settings.get("graveUntil")) in (float,int) and math.isfinite(settings["graveUntil"]):
                self["graveUntil"] = max(0, float(settings["graveUntil"]))
            for key in ("x", "y"):
                if type(settings.get(key)) is int:
                    self[key] = settings[key]
        self["muted"] = [k for k in SOUNDS if k in self["muted"]]
        for key in ("finished","rankedFinished"):
            self[key] = [k for k in self[key] if isinstance(k,str)][-100:]
        self["highscore"] = {k:v for k,v in self["highscore"].items() if type(v) is int and v>=0}
        quota=self["quota"]
        validated=clean_event(quota)
        self["quota"] = validated if validated and validated["type"]=="usage" else {}
        if self["quota"] and quota.get("source")=="Claude Code":
            self["quota"]["source"]="Claude Code"
        self["scale"] = min(4, max(1, self["scale"]))
        self["volume"] = min(100, max(0, self["volume"]))

    def save(self):
        atomic_json(self.path, self)


def pairing_token(directory=None):
    path = (directory or config_dir()) / "pairing.key"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        with open(path, "x", opener=lambda filename, flags: os.open(filename, flags, 0o600)) as f:
            f.write(secrets.token_urlsafe(32))
    except FileExistsError:
        pass
    token = path.read_text(encoding="ascii").strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", token):
        raise ValueError("Invalid pairing key")
    return token


class Language:
    def __init__(self, choice="system", directory=None):
        self.entries = {}
        for path in sorted((directory or ROOT / "Resources/Languages").glob("*.tsv")):
            with path.open(encoding="utf-8") as f:
                for row in csv.DictReader(f, delimiter="\t"):
                    self.entries[row["de"]] = row
        self.select(choice)

    def select(self, choice):
        code = (locale.getlocale()[0] or "en") if choice == "system" else choice
        code = code.replace("_", "-").lower().split("-")[0]
        self.code = "zh-Hans" if code == "zh" else code if code in LANGUAGES else "en"

    def __call__(self, key, *args):
        value = self.entries.get(key, {}).get(self.code) or key
        for i, arg in enumerate(args):
            value = value.replace("{" + str(i) + "}", str(arg))
        return value


def iso_time(value):
    if not isinstance(value, str) or len(value) > 40:
        return None
    try:
        date = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return date.timestamp() if date.tzinfo else None
    except (ValueError, OSError, OverflowError):
        return None


def clean_event(data):
    if not isinstance(data, dict):
        return None
    kind = data.get("type")
    if kind == "activity" and isinstance(data.get("state"), str) and data["state"] in ACTIVITIES:
        return {"type":kind, "state":data["state"]}
    if kind == "notice" and data.get("kind") in ("success","info","attention","warning","error"):
        result = {"type":kind, "kind":data["kind"]}
        for key, limit in (("title",65),("message",220)):
            value = data.get(key)
            if not isinstance(value, str) or not (0 < len(value) <= limit):
                return None
            result[key] = re.sub(r"[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]", " ", value)
        return result
    if kind == "approval" and type(data.get("waiting")) is bool and isinstance(data.get("sourceID"), str):
        if re.fullmatch(r"[a-zA-Z0-9._:-]{1,100}", data["sourceID"]):
            return {"type":kind, "sourceID":data["sourceID"], "waiting":data["waiting"]}
    if kind == "usage" and iso_time(data.get("observedAt")) is not None:
        items, seen = [], set()
        if not isinstance(data.get("windows"), list) or not 1 <= len(data["windows"]) <= 2:
            return None
        for item in data["windows"]:
            if not isinstance(item, dict) or item.get("kind") not in ("session","weekly"):
                return None
            if item["kind"] in seen or type(item.get("remainingPercent")) is not int or not 0 <= item["remainingPercent"] <= 100:
                return None
            seen.add(item["kind"])
            win = {"kind":item["kind"], "remainingPercent":item["remainingPercent"]}
            if iso_time(item.get("resetAt")) is not None:
                win["resetAt"] = item["resetAt"]
                win["resetApproximate"] = item.get("resetApproximate") is True
            if isinstance(item.get("resetLabel"), str) and len(item["resetLabel"]) <= 100:
                win["resetLabel"] = re.sub(r"[\x00-\x1f\x7f]", " ", item["resetLabel"])
            items.append(win)
        return {"type":"usage", "observedAt":data["observedAt"], "windows":items}
    return None


def receive_event(path, headers, rfile, port, token, events):
    if path != "/v1/events":
        return 404
    if len(headers.get_all("Host", [])) != 1 or headers.get("Host") != f"127.0.0.1:{port}":
        return 403
    origin = headers.get("Origin")
    if origin and not re.fullmatch(r"chrome-extension://[a-p]{32}", origin):
        return 403
    auth = headers.get_all("Authorization", [])
    if len(auth) != 1 or not hmac.compare_digest(auth[0].encode(), ("Bearer " + token).encode()):
        return 401
    if headers.get_content_type() != "application/json":
        return 415
    lengths = headers.get_all("Content-Length", [])
    if headers.get("Transfer-Encoding") or len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,6}", lengths[0]):
        return 400
    length = int(lengths[0])
    if length > 8192:
        return 413
    try:
        payload = rfile.read(length)
        event = clean_event(json.loads(payload)) if len(payload) == length else None
        if not event:
            return 400
        events.put_nowait(event)
    except (ValueError, RecursionError, TimeoutError):
        return 400
    except queue.Full:
        return 503
    return 200


class BrowserBridge:
    def __init__(self, token, port=49217):
        events = self.events = queue.Queue(maxsize=128)
        class Receiver(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(2)
            def log_message(self, *args):
                pass
            def do_POST(self):
                code = self.receive()
                self.send_response(code)
                self.send_header("Content-Length", "0")
                self.end_headers()
            def receive(self):
                return receive_event(self.path, self.headers, self.rfile, self.server.server_port, token, events)
        class Server(HTTPServer):
            def get_request(self):
                sock, addr = super().get_request()
                sock.settimeout(2)
                return sock, addr
            def handle_error(self, request, client_address):
                pass
        self.server = Server(("127.0.0.1", port), Receiver)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval":.1}, daemon=True)
        self.thread.start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)


@lru_cache(maxsize=1)
def alphabet():
    return json.loads((ASSETS/"letter-glyphs.json").read_bytes())


@lru_cache(maxsize=40)
def projectile_ink(text, letter):
    """Opaque pixel runs relative to the projectile center; paints and pointer intersections share these."""
    if not letter:
        width = math.ceil(len(text)*6.2) + 12
        rect = (-width//2, -8, width, 16)
        return (rect,), ((rect[0]+1,-7,width-2,14),)
    fill = []
    for row, bits in enumerate(alphabet()[text]):
        start = None
        for col in range(6):
            on = col < 5 and bits & (16 >> col)
            if on and start is None:
                start = col
            if not on and start is not None:
                fill.append((start*2-5,row*2-7,(col-start)*2,2))
                start = None
    return tuple((x-1,y-1,w+2,h+2) for x,y,w,h in fill), tuple(fill)


def intersects(rect,start,end):
    enter, leave = 0.0, 1.0
    for pos, target, low, high in ((start[0],end[0],rect[0],rect[0]+rect[2]),
                                   (start[1],end[1],rect[1],rect[1]+rect[3])):
        delta = target-pos
        if delta == 0:
            if not low <= pos < high:
                return False
        else:
            a,b=(low-pos)/delta,(high-pos)/delta
            enter,leave=max(enter,min(a,b)),min(leave,max(a,b))
            if enter>leave:
                return False
    return True


class PointerVolley:
    """The cursor and each letter move on the same time interval. Collision is in relative coordinates."""
    def __init__(self, blaster=True, rng=None):
        self.rng = rng or random.Random()
        self.total = self.rng.randint(3,42) if blaster else 1
        self.hits = 0
        self.fired = 0
        self.shots = []
        self.previous = None
        self.previous_cursor = None
        self.delay = .26
        self.blaster = blaster

    @property
    def running(self):
        return self.fired < self.total or bool(self.shots)

    def tick(self, now, muzzle, cursor):
        if self.previous is None or now - self.previous < 0 or now - self.previous > .35:
            self.previous, self.previous_cursor = now, cursor
            return [], False
        delta = now - self.previous
        self.previous = now
        outcomes, live = [], []
        self.delay -= delta
        for x,y,vx,vy,age,text in self.shots:
            dx, dy = vx*delta, vy*delta
            start = (self.previous_cursor[0]-round(x),self.previous_cursor[1]-round(y))
            end = (cursor[0]-round(x+dx),cursor[1]-round(y+dy))
            outline,_ = projectile_ink(text,self.blaster)
            if any(intersects(rect,start,end) for rect in outline):
                self.hits += 1
                outcomes.append(True)
            elif age+delta >= 3:
                outcomes.append(False)
            else:
                live.append((x+dx,y+dy,vx,vy,age+delta,text))
        self.shots = live
        released = self.delay <= 0 and self.fired < self.total
        if released:
            x, y = muzzle
            angle = math.atan2(cursor[1]-y, cursor[0]-x)
            speed = max(280, min(1250, math.dist(cursor, muzzle)*1.7))
            text = self.rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") if self.blaster else self.rng.choice(["git","{}","if","=>","fn"])
            self.shots.append((x,y,math.cos(angle)*speed,math.sin(angle)*speed,0,text))
            self.fired += 1
            self.delay = self.rng.uniform(.075,.14)
        self.previous_cursor = cursor
        return outcomes, released


def record_round(prefs, run_id, stats):
    """Count a finished, manually assisted run once, alongside the pet's terminal state."""
    if not stats.get("engaged") or run_id in prefs.get("finished", []):
        return False
    totals = dict(prefs.get("highscore", {}))
    totals["rounds"] = totals.get("rounds", 0) + 1
    for key, source in (("score","score"),("personalKills","lastHits"),("personalDeaths","personalDeaths"),
                        ("personalVictories","personalVictories"),("personalBoss","bossLastHit")):
        totals[key] = totals.get(key, 0) + int(stats.get(source, 0))
    prefs["highscore"] = totals
    prefs["finished"] = (prefs.get("finished", []) + [run_id])[-100:]
    return True


def ranked_terminal(prefs, run_id, phase, wall_time):
    if phase not in ("dead","victory") or not run_id or run_id in prefs["rankedFinished"]:
        return False
    prefs["rankedFinished"] = (prefs["rankedFinished"] + [run_id])[-100:]
    if phase=="dead":
        prefs["graveUntil"] = wall_time + 300
    prefs.save()
    return True
