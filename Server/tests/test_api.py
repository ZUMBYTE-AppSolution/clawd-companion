import concurrent.futures
from contextlib import closing
import hashlib
import io
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

from Desktop.arcade import Arcade, Pickup
from Server import game
from Server.app import ArenaAPI, BASE, derive


class ArenaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.now = 2_000_000_000.0
        self.db = Path(self.temp.name) / "arena.db"
        self.api = ArenaAPI(self.db, b"A"*32, clock=lambda: self.now,
                            kdf=lambda password, salt: hashlib.scrypt(password.encode(), salt=salt,n=1024,r=8,p=1,dklen=32))

    def req(self, verb, path, data=None, token=None, **overrides):
        body=json.dumps(data if data is not None else {}).encode()
        env={"wsgi.url_scheme":"https","REMOTE_ADDR":"192.0.2.1","PATH_INFO":BASE+path,
             "REQUEST_METHOD":verb,"CONTENT_TYPE":"application/json","CONTENT_LENGTH":str(len(body)),
             "wsgi.input":io.BytesIO(body)}
        if token:
            env["HTTP_AUTHORIZATION"]="Bearer "+token
        env.update(overrides)
        status=[]
        out=b"".join(self.api(env,lambda s,h: status.append(int(s.split()[0]))))
        return status[0],json.loads(out)

    def register(self, name="Turing", email=None):
        status, data=self.req("POST","/register",{"username":name,"email":email or name+"@example.org","password":"a suitable long phrase"})
        self.assertEqual(status,200,data)
        return data["token"]

    def test_dead_players_wait_five_minutes_across_sessions(self):
        token = self.register()
        code, first = self.req("POST", "/runs", {}, token)
        self.assertEqual(code, 200)
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            db.execute("UPDATE runs SET phase='dead',seen=? WHERE id=?", (self.now, first["id"]))
        self.now += 299.9
        self.assertEqual(self.req("POST", "/runs", {}, token), (409, {"error":"reviving"}))
        self.now += 0.1
        code, fresh = self.req("POST", "/runs", {}, token)
        self.assertEqual(code, 200)
        self.assertNotEqual(first["id"], fresh["id"])
        self.assertEqual(fresh["hp"], 100)

    def test_real_scrypt_and_account_privacy_revocation(self):
        self.api.kdf=derive
        token=self.register()
        status,other=self.req("POST","/login",{"username":"TURING@example.org","password":"a suitable long phrase"})
        self.assertEqual(status,200)
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            salt,key,ident=db.execute("SELECT salt,verifier,email_key FROM users").fetchone()
            self.assertEqual((len(salt),len(key),len(ident)),(16,32,64))
            self.assertNotEqual(ident,"turing@example.org")
            stored={entry[0] for entry in db.execute("SELECT token_hash FROM sessions")}
            self.assertNotIn(token,stored)
            self.assertIn(hashlib.sha256(token.encode()).hexdigest(),stored)
        self.assertEqual(self.req("GET","/me",token=token)[1],{"username":"Turing","kills":0,"deaths":0,"kd":None,"wins":0,"score":0})
        self.assertEqual(self.req("POST","/logout",{},token)[0],200)
        self.assertEqual(self.req("GET","/me",token=token)[0],401)
        self.assertEqual(self.req("GET","/me",token=other["token"])[0],200)
        self.now+=31*86400
        self.assertEqual(self.req("GET","/me",token=other["token"])[0],401)

    def test_boundaries_auth_validation_limits_and_forged_scores(self):
        for path,verb in [("/me","GET"),("/leaderboard","GET"),("/runs","POST"),("/runs/"+"a"*32,"GET")]:
            self.assertEqual(self.req(verb,path)[0],401)
        self.assertEqual(self.req("POST","/register",{},HTTP_ORIGIN="https://example.org")[0],403)
        self.assertEqual(self.req("POST","/register",{},**{"wsgi.url_scheme":"http","HTTP_X_FORWARDED_PROTO":"https"})[0],403)
        self.assertEqual(self.req("POST","/register",{},CONTENT_TYPE="text/plain")[0],415)
        self.assertEqual(self.req("POST","/register",{},CONTENT_LENGTH="99999")[0],400)
        self.assertEqual(self.req("POST","/register",{"username":"no","email":"bad","password":"short"})[0],400)
        token=self.register()
        self.assertEqual(self.req("POST","/runs",{"kills":100,"score":999},token)[0],400)
        self.assertEqual(self.req("POST","/register",{"username":"TURING","email":"other@example.net","password":"longlongpassword"})[0],409)
        for _ in range(14):
            self.assertEqual(self.req("POST","/login",{"username":"unknown","password":"bad"})[0],401)
        self.assertEqual(self.req("POST","/login",{"username":"unknown","password":"bad"})[0],429)

    def test_clock_state_and_idempotent_click(self):
        token=self.register()
        _,frame=self.req("POST","/runs",{},token)
        path="/runs/"+frame["id"]
        self.assertEqual(self.req("POST","/runs",{},token)[1]["id"],frame["id"])
        guest=self.register("Ada")
        self.assertEqual(self.req("GET",path,token=guest)[0],404)
        self.assertEqual(self.req("POST",path+"/click",{"seq":3,"x":1,"y":1},token)[0],409)
        self.assertEqual(self.req("POST",path+"/click",{"seq":1,"x":1,"y":1,"time":99},token)[0],400)
        self.assertEqual(self.req("POST",path+"/click",{"seq":1,"x":0,"y":0},token)[1]["assists"],0)
        x,y=self.ink(frame)
        result=self.req("POST",path+"/click",{"seq":2,"x":x,"y":y},token)[1]
        self.assertEqual((result["seq"],result["assists"],result["ranked"]),(2,1,True))
        self.assertEqual(self.req("POST",path+"/click",{"seq":2,"x":x,"y":y},token)[1],result)
        # No host time passed. Even a fresh sequence cannot apply another hit yet.
        self.assertEqual(self.req("POST",path+"/click",{"seq":3,"x":x,"y":y},token)[1]["assists"],1)
        self.now+=30
        self.assertEqual(self.req("GET",path,token=token)[1]["phase"],"expired")
        self.assertEqual(self.req("GET","/me",token=token)[1]["deaths"],1)
        self.assertEqual(self.req("GET",path,token=token)[1]["phase"],"expired")
        self.assertEqual(self.req("GET","/me",token=token)[1]["deaths"],1)

    def ink(self, frame):
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            arena=game.restore(db.execute("SELECT state FROM runs WHERE id=?",(frame["id"],)).fetchone()[0])
        x,y,w,h=next(iter(arena.hit_rects()))
        return x+w/2,y+h/2

    def test_full_health_restore_consumes_pickup_without_ranking_round(self):
        token = self.register()
        _, frame = self.req("POST", "/runs", {}, token)
        path = "/runs/" + frame["id"]
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            arena = game.restore(db.execute("SELECT state FROM runs WHERE id=?", (frame["id"],)).fetchone()[0])
            arena.pickups.append(Pickup("restore", 120, 62, 999))
            self.assertEqual(arena.player_hp, 100)
            db.execute("UPDATE runs SET state=? WHERE id=?", (game.dump(arena), frame["id"]))
        status, ack = self.req("POST", path + "/click", {"seq": 1, "x": 120, "y": 62}, token)
        self.assertEqual(status, 200)
        self.assertEqual(ack["pickups"], [])
        self.assertEqual(ack["assists"], 0)
        self.assertFalse(ack["ranked"])
        self.now += 30
        self.assertEqual(self.req("GET", "/leaderboard", token=token)[1], {"players": []})

    def test_passive_round_never_ranks_and_ranked_boss_is_finalized_once(self):
        token=self.register()
        _,frame=self.req("POST","/runs",{},token)
        path="/runs/"+frame["id"]
        for _ in range(15):
            self.now+=10
            status,frame=self.req("GET",path,token=token)
            self.assertEqual(status,200)
            if frame["phase"] in ("dead","victory","expired"):
                break
        self.assertIn(frame["phase"],("dead","victory"))
        self.assertFalse(frame["ranked"])
        self.assertEqual(self.req("GET","/leaderboard",token=token)[1],{"players":[]})
        if frame["phase"] == "dead":
            status, reply = self.req("POST", "/runs", {}, token)
            self.assertEqual((status, reply), (409, {"error": "reviving"}))
            self.now += 300
        status,frame=self.req("POST","/runs",{},token)
        self.assertEqual(status, 200, frame)
        path="/runs/"+frame["id"]
        # Deterministic fixture with the boss one real, pixel-tested tap from defeat.
        arena=Arcade(seed=42)
        arena.wave=3; arena.enemies=[]; arena._start_wave()
        arena.enemies[0].hp=1
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            db.execute("UPDATE runs SET state=? WHERE id=?",(game.dump(arena),frame["id"]))
        x,y=self.ink(frame)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as threads:
            results=list(threads.map(lambda _: self.req("POST",path+"/click",{"seq":1,"x":x,"y":y},token),range(2)))
        for status,end in results:
            self.assertEqual(status,200)
            self.assertEqual((end["phase"],end["score"],end["kills"]),("victory",600,1))
        wanted={"username":"Turing","kills":1,"deaths":0,"kd":None,"wins":1,"score":600}
        self.assertEqual(self.req("GET","/me",token=token)[1],wanted)
        self.assertEqual(self.req("GET","/leaderboard",token=token)[1],{"players":[{"rank":1,**wanted}]})

    def test_portable_client_reads_a_production_server_frame_and_leaderboard(self):
        # Exercise the actual clients' JSON contract without contacting a public account.
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Desktop"))
        self.addCleanup(sys.path.pop, 0)
        from arena_wire import ArenaClient, RemoteFrame, leaderboard_rows
        from urllib.parse import urlsplit

        endpoint = self
        class Transport:
            def open(self, request, timeout):
                path = urlsplit(request.full_url).path.removeprefix(BASE)
                token = request.get_header("Authorization", "").removeprefix("Bearer ")
                payload = json.loads(request.data) if request.data else None
                status, answer = endpoint.req(request.get_method(), path, payload, token)
                endpoint.assertEqual(status, 200, answer)
                return io.BytesIO(json.dumps(answer).encode())

        client = ArenaClient(opener=Transport())
        user = client.request("POST", "/register", {"username": "Ada", "email": "ada@example.com",
                                                   "password": "correct horse lamp"})
        frame = client.request("POST", "/runs", {}, user["token"])
        self.assertEqual(RemoteFrame(frame, str).phase, "wave")
        x, y = self.ink(frame)
        ack = client.request("POST", "/runs/" + frame["id"] + "/click",
                             {"seq": 1, "x": x, "y": y}, user["token"])
        self.assertTrue(ack["ranked"])
        self.assertEqual(RemoteFrame(ack, str).phase, "wave")
        self.now += 30
        rows = leaderboard_rows(client.request("GET", "/leaderboard", token=user["token"]))
        self.assertEqual(rows, [(1, "Ada", 0, 1, 0.0, 0, 0)])

    def test_legacy_snapshot_resumes_without_resetting_ranked_counters_or_sequence(self):
        token = self.register()
        _, frame = self.req("POST", "/runs", {}, token)
        path = "/runs/" + frame["id"]
        arena = Arcade(seed=99)
        arena.player_hp = 69
        arena.enemies[0].hp = 3
        arena.kills = 2
        legacy = json.loads(game.dump(arena))
        for name in ("_assists", "_manual_damage", "_manual_pickups", "_personal_kills",
                     "_last_hits", "_kill_bonus", "_personal_boss", "_boss_last_hit"):
            legacy.pop(name)
        for enemy in legacy["enemies"]:
            enemy.pop("manual_damage")
        with closing(sqlite3.connect(self.db, isolation_level=None)) as db:
            db.execute("UPDATE runs SET state=?,kills=2,assists=4,seq=5 WHERE id=?",
                       (json.dumps(legacy), frame["id"]))
        status, resumed = self.req("GET", path, token=token)
        self.assertEqual(status, 200)
        self.assertEqual((resumed["hp"], resumed["kills"], resumed["assists"], resumed["seq"]), (69, 2, 4, 5))
        x, y = self.ink(resumed)
        click = {"seq": 6, "x": x, "y": y}
        status, ack = self.req("POST", path + "/click", click, token)
        self.assertEqual(status, 200)
        self.assertEqual((ack["hp"], ack["kills"], ack["assists"], ack["score"]), (69, 3, 5, 300))
        self.assertEqual(self.req("POST", path + "/click", click, token)[1], ack)

    def test_state_roundtrip_matches_fresh_engine_for_each_tick(self):
        original=Arcade(seed=1337)
        restored=game.restore(game.dump(original))
        for _ in range(360):
            original._advance(original.step)
            restored._advance(restored.step)
        self.assertEqual(json.loads(game.dump(original)),json.loads(game.dump(restored)))

if __name__=="__main__":
    unittest.main()
