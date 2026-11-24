"""Persist trusted simulation state between workers, with a server clock and no client scores."""
import json
import math
import secrets
from dataclasses import asdict

from Desktop.arcade import Arcade, Enemy, Pickup, Shot

TIMEOUT = 25
MAX_SECONDS = 180


def dump(arena):
    state = {k: v for k, v in vars(arena).items()
             if k not in {"random", "translate", "enemies", "shots", "pickups", "_cues"}}
    if math.isinf(state["next_wave"]):
        state["next_wave"] = None
    state.update(rng=arena.random.getstate(), enemies=[asdict(e) for e in arena.enemies],
                 shots=[asdict(s) for s in arena.shots], pickups=[asdict(p) for p in arena.pickups])
    return json.dumps(state, separators=(",", ":"), allow_nan=False)


def restore(payload):
    state = json.loads(payload)
    # Older snapshots predate personal-damage and boss counters. Start with the
    # engine's current defaults, then replace the simulation and RNG with the saved state.
    arena = Arcade(seed=0)
    version, vector, gaussian = state.pop("rng")
    arena.random.setstate((version, tuple(vector), gaussian))
    arena._cues = []
    arena.enemies = [Enemy(**e) for e in state.pop("enemies")]
    arena.shots = [Shot(**s) for s in state.pop("shots")]
    arena.pickups = [Pickup(**p) for p in state.pop("pickups")]
    if state["next_wave"] is None:
        state["next_wave"] = math.inf
    arena.__dict__.update(state)
    return arena


def create(db, uid, now):
    arena = Arcade(secrets.randbits(128))
    ident = secrets.token_hex(16)
    db.execute("INSERT INTO runs(id,user_id,created,seen,state) VALUES(?,?,?,?,?)", (ident, uid, now, now, dump(arena)))
    return db.execute("SELECT * FROM runs WHERE id=?", (ident,)).fetchone()


def finish(db, row, phase, kills, assists, boss_assist, now):
    won = phase == "victory" and boss_assist
    died = phase in ("expired", "dead")
    score = kills * 100 + int(won) * 500
    if assists:
        db.execute("UPDATE users SET kills=kills+?,deaths=deaths+?,wins=wins+?,score=score+? WHERE id=?",
                   (kills, int(died), int(won), score, row["user_id"]))
    db.execute("UPDATE runs SET phase=?,seen=?,score=? WHERE id=?", (phase, now, score, row["id"]))
    return score


def expire(db, now, uid=None):
    params = [now - TIMEOUT, now - MAX_SECONDS]
    sql = "SELECT * FROM runs WHERE phase='playing' AND (seen<? OR created<?)"
    if uid is not None:
        sql += " AND user_id=?"
        params.append(uid)
    # Bound work per request while draining old unattended rounds.
    for row in db.execute(sql + " LIMIT 128", params).fetchall():
        finish(db, row, "expired", row["kills"], row["assists"], row["boss_assist"], now)


def frame(db, row, now, click=None):
    arena = restore(row["state"])
    phase, kills, assists, boss_assist = row["phase"], row["kills"], row["assists"], row["boss_assist"]
    seq, score = row["seq"], row["score"]
    if phase == "playing":
        # Number of elapsed fixed ticks comes exclusively from the host clock.
        target = max(row["ticks"], min(MAX_SECONDS * 60, int((now - row["created"]) * 60)))
        ticks = row["ticks"]
        while ticks < target and arena.playing:
            arena._advance(arena.step)
            ticks += 1
        if click is not None and arena.playing and click[0] == seq + 1:
            seq, x, y = click
            target_object = arena._target(x, y)
            previous = arena.stats
            arena.click(x, y)
            current = arena.stats
            dealt_damage = current["manualDamage"] > previous["manualDamage"]
            effective_pickup = current["manualPickups"] > previous["manualPickups"]
            if dealt_damage or effective_pickup:
                assists += 1
                kills += current["lastHits"] - previous["lastHits"]
                if dealt_damage and isinstance(target_object, Enemy) and target_object.kind == "boss":
                    boss_assist = 1
        if arena.playing:
            phase = arena.phase
            score = kills * 100
        else:
            phase = arena.phase
            score = finish(db, row, phase, kills, assists, boss_assist, now)
        db.execute("UPDATE runs SET state=?,seen=?,ticks=?,seq=?,kills=?,assists=?,boss_assist=? WHERE id=?",
                   (dump(arena), now, ticks, seq, kills, assists, boss_assist, row["id"]))
    return {"id": row["id"], "phase": phase, "wave": arena.wave, "hp": arena.player_hp,
            "time": round(arena.time, 4), "shield": round(arena.shield, 3), "rapidFire": round(arena.rapid_fire, 3),
            "hero": {"x": round(arena.hero[0], 2), "y": round(arena.hero[1], 2)},
            "enemies": [{"id": e.serial, "kind": e.kind, "x": round(e.x, 2), "y": round(e.y, 2),
                         "radius": e.radius, "hp": e.hp, "maxHP": e.max_hp} for e in arena.enemies],
            "pickups": [{"id": p.serial, "kind": p.kind, "x": round(p.x, 2), "y": round(p.y, 2),
                         "radius": p.radius} for p in arena.pickups],
            "shots": [{"x": round(s.x, 2), "y": round(s.y, 2), "hostile": s.hostile} for s in arena.shots],
            "kills": kills, "assists": assists, "ranked": bool(assists), "seq": seq, "score": score}
