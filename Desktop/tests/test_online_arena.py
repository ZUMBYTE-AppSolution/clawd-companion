import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import unittest
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from arena_wire import ArenaClient, ArenaError, BASE_URL, RemoteFrame, _NoRedirect, leaderboard_rows, validate_account


RUN = {
    "id": "1234567890abcdef1234567890abcdef", "phase": "wave", "wave": 1, "hp": 95,
    "hero": {"x": 35, "y": 78}, "kills": 0, "assists": 2, "ranked": True, "seq": 2, "score": 12,
    "enemies": [{"id": 2, "kind": "spore", "x": 150, "y": 85, "radius": 12, "hp": 8, "maxHP": 20}],
    "pickups": [{"id": 3, "kind": "shield", "x": 200, "y": 85, "radius": 7}],
    "shots": [{"x": 95, "y": 95, "hostile": False}],
}


class StubOpener:
    def __init__(self, answer):
        self.answer = answer
        self.requests = []

    def open(self, request, timeout):
        self.requests.append(request)
        if isinstance(self.answer, Exception):
            raise self.answer
        return io.BytesIO(self.answer)


class OnlineArenaTests(unittest.TestCase):
    def test_fixed_https_route_bearer_and_click_payload_no_external_request(self):
        stub = StubOpener(json.dumps(RUN).encode())
        client = ArenaClient(stub)
        payload = {"x": 150, "y": 85, "seq": 3}
        path = "/runs/" + RUN["id"] + "/click"
        self.assertEqual(client.request("POST", path, payload, "test-token"), RUN)
        sent = stub.requests[0]
        self.assertEqual(sent.full_url, BASE_URL + path)
        self.assertEqual(sent.get_header("Authorization"), "Bearer test-token")
        self.assertEqual(json.loads(sent.data), payload)
        for invalid in ("https://elsewhere.invalid/login", "//elsewhere.invalid", "/runs/../me", "/login?x=1"):
            with self.assertRaises(ArenaError):
                client.request("POST", invalid, {}, "test-token")
        with self.assertRaises(ArenaError):
            client.request("POST", "/login", {}, "broken\nheader")
        self.assertEqual(len(stub.requests), 1)
        self.assertIsNone(_NoRedirect().redirect_request(sent, None, 307, "", {}, "https://elsewhere.invalid/"))

    def test_invalid_json_error_responses_and_size_are_bounded(self):
        for content in (b"[1]", b"not json", b"x" * (257 * 1024)):
            with self.assertRaises(ArenaError):
                ArenaClient(StubOpener(content)).request("GET", "/leaderboard")
        error = HTTPError(BASE_URL+"/login", 401, "", {}, io.BytesIO(b'{"error":"invalid_credentials"}'))
        with self.assertRaises(ArenaError) as denied:
            ArenaClient(StubOpener(error)).request("POST", "/login", {})
        self.assertEqual((denied.exception.code, denied.exception.http), ("invalid_credentials", 401))

    def test_remote_frame_keeps_server_stats_and_only_supplied_sprites(self):
        frame = RemoteFrame(RUN, str, clock=2)
        self.assertEqual((frame.id, frame.seq, frame.score, frame.kills, frame.assists, frame.ranked),
                         (RUN["id"], 2, 12, 0, 2, True))
        self.assertEqual((frame.scene.hero, frame.scene.player_hp), ((35, 78), 95))
        self.assertEqual([e.kind for e in frame.scene.enemies], ["spore"])
        self.assertTrue(frame.scene.target_at(150, 85))
        self.assertTrue(frame.scene.target_at(200, 85))
        self.assertFalse(frame.scene.target_at(15, 12))
        self.assertFalse(frame.scene.target_at(95, 95))
        for field, value in [("ranked", "true"), ("id", "../me"), ("phase", "unknown"), ("seq", -1),
                             ("hp", float("nan")), ("shots", [{}]), ("pickups", [None]*300)]:
            payload = dict(RUN, **{field: value})
            with self.subTest(field=field), self.assertRaises(ArenaError):
                RemoteFrame(payload, str)
        payload = copy.deepcopy(RUN)
        payload["enemies"][0]["kind"] = "unknown"
        with self.assertRaises(ArenaError):
            RemoteFrame(payload, str)

    def test_account_validation_and_table(self):
        validate_account("pixel.07", "a"*12, "pixel@example.test")
        validate_account("pixel@example.test", "a"*12)
        for name, pw, email in (("x", "s"*12, None), ("valid", "short", None), ("person", "s"*12, "broken")):
            with self.assertRaises(ArenaError):
                validate_account(name, pw, email)
        self.assertEqual(leaderboard_rows({"players": []}), [])
        row = dict(rank=1, username="player7", kills=9, deaths=2, kd=4.5, wins=1, score=500)
        self.assertEqual(leaderboard_rows({"players":[row]})[0], (1, "player7", 9, 2, 4.5, 1, 500))
        self.assertIsNone(leaderboard_rows({"players":[dict(row, deaths=0, kd=None)]})[0][4])
        self.assertIsNone(leaderboard_rows({"players":[dict(row, deaths=0, kd=0)]})[0][4])
        with self.assertRaises(ArenaError):
            leaderboard_rows({"players": [dict(row, kd=None)]})
        with self.assertRaises(ArenaError):
            leaderboard_rows({"players": [dict(row, kd=float("nan"))]})

    @unittest.skipUnless((Path(__file__).resolve().parents[2] / "Server/tests/test_api.py").is_file(),
                         "Server contract fixtures are only included in the source checkout")
    def test_authoritative_local_server_frame_and_idempotent_pixel_hit(self):
        from Server.tests.test_api import ArenaTests

        local = ArenaTests()
        local.setUp()
        self.addCleanup(local.doCleanups)
        token = local.register()
        status, payload = local.req("POST", "/runs", {}, token)
        self.assertEqual(status, 200)
        path = "/runs/" + payload["id"]
        local.now += .12
        status, payload = local.req("GET", path, token=token)
        self.assertEqual(status, 200)
        frame = RemoteFrame(payload, str)
        enemy = frame.scene.enemies[0]
        self.assertTrue(frame.scene.target_at(enemy.x, enemy.y))
        click = {"seq": frame.seq+1, "x": enemy.x, "y": enemy.y}
        for _ in range(2):
            status, payload = local.req("POST", path+"/click", click, token)
            self.assertEqual(status, 200)
            acknowledged = RemoteFrame(payload, str)
            self.assertTrue(acknowledged.ranked)
            self.assertEqual((acknowledged.assists, acknowledged.seq), (1, click["seq"]))

    @unittest.skipUnless(importlib.util.find_spec("PySide6"), "PySide6 not installed")
    def test_widget_applies_server_frames_retries_same_click_and_retains_login_on_stop(self):
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        from PySide6.QtWidgets import QApplication
        from online_arena import OnlineArenaWidget
        app = QApplication.instance() or QApplication([])
        stub = StubOpener(b"{}")
        widget = OnlineArenaWidget(str, lambda: True, client=ArenaClient(stub))
        try:
            self.assertEqual(stub.requests, [])
            widget._accept("login", {"token": "session-token", "username":"player7"})
            widget._accept("start", RUN)
            self.assertTrue(widget.is_playing())
            widget._click(99, 120)
            self.assertIsNone(widget._next_click)
            widget._click(150, 85)
            expected = {"x":150, "y":85, "seq":3}
            self.assertEqual(widget._next_click, expected)
            widget._failure("click", ArenaError("network"))
            self.assertEqual(widget._next_click, expected)
            widget._accept("click", dict(RUN, seq=3, score=18))
            self.assertIsNone(widget._next_click)
            self.assertEqual(widget.canvas.frame.score, 18)
            outcomes = []
            widget.roundEnded.connect(lambda run_id, phase: outcomes.append((run_id, phase)))
            for _ in range(2):
                widget._accept("poll", dict(RUN, phase="dead", hp=0, seq=3))
            self.assertEqual(outcomes, [(RUN["id"], "dead")])
            widget.stop()
            self.assertFalse(widget.is_playing())
            self.assertEqual(widget._username, "player7")
            self.assertEqual(stub.requests, [])
        finally:
            widget._shutdown()
            widget.close()
        self.assertIsNotNone(app)


if __name__ == "__main__":
    unittest.main()
