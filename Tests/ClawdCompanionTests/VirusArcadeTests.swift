import CoreGraphics
import XCTest
@testable import ClawdCompanion

final class VirusArcadeTests: XCTestCase {
    func testRandomOpponentsHaveDifferentCountsSizesKindsAndIndependentHealth() {
        var sizes = Set<CGFloat>(), health = Set<Int>(), counts = Set<Int>()
        var kinds = Set<VirusArcade.Kind>()
        var healthBySize: [CGFloat: Set<Int>] = [:]
        for seed in UInt64(0)..<48 {
            let frame = VirusArcade(seed: seed).frame
            XCTAssertEqual(frame.phase, .wave)
            XCTAssertEqual(frame.wave, 1)
            XCTAssertEqual(frame.playerHP, 100)
            XCTAssertTrue((2...4).contains(frame.enemyTotal))
            let first = frame.enemies[0]
            XCTAssertEqual(first.hp, first.maxHP)
            XCTAssertGreaterThan(first.maxHP, 0)
            sizes.insert(first.radius)
            health.insert(first.maxHP)
            healthBySize[first.radius, default: []].insert(first.hp)
            counts.insert(frame.enemyTotal)
            kinds.insert(first.kind)
        }
        XCTAssertEqual(counts, [2, 3, 4])
        XCTAssertEqual(kinds, [.bug, .worm, .spore])
        XCTAssertGreaterThan(sizes.count, 3)
        XCTAssertGreaterThan(health.count, 5)
        XCTAssertTrue(healthBySize.values.contains { $0.count > 1 })
    }

    func testFixedStepIsIndependentOfPresentationRateAndLongGapsFreezeCombat() {
        var fast = VirusArcade(seed: 4)
        var slow = fast
        for i in 0...1440 { _ = fast.tick(now: Double(i) / 120) }
        for i in 0...96 { _ = slow.tick(now: Double(i) / 8) }
        let before = fast.frame
        XCTAssertEqual(slow.frame, before)
        XCTAssertEqual(before.time, 12, accuracy: 0.000001)
        XCTAssertFalse(before.shots.isEmpty)
        XCTAssertEqual(fast.tick(now: 4000), before)
        XCTAssertEqual(fast.tick(now: 3999.9), before)
        XCTAssertEqual(fast.tick(now: 4000), before)

        fast.pause()
        XCTAssertEqual(fast.tick(now: 5000), before)
        fast.resume(now: 6000)
        XCTAssertEqual(fast.tick(now: 6000), before)
        _ = fast.tick(now: 6000 + 0.125)
        _ = slow.tick(now: 12 + 0.125)
        XCTAssertEqual(fast.frame, slow.frame)
    }

    func testClickRequiresLiveTargetAndCannotDuplicateDamageAtSameTime() {
        var game = VirusArcade(seed: 4)
        let first = game.frame.enemies[0]
        game.hit(at: CGPoint(x: first.position.x, y: first.position.y + first.radius + 1))
        game.hit(enemyID: -1)
        game.collect(pickupID: first.id)
        XCTAssertEqual(game.frame.enemies[0], first)
        game.hit(at: first.position)
        game.hit(enemyID: first.id)
        let hit = game.tick(now: 0)
        XCTAssertEqual(hit.enemies[0].hp, first.hp - 9)
        XCTAssertEqual(hit.enemies[0].maxHP, first.maxHP)
        XCTAssertEqual(hit.enemies[0].hurt, 1)
        XCTAssertEqual(hit.cues, [.enemyHit])
        XCTAssertTrue(game.tick(now: 0).cues.isEmpty)
    }

    func testWavesMustBeClearedBeforeBossAndOneTerminalEvent() {
        var game = VirusArcade(seed: 1)
        var previous = game.frame
        var events: [VirusArcade.Event] = []
        var cues = Set<VirusArcade.Cue>()
        var visitedWaves = Set<Int>()
        var foundDamagedEnemy = false, foundHostileShot = false, foundFriendlyShot = false
        var fullPreviousWave = false
        for i in 0...2500 {
            let frame = game.tick(now: Double(i) / 30)
            visitedWaves.insert(frame.wave)
            if let event = frame.event { events.append(event) }
            cues.formUnion(frame.cues)
            if frame.wave != previous.wave {
                XCTAssertTrue(fullPreviousWave)
                fullPreviousWave = false
            }
            if frame.phase == .wave {
                XCTAssertFalse(frame.enemies.contains { $0.kind == .boss })
                if frame.defeated == frame.enemyTotal {
                    XCTAssertTrue(frame.enemies.isEmpty)
                    fullPreviousWave = true
                }
            }
            if frame.event == .bossAppeared {
                XCTAssertEqual(frame.phase, .boss)
                XCTAssertEqual(frame.enemyTotal, 1)
                XCTAssertEqual(frame.enemies.map(\.kind), [.boss])
                XCTAssertGreaterThan(frame.enemies[0].radius, 11)
                XCTAssertGreaterThan(frame.enemies[0].maxHP, 26)
            }
            XCTAssertLessThanOrEqual(frame.enemies.count, VirusArcade.maximumEnemies)
            foundDamagedEnemy = foundDamagedEnemy || frame.enemies.contains { $0.hp < $0.maxHP && $0.hp > 0 }
            foundHostileShot = foundHostileShot || frame.shots.contains { $0.hostile }
            foundFriendlyShot = foundFriendlyShot || frame.shots.contains { !$0.hostile }
            previous = frame
            if frame.phase == .victory { break }
        }
        XCTAssertEqual(visitedWaves, [1, 2, 3])
        XCTAssertEqual(events, [.bossAppeared, .won])
        XCTAssertEqual(cues, [.fire, .enemyHit, .enemyDefeated, .heroHurt, .powerup, .boss, .victory])
        XCTAssertTrue(foundDamagedEnemy && foundFriendlyShot && foundHostileShot)
        XCTAssertEqual(previous.phase, .victory)
        XCTAssertGreaterThan(previous.playerHP, 0)
        XCTAssertEqual(previous.defeated, previous.enemyTotal)
        XCTAssertTrue(previous.shots.isEmpty)
        XCTAssertEqual(game.tick(now: 1000), game.frame)
    }

