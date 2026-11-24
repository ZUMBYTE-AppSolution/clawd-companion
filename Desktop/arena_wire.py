"""HTTPS and authoritative frame decoding for the optional online arena."""
import json
import math
import re
import ssl
import threading
from urllib.parse import urlsplit
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener

from arcade import Arcade, Enemy, Pickup, Shot
from desktop_core import ROOT


USER = re.compile(r"[A-Za-z0-9._-]{3,24}")
RUN_ID = re.compile(r"[A-Za-z0-9_-]{1,128}")
LIMIT = 256 * 1024


class ArenaError(Exception):
    def __init__(self, code, http=0):
        super().__init__(code)
        self.code, self.http = code, http


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _validated_endpoint(value, host):
    if not isinstance(value, str) or len(value) > 2048:
        return None
    value = value.strip(" \t\r\n")
    if not re.fullmatch(r"[!-~]+", value) or any(c in value for c in "?#"):
        return None
    try:
        url = urlsplit(value)
    except ValueError:
        return None
    if url.scheme != "https" or url.netloc.lower() != host:
        return None
    parts = url.path.split("/")[1:]
    if parts and not parts[-1]:
        parts.pop()
    if any(p in (".", "..") or not re.fullmatch(r"[A-Za-z0-9._~-]+", p) for p in parts):
        return None
    return "https://" + host + ("/" + "/".join(parts) if parts else "")


def _read_configuration(root):
    try:
        with (root / "Resources" / "ArenaEndpoint.txt").open("rb") as settings:
            return settings.read(2049).decode("ascii")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeError):
        return ""


def _transport():
    return build_opener(_NoRedirect(), HTTPSHandler(context=ssl.create_default_context()))


class ArenaClient:
    def __init__(self, opener=None, *, fixture_endpoint=None, discovery_opener=None):
        if opener is None:
            self._host = "zumbyte.de"
            configured = _read_configuration(ROOT)
        else:
            self._host = "arena.invalid"
            configured = fixture_endpoint
        self._base = _validated_endpoint(configured, self._host)
        self._discover = configured is None
        self._lock = threading.Lock()
        self._opener = opener
        self._discovery_opener = (discovery_opener or opener) if opener is not None else None

    def _endpoint(self):
        with self._lock:
            if self._base:
                return self._base
            if not self._discover:
                raise ArenaError("network")
            url = "https://" + self._host + "/.well-known/clawd-companion.json"
            request = Request(url, headers={"Accept": "application/json"}, method="GET")
            try:
                opener = self._discovery_opener or _transport()
                with opener.open(request, timeout=6) as response:
                    if response.status != 200 or response.geturl() != url or response.headers.get_content_type() != "application/json":
                        raise ArenaError("network")
                    raw = response.read(2049)
                if len(raw) > 2048:
                    raise ArenaError("network")
                data = json.loads(raw)
                base = _validated_endpoint(data.get("arena"), self._host) if isinstance(data, dict) else None
            except HTTPError as error:
                error.close()
                raise ArenaError("network") from None
            except (URLError, OSError, ValueError, RecursionError):
                raise ArenaError("network") from None
            if base is None:
                raise ArenaError("network")
            self._base = base
            return base

    def request(self, method, path, data=None, token=""):
        # A run id can only address one route underneath this fixed HTTPS origin.
        allowed = {"GET": {"/me", "/leaderboard"}, "POST": {"/register", "/login", "/logout", "/runs"}}
        ranked = re.fullmatch(r"/runs/[A-Za-z0-9_-]{1,128}(/click)?", path)
        if path not in allowed.get(method, ()) and not (
            ranked and ((method == "GET" and not ranked[1]) or (method == "POST" and ranked[1]))
        ):
            raise ArenaError("invalid_request")
        headers = {"Accept": "application/json", "Cache-Control": "no-store", "User-Agent": "ClawdCompanion"}
        if token:
            if not isinstance(token, str) or not re.fullmatch(r"[\x21-\x7e]{1,4096}", token):
                raise ArenaError("invalid_token")
            headers["Authorization"] = "Bearer " + token
        body = None
        if data is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(data, ensure_ascii=False, allow_nan=False).encode("utf-8")
        request = Request(self._endpoint() + path, data=body, headers=headers, method=method)
        try:
            with self._lock:
                if self._opener is None:
                    self._opener = _transport()
                opener = self._opener
            with opener.open(request, timeout=6) as response:
                raw = response.read(LIMIT + 1)
        except HTTPError as error:
            try:
                obj = json.loads(error.read(4096))
                code = obj.get("error") if isinstance(obj, dict) else None
            except (UnicodeError, ValueError):
                code = None
            finally:
                error.close()
            raise ArenaError(code if isinstance(code, str) else "server_error", error.code) from None
        except (URLError, OSError, ValueError):
            raise ArenaError("network") from None
        if len(raw) > LIMIT:
            raise ArenaError("invalid_response")
        if not raw and path == "/logout":
            return {}
        try:
            value = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise ArenaError("invalid_response") from error
        if not isinstance(value, dict):
            raise ArenaError("invalid_response")
        return value


