import io
import queue
from http.client import HTTPMessage
import http.client
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import code_link
from desktop_core import (ASSETS, DEFAULTS, LANGUAGES, SOUNDS, BrowserBridge, Language, PointerVolley,
                          Preferences, clean_event, pairing_token, projectile_ink, intersects, receive_event, record_round, ranked_terminal)


class DesktopCoreTests(unittest.TestCase):
    def test_sprites_languages_and_sound_resources(self):
        import struct
        import wave
        for name in ("mascot-atlas","menu-atlas"):
            info=json.loads((ASSETS/(name+".json")).read_bytes())
            with (ASSETS/(name+".png")).open("rb") as f:
                f.seek(16)
                self.assertEqual(struct.unpack(">II",f.read(8)),(info["columns"]*info["cellWidth"],info["rows"]*info["cellHeight"]))
            self.assertTrue({"planning","perched","juggling","typing","letterBlaster","grave","reviving"}<=info["poses"].keys())
        for name in (*SOUNDS,"wave-loop","boss-loop"):
            with wave.open(str(ASSETS/"sounds"/(name+".wav"))) as f:
                self.assertEqual(f.getsampwidth(),2)
                self.assertGreater(f.getnframes(),80)
        language=Language("de")
        for code in LANGUAGES:
            language.select(code)
            self.assertEqual(language.code,code)
            for key in (*SOUNDS.values(),"Spazieren","Sprache","Highscores","Tode","Virenarena"):
                self.assertTrue(language.entries[key][code])

    def test_preferences_and_engaged_terminal_stats_survive_restart_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"desktop.json"
            prefs=Preferences(path)
            self.assertFalse(record_round(prefs,"auto",{"engaged":False,"score":0,"deaths":1}))
            stats=dict(engaged=True,score=83,lastHits=2,personalKills=4,personalDeaths=0,personalVictories=1,bossLastHit=True)
            self.assertTrue(record_round(prefs,"r1",stats))
            self.assertFalse(record_round(prefs,"r1",stats))
            prefs["graveUntil"]=deadline=time.time()+300
            prefs.save()
            restored=Preferences(path)
            self.assertEqual(restored["graveUntil"],deadline)
            self.assertFalse(record_round(restored,"r1",stats))
            self.assertEqual(restored["highscore"],dict(rounds=1,score=83,personalKills=2,personalDeaths=0,personalVictories=1,personalBoss=1))
            self.assertEqual(DEFAULTS["highscore"],{})

    def test_server_confirmed_death_does_not_extend_after_refresh_or_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"desktop.json"
            prefs=Preferences(path)
            self.assertFalse(ranked_terminal(prefs,"r1","expired",1010))
            self.assertTrue(ranked_terminal(prefs,"r1","dead",1010))
            self.assertEqual(prefs["graveUntil"],1310)
            restored=Preferences(path)
            self.assertFalse(ranked_terminal(restored,"r1","dead",1400))
            self.assertEqual(restored["graveUntil"],1310)
            self.assertTrue(ranked_terminal(restored,"r2","victory",1500))
            self.assertEqual(restored["graveUntil"],1310)
            self.assertEqual(restored["highscore"],{})

    def test_volley_counts_only_intersections_and_retargets_each_release(self):
        sizes={PointerVolley(True,random.Random(seed)).total for seed in range(500)}
        self.assertEqual((min(sizes),max(sizes)),(3,42))
        volley=PointerVolley(False,random.Random(3))
        results=[]
        for i in range(180):
            new,_=volley.tick(i/30,(0,0),(200,0))
            results+=new
        self.assertFalse(volley.running)
        self.assertEqual(results,[True])
        dodge=PointerVolley(False,random.Random(4))
        results=[]
        for i in range(180):
            new,_=dodge.tick(i/30,(0,0),(200,0) if i<10 else (200,100))
            results+=new
        self.assertEqual(results,[False])
        volley=PointerVolley(True,random.Random(2))
        angles=[]
        for i in range(60):
            _,fired=volley.tick(i/30,(0,0),(200,0) if i<12 else (0,200))
            if fired:
                angles.append(volley.shots[-1][2:4])
        self.assertGreater(angles[0][0],abs(angles[0][1]))
        self.assertGreater(angles[-1][1],abs(angles[-1][0]))
        before=list(volley.shots)
        self.assertEqual(volley.tick(100,(0,0),(0,0)),([],False))
        self.assertEqual(volley.shots,before)

    def test_transparent_center_of_pixel_letter_does_not_score(self):
        outline,_ = projectile_ink("O",True)
        self.assertFalse(any(intersects(r, (0,0),(0,0)) for r in outline))
        self.assertTrue(any(intersects(r,(0,0),(8,0)) for r in outline))
        self.assertFalse(any(intersects(r,(0,-10),(2,-10)) for r in outline))

    def test_quota_and_notices_never_carry_conversation_fields(self):
        sample={"type":"usage","observedAt":"2026-11-24T12:03:00Z","conversation":"no",
                "windows":[{"kind":"session","remainingPercent":37,"resetAt":"2026-11-24T14:20:00Z","text":"no"}]}
        out=clean_event(sample)
        self.assertEqual(out["windows"][0]["remainingPercent"],37)
        self.assertNotIn("text",out["windows"][0])
        self.assertNotIn("conversation",out)
        sample["windows"].append(sample["windows"][0])
        self.assertIsNone(clean_event(sample))
        for data in (None,{},{"type":"activity","state":[]},{"type":"approval","waiting":1,"sourceID":"x"}):
            self.assertIsNone(clean_event(data))
        msg=clean_event({"type":"notice","kind":"info","title":"Claude","message":"Hi\x00there","other":"secret"})
        self.assertEqual(msg,dict(type="notice",kind="info",title="Claude",message="Hi there"))


