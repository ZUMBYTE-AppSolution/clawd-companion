import CoreGraphics
import XCTest
@testable import ClawdCompanion

@MainActor
final class ManualArenaTests: XCTestCase {
    private func pixel(in frame: VirusArcade.Frame, center: CGPoint, radius: CGFloat,
                       target: VirusArenaPixels.Target?) -> CGPoint? {
        let pixels = Int(ceil(radius))
        for y in -pixels...pixels {
            for x in -pixels...pixels {
                let dx = CGFloat(x) + 0.25, dy = CGFloat(y) + 0.25
                guard dx * dx + dy * dy < radius * radius else { continue }
                let point = CGPoint(x: center.x + dx, y: center.y + dy)
                if VirusArenaPixels.target(at: point, in: frame)?.target == target { return point }
            }
        }
        return nil
    }

    func testOnlyVisibleEnemyPixelsAcceptTaps() throws {
        let arena = ManualArena(makeGame: { VirusArcade(seed: 2) })
        arena.start(now: 0)
        let frame = try XCTUnwrap(arena.frame)
        let enemy = try XCTUnwrap(frame.enemies.first)
        // Both positions are inside the round physics radius, only one has sprite ink.
        let clear = try XCTUnwrap(pixel(in: frame, center: enemy.position, radius: enemy.radius, target: nil))
        let opaque = try XCTUnwrap(pixel(in: frame, center: enemy.position, radius: enemy.radius, target: .enemy(enemy.id)))
        arena.tap(clear)
        arena.tick(now: 0)
        XCTAssertEqual(arena.frame?.enemies.first?.hp, enemy.hp)
        XCTAssertEqual(arena.frame?.stats.manualDamage, 0)
        arena.tap(opaque)
        arena.tap(opaque)
        arena.tick(now: 0)
        XCTAssertEqual(arena.frame?.enemies.first?.hp, enemy.hp - 9)
        XCTAssertEqual(arena.frame?.stats.manualDamage, 9)
        XCTAssertEqual(arena.frame?.stats.assists, 1)
    }

    func testPauseIgnoresClicksAndResumesWithoutChargingPausedTime() throws {
        let arena = ManualArena(makeGame: { VirusArcade(seed: 8) })
        arena.start(now: 100)
        arena.tick(now: 100.1)
        let before = try XCTUnwrap(arena.frame)
        let enemy = try XCTUnwrap(before.enemies.first)
        let aim = try XCTUnwrap(pixel(in: before, center: enemy.position, radius: enemy.radius, target: .enemy(enemy.id)))
        arena.pause()
        XCTAssertTrue(arena.playing)
        XCTAssertTrue(arena.paused)
        arena.tap(aim)
        arena.tick(now: 100.18)
        XCTAssertEqual(arena.frame?.time, before.time)
        XCTAssertEqual(arena.frame?.enemies, before.enemies)
        arena.resume(now: 100.20)
        arena.tick(now: 100.30)
        let after = try XCTUnwrap(arena.frame)
        XCTAssertFalse(arena.paused)
        XCTAssertEqual(after.time, before.time + 0.1, accuracy: 0.0000001)
        XCTAssertEqual(after.stats.manualDamage, 0)
        arena.pause()
        arena.resume(now: 40_000)
        arena.tick(now: 40_000)
        XCTAssertEqual(arena.frame?.time, after.time)
        XCTAssertEqual(arena.frame?.playerHP, after.playerHP)
    }

    func testHelpfulPickupAwardsManualCreditExactlyOnce() throws {
        let arena = ManualArena(makeGame: { VirusArcade(seed: 1) })
        arena.start(now: 0)
        for i in 1...1800 {
            let now = Double(i) / 30
            arena.tick(now: now)
            guard let f = arena.frame, let item = f.pickups.first(where: { pickup in
                switch pickup.kind {
                case .restore: return f.playerHP < 100
                case .shield: return f.shield == 0
                case .rapidFire: return f.rapidFire == 0
                }
            }) else { continue }
            let touch = try XCTUnwrap(pixel(in: f, center: item.position, radius: item.radius, target: .pickup(item.id)))
            arena.tap(touch)
            arena.tick(now: now)
            XCTAssertEqual(arena.frame?.stats.manualPickups, 1)
            XCTAssertFalse(try XCTUnwrap(arena.frame).pickups.contains { $0.id == item.id })
            arena.tap(touch)
            arena.tick(now: now)
            XCTAssertEqual(arena.frame?.stats.manualPickups, 1)
            return
        }
        XCTFail("The seeded run must present a useful, collectible pickup before the end.")
    }