    func testClawdCanDieAndPlayerAssistanceCanChangeTheOutcome() {
        var game = VirusArcade(seed: 2)
        var assisted = game
        var deaths = 0
        for i in 0...1500 {
            let now = Double(i) / 30
            if game.tick(now: now).event == .died { deaths += 1 }
            let frame = assisted.tick(now: now)
            if let enemy = frame.enemies.first { assisted.hit(enemyID: enemy.id) }
        }
        XCTAssertEqual(deaths, 1)
        XCTAssertEqual(game.frame.phase, .dead)
        XCTAssertEqual(game.frame.playerHP, 0)
        XCTAssertTrue(game.frame.shots.isEmpty)
        XCTAssertTrue(game.frame.pickups.isEmpty)
        let tomb = game.frame
        if let enemy = tomb.enemies.first { game.hit(enemyID: enemy.id) }
        XCTAssertEqual(game.tick(now: 3600), tomb)
        XCTAssertEqual(assisted.frame.phase, .victory)
        XCTAssertGreaterThan(assisted.frame.playerHP, 0)
    }

    func testPickupsCanBeCollectedOnceAndApplyThreeDistinctEffects() {
        var collected = Set<VirusArcade.PickupKind>()
        var healedWounds = false
        for seed in UInt64(0)..<12 {
            var game = VirusArcade(seed: seed)
            for i in 0...1500 {
                let now = Double(i) / 30
                let before = game.tick(now: now)
                for item in before.pickups {
                    let hp = game.frame.playerHP
                    game.hit(at: item.position)
                    let after = game.tick(now: now)
                    XCTAssertTrue(after.cues.contains(.powerup))
                    XCTAssertFalse(after.pickups.contains { $0.id == item.id })
                    game.collect(pickupID: item.id)
                    XCTAssertTrue(game.tick(now: now).cues.isEmpty)
                    switch item.kind {
                    case .restore:
                        XCTAssertEqual(after.playerHP, min(hp + 25, 100))
                        healedWounds = healedWounds || hp < 100
                    case .shield:
                        XCTAssertEqual(after.shield, 4, accuracy: 0.00001)
                    case .rapidFire:
                        XCTAssertEqual(after.rapidFire, 5, accuracy: 0.00001)
                    }
                    collected.insert(item.kind)
                }
                if before.phase == .dead || before.phase == .victory { break }
            }
            if collected.count == 3 && healedWounds { break }
        }
        XCTAssertEqual(collected, [.shield, .restore, .rapidFire])
        XCTAssertTrue(healedWounds)
    }

    func testDriftingPickupsReachClawdAndBuffsChangeCombat() {
        var autoCollected = false, fastFollowUp = false, intercepted = false
        for seed in UInt64(0)..<24 {
            var game = VirusArcade(seed: seed)
            var previous = game.frame
            var lastShot = -10.0
            for i in 0...2500 {
                let frame = game.tick(now: Double(i) / 60)
                if frame.cues.contains(.fire) {
                    if frame.rapidFire > 0 && frame.time - lastShot < 0.35 { fastFollowUp = true }
                    lastShot = frame.time
                }
                if frame.cues.contains(.powerup) {
                    let nearby = previous.pickups.contains {
                        hypot($0.position.x - frame.hero.x, $0.position.y - frame.hero.y) <= $0.radius + 10
                    }
                    XCTAssertTrue(nearby)
                    autoCollected = true
                }
                if previous.shield > VirusArcade.step && frame.shield > 0,
                   previous.shots.contains(where: { shot in
                       shot.hostile && hypot(shot.position.x - frame.hero.x, shot.position.y - frame.hero.y) < 13
                           && !frame.shots.contains(where: { $0.id == shot.id })
                   }) {
                    XCTAssertFalse(frame.cues.contains(.heroHurt))
                    XCTAssertGreaterThanOrEqual(frame.playerHP, previous.playerHP)
                    intercepted = true
                }
                previous = frame
                if frame.phase == .dead || frame.phase == .victory { break }
            }
            if autoCollected && fastFollowUp && intercepted { break }
        }
        XCTAssertTrue(autoCollected)
        XCTAssertTrue(fastFollowUp)
        XCTAssertTrue(intercepted)
    }
}