def number(value, low, high, integer=False):
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not low <= value <= high:
        raise ArenaError("invalid_response")
    if not math.isfinite(value) or (integer and value != int(value)):
        raise ArenaError("invalid_response")
    return int(value) if integer else value


def kd_ratio(row):
    if row.get("deaths") == 0 and row.get("kd") is None:
        return None
    value = number(row.get("kd"), 0, 10**12)
    return value if row.get("deaths") else None


def leaderboard_rows(payload):
    rows = payload.get("players")
    if not isinstance(rows, list) or len(rows) > 1000:
        raise ArenaError("invalid_response")
    result = []
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("username"), str) or not USER.fullmatch(row["username"]):
            raise ArenaError("invalid_response")
        result.append((number(row.get("rank"), 1, 10**9, True), row["username"],
                       number(row.get("kills"), 0, 10**12, True), number(row.get("deaths"), 0, 10**12, True),
                       kd_ratio(row), number(row.get("wins"), 0, 10**12, True),
                       number(row.get("score"), 0, 10**15, True)))
    return result


def validate_account(username, password, email=None):
    def valid_email(value):
        return len(value) <= 254 and re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value)

    if not (USER.fullmatch(username) or (email is None and valid_email(username))) or not 12 <= len(password) <= 128:
        raise ArenaError("invalid_request")
    if email is not None and not valid_email(email):
        raise ArenaError("invalid_request")


class RemoteFrame:
    """Build a render-only scene from the server snapshot. Client clocks animate cels only."""

    def __init__(self, payload, translate, clock=0):
        if not isinstance(payload, dict):
            raise ArenaError("invalid_response")
        identifier = payload.get("id")
        if not isinstance(identifier, str) or not RUN_ID.fullmatch(identifier):
            raise ArenaError("invalid_response")
        self.id = identifier
        self.phase = payload.get("phase")
        if self.phase not in ("wave", "boss", "victory", "dead", "expired"):
            raise ArenaError("invalid_response")
        self.seq = number(payload.get("seq"), 0, 10**9, True)
        self.score = number(payload.get("score"), 0, 10**9, True)
        self.ranked = payload.get("ranked")
        if not isinstance(self.ranked, bool):
            raise ArenaError("invalid_response")
        self.kills = number(payload.get("kills"), 0, 10**6, True)
        self.assists = number(payload.get("assists"), 0, 10**6, True)
        scene = self.scene = Arcade(seed=0, translate=translate)
        scene.phase = self.phase
        scene.wave = number(payload.get("wave"), 1, 99, True)
        scene.player_hp = number(payload.get("hp"), 0, 100, True)
        scene.hero = self._point(payload.get("hero"))
        scene.shots.clear()
        scene.enemies.clear()
        scene.time = number(payload["time"], 0, 86400) if "time" in payload else clock
        # These optional effects are entirely server-supplied and only affect the picture.
        scene.shield_until = scene.time + number(payload.get("shield", 0), 0, 60)
        scene.rapid_until = scene.time + number(payload.get("rapidFire", 0), 0, 60)
        for e in self._items(payload, "enemies"):
            x, y = self._point(e)
            kind, serial = e.get("kind"), number(e.get("id"), 0, 10**9, True)
            if kind not in ("bug", "worm", "spore", "boss"):
                raise ArenaError("invalid_response")
            max_hp = number(e.get("maxHP"), 1, 10000, True)
            hp = number(e.get("hp"), 0, max_hp, True)
            radius = number(e.get("radius"), 1, 50)
            scene.enemies.append(Enemy(kind, x, y, radius, hp, max_hp, x, y, 0, 0, 0, serial))
        for obj in self._items(payload, "pickups"):
            x, y = self._point(obj)
            kind = obj.get("kind")
            if kind not in ("restore", "shield", "rapidFire"):
                raise ArenaError("invalid_response")
            scene.pickups.append(Pickup(kind, x, y, number(obj.get("id"), 0, 10**9, True),
                                        number(obj.get("radius"), 1, 50)))
        for obj in self._items(payload, "shots"):
            x, y = self._point(obj)
            if not isinstance(obj.get("hostile"), bool):
                raise ArenaError("invalid_response")
            scene.shots.append(Shot(x, y, 0, 0, 0, obj["hostile"]))

    @staticmethod
    def _items(payload, key):
        value = payload.get(key)
        if not isinstance(value, list) or len(value) > 256 or any(not isinstance(item, dict) for item in value):
            raise ArenaError("invalid_response")
        return value

    @staticmethod
    def _point(obj):
        if not isinstance(obj, dict):
            raise ArenaError("invalid_response")
        return number(obj.get("x"), -100, 400), number(obj.get("y"), -100, 260)