class IntegrationTests(unittest.TestCase):
    def test_request_validation_without_a_socket(self):
        events=queue.Queue(maxsize=1)
        data=b'{"type":"activity","state":"thinking"}'
        def send(**override):
            fields={"Host":"127.0.0.1:49217", "Content-Type":"application/json", "Authorization":"Bearer token",
                    "Origin":"chrome-extension://"+"a"*32, "Content-Length":str(len(data)), **override}
            headers=HTTPMessage()
            for key,value in fields.items():
                headers.add_header(key,value)
            return receive_event("/v1/events",headers,io.BytesIO(data),49217,"token",events)
        self.assertEqual(send(Authorization="Bearer nope"),401)
        self.assertEqual(send(Host="untrusted"),403)
        self.assertEqual(send(Origin="https://untrusted"),403)
        self.assertEqual(send(**{"Transfer-Encoding":"chunked"}),400)
        self.assertEqual(send(**{"Content-Length":"9000"}),413)
        self.assertEqual(send(**{"Content-Type":"text/html"}),415)
        self.assertEqual(send(),200)
        self.assertEqual(send(),503)
        self.assertEqual(events.get_nowait(),{"type":"activity","state":"thinking"})

    def test_bridge_checks_token_origin_size_and_host_and_delivers_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            key=pairing_token(Path(tmp))
            self.assertEqual(key,pairing_token(Path(tmp)))
            if os.name!="nt":
                self.assertEqual((Path(tmp)/"pairing.key").stat().st_mode&0o077,0)
            try:
                bridge=BrowserBridge(key,0)
            except PermissionError:
                self.skipTest("Loopback listen disabled by this executor")
            port=bridge.server.server_port
            sample=b'{"type":"activity","state":"planning"}'
            def send(body=sample,**headers):
                opts={"Authorization":"Bearer "+key,"Content-Type":"application/json","Origin":"chrome-extension://"+"a"*32}
                opts.update(headers)
                connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
                try:
                    connection.request("POST","/v1/events",body,opts)
                    return connection.getresponse().status
                finally:
                    connection.close()
            try:
                self.assertEqual(send(Authorization="Bearer nope"),401)
                self.assertEqual(send(Origin="https://claude.ai"),403)
                self.assertEqual(send(Host="foreign.test"),403)
                self.assertEqual(send(body=b"a"*8193),413)
                self.assertEqual(send(body=b"{}"),400)
                self.assertEqual(send(),200)
                self.assertEqual(bridge.events.get_nowait(),{"type":"activity","state":"planning"})
                self.assertTrue(bridge.events.empty())
            finally:
                bridge.close()

    def test_hook_install_is_idempotent_and_existing_status_line_roundtrips(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"settings.json"
            original={"sandbox":{"enabled":True},"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"my-other-hook"}]}]},
                      "statusLine":{"type":"command","command":"cat | something --custom","padding":2}}
            path.write_text(json.dumps(original))
            for key in ("hooks","quota"):
                code_link.configure(key,True,path)
                once=path.read_bytes()
                code_link.configure(key,True,path)
                self.assertEqual(path.read_bytes(),once)
            for key in ("hooks","quota"):
                code_link.configure(key,False,path)
            self.assertEqual(json.loads(path.read_bytes()),original)
            path.write_bytes(b"{ broken")
            with self.assertRaises(ValueError):
                code_link.configure("hooks",True,path)
            self.assertEqual(path.read_bytes(),b"{ broken")

    def test_hook_entrypoint_runs_without_qt_and_preserves_status_line_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            env={**os.environ,"APPDATA":tmp,"XDG_CONFIG_HOME":tmp,"CLAUDE_CONFIG_DIR":str(Path(tmp)/"claude")}
            for key in ("hooks","quota"):
                code_link.configure(key,True,Path(tmp)/"claude/settings.json")
            command=[sys.executable,str(Path(code_link.__file__).with_name("companion.py"))]
            raw={"session_id":"my-secret-session","hook_event_name":"SubagentStart","agent_id":"my-agent",
                 "prompt":"private content"}
            p=subprocess.run(command+["--clawd-hook"],input=json.dumps(raw).encode(),env=env,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr)
            contents=list((Path(tmp)/"ClawdCompanion/events").glob("*.json"))
            self.assertEqual(len(contents),1)
            self.assertNotIn("private content",contents[0].read_text())
            self.assertNotIn("my-agent",contents[0].read_text())
            now=time.time()
            raw=json.dumps({"rate_limits":{"five_hour":{"used_percentage":12.8,"resets_at":now+42}},"prompt":"private content"}).encode()+b"\n"
            p=subprocess.run(command+["--clawd-quota-pipe"],input=raw,env=env,capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(p.stdout,raw)
            events=[json.loads(p.read_bytes()) for p in (Path(tmp)/"ClawdCompanion/events").glob("*.json")]
            usage=next(e for e in events if e["type"]=="usage")
            self.assertEqual(usage["windows"][0]["remainingPercent"],87)
            self.assertNotIn("private content",str(events))
