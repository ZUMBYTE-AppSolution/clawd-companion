"""WSGI JSON API for registered Claw’d players. Python 3.11+, SQLite 3.35+."""
import base64
import contextlib
import hashlib
import hmac
import ipaddress
import json
import math
import os
import re
import secrets
import sqlite3
import threading
import time
from http import HTTPStatus
from pathlib import Path

from . import game

BASE = "/api/clawd/v1"
RUN = re.compile(r"/runs/([a-f0-9]{32})(/click)?\Z")
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{2,23}\Z")
EMAIL = re.compile(r"[^@\s\x00-\x1f]+@[^@\s\x00-\x1f]+\.[^@\s\x00-\x1f]+\Z")
TOKEN = re.compile(r"Bearer ([A-Za-z0-9_-]{43})\Z")
KDF_SLOTS = threading.BoundedSemaphore(2)


class Problem(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


@contextlib.contextmanager
def transaction(db):
    db.execute("BEGIN IMMEDIATE")
    try:
        yield
        db.commit()
    except BaseException:
        db.rollback()
        raise


def derive(password, salt):
    if not KDF_SLOTS.acquire(timeout=0.5):
        raise Problem(503, "unavailable")
    try:
        return hashlib.scrypt(password.encode(), salt=salt, n=32768, r=8, p=3, maxmem=80 * 1024 * 1024, dklen=32)
    finally:
        KDF_SLOTS.release()


class ArenaAPI:
    def __init__(self, database, key, *, clock=time.time, trust_proxy=False, require_https=True, kdf=derive):
        if not isinstance(key, bytes) or len(key) < 32:
            raise ValueError("CLAWD_SECRET must contain at least 32 random decoded bytes")
        self.database, self.key, self.clock, self.kdf = str(database), key, clock, kdf
        self.trust_proxy, self.require_https = trust_proxy, require_https
        with contextlib.closing(self.connect()) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript(Path(__file__).with_name("schema.sql").read_text())

    def connect(self):
        db = sqlite3.connect(self.database, timeout=4, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def index(self, purpose, value):
        return hmac.digest(self.key, (purpose + "\0" + value).encode(), "sha256").hex()

    def connection(self, env):
        remote = env.get("REMOTE_ADDR", "")
        proxy = self.trust_proxy and remote in ("", "127.0.0.1", "::1")
        scheme = env.get("HTTP_X_FORWARDED_PROTO") if proxy else env.get("wsgi.url_scheme")
        if self.require_https and scheme != "https":
            raise Problem(403, "https_required")
        ip = env.get("HTTP_X_REAL_IP", remote) if proxy else remote
        try:
            return str(ipaddress.ip_address(ip))
        except ValueError:
            return "local"

    def limit(self, db, scope, subject, maximum, window, now):
        key = self.index("limit/" + scope, str(subject))
        # A single statement commits the attempt before any credential or game transaction.
        row = db.execute("""INSERT INTO limits VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET
                            expires=CASE WHEN expires<=? THEN excluded.expires ELSE expires END,
                            uses=CASE WHEN expires<=? THEN 1 ELSE MIN(uses+1,?) END RETURNING uses""",
                         (key, now+window, now, now, maximum+1)).fetchone()
        if row[0] > maximum:
            raise Problem(429, "rate_limited")

    def clean(self, db, now):
        previous = db.execute("SELECT expires FROM limits WHERE key='cleanup'").fetchone()
        if previous is not None and previous[0] > now:
            return
        # Bounded cleanup shared by workers once per minute.
        changed = db.execute("""INSERT INTO limits VALUES('cleanup',?,0) ON CONFLICT(key)
                                DO UPDATE SET expires=excluded.expires WHERE expires<=?""", (now+60, now)).rowcount
        if changed:
            db.execute("DELETE FROM limits WHERE key IN (SELECT key FROM limits WHERE expires<? LIMIT 256)", (now,))
            db.execute("DELETE FROM sessions WHERE token_hash IN (SELECT token_hash FROM sessions WHERE expires<=? LIMIT 256)", (now,))
            db.execute("DELETE FROM runs WHERE id IN (SELECT id FROM runs WHERE phase!='playing' AND seen<? LIMIT 128)",
                       (now-7*86400,))

    def session(self, db, user, now):
        token = secrets.token_urlsafe(32)
        db.execute("INSERT INTO sessions VALUES(?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), user["id"], now+30*86400))
        db.execute("""DELETE FROM sessions WHERE token_hash IN (SELECT token_hash FROM sessions WHERE user_id=?
                      ORDER BY expires DESC,rowid DESC LIMIT -1 OFFSET 8)""", (user["id"],))
        return {"username": user["username"], "token": token}

    def credentials(self, db, action, data, ip, now):
        self.limit(db, "auth", ip, 35, 600, now)
        identity, password = data.get("username"), data.get("password")
        if not isinstance(identity, str) or not isinstance(password, str) or len(identity)>254 or not 1<=len(password)<=128:
            raise Problem(400, "invalid_registration" if action=="register" else "invalid_credentials")
        if action == "register":
            self.limit(db, "signup", ip, 5, 3600, now)
            email = data.get("email")
            if not NAME.fullmatch(identity) or not isinstance(email, str) or len(email)>254 or not EMAIL.fullmatch(email) or len(password)<12:
                raise Problem(400, "invalid_registration")
            salt = secrets.token_bytes(16)
            verifier = self.kdf(password, salt)
            try:
                with transaction(db):
                    uid = db.execute("INSERT INTO users(username,email_key,salt,verifier) VALUES(?,?,?,?)",
                                     (identity, self.index("email",email.casefold()), salt, verifier)).lastrowid
                    return self.session(db, {"id":uid,"username":identity}, now)
            except sqlite3.IntegrityError:
                raise Problem(409, "account_unavailable") from None
        self.limit(db, "login", identity.casefold(), 14, 600, now)
        user = db.execute("SELECT * FROM users WHERE username=? OR email_key=?",
                          (identity, self.index("email",identity.casefold()))).fetchone()
        verifier = self.kdf(password, user["salt"] if user else self.key[:16])
        if not hmac.compare_digest(verifier, user["verifier"] if user else bytes(32)) or user is None:
            raise Problem(401, "invalid_credentials")
        with transaction(db):
            return self.session(db, user, now)

    def authorize(self, db, env, now):
        auth = TOKEN.fullmatch(env.get("HTTP_AUTHORIZATION",""))
        if not auth:
            raise Problem(401, "unauthorized")
        hashed = hashlib.sha256(auth[1].encode()).hexdigest()
        session = db.execute("SELECT user_id FROM sessions WHERE token_hash=? AND expires>?", (hashed,now)).fetchone()
        if session is None:
            raise Problem(401, "unauthorized")
        return session[0], hashed

    @staticmethod
    def profile(row):
        return {"username": row["username"], "kills": row["kills"], "deaths": row["deaths"],
                "kd": round(row["kills"] / row["deaths"], 2) if row["deaths"] else None, "wins": row["wins"], "score": row["score"]}

    def dispatch(self, db, path, method, data, env, ip, now):
        if path in ("/login", "/register") and method=="POST":
            return self.credentials(db, path[1:], data, ip, now)
        try:
            uid, hashed = self.authorize(db, env, now)
        except Problem:
            self.limit(db, "denied", ip, 120, 60, now)
            raise
        self.limit(db, "requests", uid, 750, 60, now)
        if path == "/logout" and method == "POST":
            db.execute("DELETE FROM sessions WHERE token_hash=?", (hashed,))
            return {"ok": True}
        if path == "/me" and method=="GET":
            with transaction(db):
                game.expire(db, now, uid)
                return self.profile(db.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone())
        if path == "/leaderboard" and method=="GET":
            self.limit(db, "board", uid, 40, 60, now)
            with transaction(db):
                game.expire(db, now)
                rows = db.execute("""SELECT * FROM users WHERE score>0 OR deaths>0 OR wins>0
                                  ORDER BY score DESC,kills DESC,wins DESC,id LIMIT 100""")
                return {"players":[{"rank":n, **self.profile(row)} for n,row in enumerate(rows,1)]}
        if path == "/runs" and method=="POST":
            if data:
                raise Problem(400, "invalid_input")
            self.limit(db,"start",uid,20,60,now)
            with transaction(db):
                game.expire(db,now,uid)
                grave = db.execute("SELECT 1 FROM runs WHERE user_id=? AND phase='dead' AND seen>? LIMIT 1",
                                   (uid, now - 300)).fetchone()
                if grave:
                    raise Problem(409, "reviving")
                row=db.execute("SELECT * FROM runs WHERE user_id=? AND phase='playing'",(uid,)).fetchone()
                return game.frame(db,row or game.create(db,uid,now),now)
        match = RUN.fullmatch(path)
        if not match or method != ("POST" if match[2] else "GET"):
            raise Problem(404, "not_found")
        click = None
        if match[2]:
            self.limit(db,"click",uid,360,60,now)
            seq,x,y = data.get("seq"),data.get("x"),data.get("y")
            if (data.keys() != {"seq","x","y"} or type(seq) is not int or not 1<=seq<2**31
                or not all(type(n) in (float,int) and math.isfinite(n) for n in (x,y)) or not (0<=x<300 and 0<=y<160)):
                raise Problem(400,"invalid_input")
            click=(seq,x,y)
        with transaction(db):
            game.expire(db,now,uid)
            row = db.execute("SELECT * FROM runs WHERE id=? AND user_id=?", (match[1],uid)).fetchone()
            if row is None:
                raise Problem(404,"not_found")
            if click and click[0]>row["seq"]+1:
                raise Problem(409,"sequence_gap")
            return game.frame(db,row,now,click)

    def __call__(self, env, start_response):
        try:
            ip = self.connection(env)
            if env.get("HTTP_ORIGIN"):
                raise Problem(403,"app_only")
            path = env.get("SCRIPT_NAME", "").rstrip("/") + env.get("PATH_INFO", "")
            if not path.startswith(BASE + "/"):
                raise Problem(404,"not_found")
            method = env.get("REQUEST_METHOD","")
            if method not in ("GET","POST"):
                raise Problem(405,"method_not_allowed")
            data = {}
            if method == "POST":
                if env.get("CONTENT_TYPE","").split(";")[0].strip().lower() != "application/json":
                    raise Problem(415,"invalid_input")
                length = int(env.get("CONTENT_LENGTH") or 0)
                if length<2 or length>4096:
                    raise Problem(400,"invalid_input")
                data=json.loads(env["wsgi.input"].read(length))
                if not isinstance(data,dict):
                    raise Problem(400,"invalid_input")
            now=self.clock()
            with contextlib.closing(self.connect()) as db:
                self.clean(db, now)
                result=self.dispatch(db,path[len(BASE):],method,data,env,ip,now)
            status = 200
        except Problem as exc:
            status, result = exc.status, {"error":exc.code}
        except (ValueError, UnicodeError, OverflowError, RecursionError):
            status,result = 400, {"error":"invalid_input"}
        except sqlite3.OperationalError:
            status,result = 503, {"error":"unavailable"}
        body=json.dumps(result, separators=(",",":"), ensure_ascii=False, allow_nan=False).encode()
        headers=[("Content-Type","application/json; charset=utf-8"),("Content-Length",str(len(body))),
                 ("Cache-Control","no-store"),("X-Content-Type-Options","nosniff")]
        if status==429:
            headers.append(("Retry-After","60"))
        start_response(f"{status} {HTTPStatus(status).phrase}", headers)
        return [body]


def from_environment():
    path=Path(os.environ["CLAWD_DATABASE"])
    if not path.is_absolute():
        raise ValueError("CLAWD_DATABASE must be absolute")
    key=base64.b64decode(os.environ["CLAWD_SECRET"], validate=True)
    return ArenaAPI(path,key,trust_proxy=os.getenv("CLAWD_TRUST_PROXY")=="1")