    func testTakeoverPreservesTheExistingRoundAndReportsVictoryOnce() throws {
        var existing = VirusArcade(seed: 2)
        for step in 0...60 { _ = existing.tick(now: Double(step) / 30) }
        let original = existing.frame
        let id = UUID()
        var factoryCalls = 0
        let arena = ManualArena(makeGame: { factoryCalls += 1; return VirusArcade(seed: 5) })
        var results: [(UUID, VirusArcade.RunStats)] = []
        var totals = ArenaTotals()
        arena.onFinish = { completedID, stats in
            results.append((completedID, stats))
            _ = totals.record(id: completedID, stats: stats)
        }
        arena.start(now: 400, existing: (id, existing))
        let adopted = try XCTUnwrap(arena.frame)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(adopted.time, original.time)
        XCTAssertEqual(adopted.enemies, original.enemies)
        XCTAssertEqual(adopted.shots, original.shots)
        XCTAssertEqual(adopted.stats, original.stats)
        XCTAssertFalse(original.shots.isEmpty)
        for step in 1...1800 where arena.playing {
            let now = 400 + Double(step) / 30
            arena.tick(now: now)
            if let f = arena.frame, let foe = f.enemies.first,
               let point = pixel(in: f, center: foe.position, radius: foe.radius, target: .enemy(foe.id)) {
                arena.tap(point)
            }
        }
        XCTAssertFalse(arena.playing)
        arena.tick(now: 550)
        arena.resume(now: 551)
        arena.tick(now: 551.1)
        arena.end()
        XCTAssertEqual(results.map { $0.0 }, [id])
        let stats = try XCTUnwrap(results.first?.1)
        XCTAssertEqual(stats.personalVictories, 1)
        XCTAssertGreaterThan(stats.lastHits, 0)
        XCTAssertGreaterThan(totals.points, 0)
        XCTAssertEqual(totals.points, stats.score)
        XCTAssertEqual(totals.rounds, 1)
        XCTAssertEqual(totals.kills, stats.lastHits)
    }

    func testAbortedFightNeverFinishesAndUnassistedDeathNeverEarnsPersonalPoints() throws {
        let arena = ManualArena(makeGame: { VirusArcade(seed: 2) })
        var results: [VirusArcade.RunStats] = []
        var totals = ArenaTotals()
        arena.onFinish = { id, stats in
            results.append(stats)
            _ = totals.record(id: id, stats: stats)
        }
        arena.start(now: 0)
        let f = try XCTUnwrap(arena.frame)
        let e = try XCTUnwrap(f.enemies.first)
        arena.tap(try XCTUnwrap(pixel(in: f, center: e.position, radius: e.radius, target: .enemy(e.id))))
        arena.tick(now: 0)
        XCTAssertTrue(try XCTUnwrap(arena.frame).stats.engaged)
        arena.end()
        arena.tick(now: 0.1)
        XCTAssertFalse(arena.playing)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(totals.rounds, 0)

        arena.start(now: 12)
        for step in 1...2100 where arena.playing {
            arena.tick(now: 12 + Double(step) / 30)
        }
        arena.tick(now: 200)
        XCTAssertEqual(results.count, 1)
        let stats = try XCTUnwrap(results.first)
        XCTAssertEqual(stats.deaths, 1)
        XCTAssertFalse(stats.engaged)
        XCTAssertEqual(stats.score, 0)
        XCTAssertEqual(totals, ArenaTotals())
    }
}
