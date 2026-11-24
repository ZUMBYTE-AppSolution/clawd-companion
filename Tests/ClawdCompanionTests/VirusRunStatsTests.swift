import CoreGraphics
import XCTest
@testable import ClawdCompanion

final class VirusRunStatsTests: XCTestCase {
    func testAutonomousVictoryAndDeathHaveZeroPersonalScore() {
        for (seed, victory) in [(UInt64(1), true), (UInt64(2), false)] {
            var game = VirusArcade(seed: seed)
            for tick in 0...2500 { _ = game.tick(now: Double(tick) / 30) }
            let stats = game.stats
            XCTAssertEqual(stats.victories, victory ? 1 : 0)
            XCTAssertEqual(stats.deaths, victory ? 0 : 1)
            XCTAssertEqual(stats.bossDefeated, victory)
            XCTAssertGreaterThan(stats.kills, 0)
            XCTAssertEqual([stats.score, stats.assists, stats.manualPickups, stats.personalKills,
                            stats.lastHits, stats.personalDeaths, stats.personalVictories], [0, 0, 0, 0, 0, 0, 0])
            XCTAssertFalse(stats.engaged)
            XCTAssertFalse(stats.personalBoss)
            XCTAssertFalse(stats.bossLastHit)
            XCTAssertEqual(game.tick(now: 999).stats, stats)
        }
    }

    func testMissCooldownAndOverkillCannotInflateDamage() throws {
        var game = VirusArcade(seed: 6)
        let first = try XCTUnwrap(game.frame.enemies.first)
        let center = first.position
        let hole = try XCTUnwrap((-10...10).flatMap { dx in
            (-10...10).map { dy in CGPoint(x: center.x + CGFloat(dx)/2, y: center.y + CGFloat(dy)/2) }
        }.first { point in
            hypot(point.x-center.x, point.y-center.y) <= first.radius
            && VirusArenaPixels.target(at: point, in: game.frame) == nil
        })
        game.hit(at: hole)
        game.hit(enemyID: -1)
        XCTAssertEqual(game.stats.score, 0)
        for tick in 0...4 {
            _ = game.tick(now: Double(tick)/5)
            game.hit(enemyID: first.id)
            game.hit(enemyID: first.id)
        }
        XCTAssertEqual(game.stats.manualDamage, first.maxHP)
        XCTAssertEqual(game.stats.assists, (first.maxHP + 8)/9)
        XCTAssertEqual(game.stats.lastHits, 1)
        XCTAssertEqual(game.stats.personalKills, 1)
        XCTAssertEqual(game.stats.killBonus, 10)
        XCTAssertEqual(game.stats.score, first.maxHP + 10)
    }

    func testAssistedKillOnlyCreditsItsOwnFractionAndNoAutonomousBossBonus() throws {
        var game = VirusArcade(seed: 1)
        let first = try XCTUnwrap(game.frame.enemies.first)
        game.hit(at: first.position)
        for tick in 0...2500 { _ = game.tick(now: Double(tick)/30) }
        let stats = game.stats
        XCTAssertEqual(stats.manualDamage, 9)
        XCTAssertEqual(stats.kills >= 1, true)
        XCTAssertEqual(stats.personalKills, 1)
        XCTAssertEqual(stats.lastHits, 0)
        XCTAssertEqual(stats.killBonus, 90/first.maxHP)
        XCTAssertEqual(stats.score, 9+90/first.maxHP)
        XCTAssertFalse(stats.personalBoss)
        XCTAssertEqual(stats.personalDeaths+stats.personalVictories, 1)
    }

    func testManualPowerupsOnlyCreditActualBenefitOnce() {
        var fullHeals = 0, effectivePickups = 0
        for seed in UInt64(0)..<10 {
            var game = VirusArcade(seed: seed)
            for tick in 0...1500 {
                let frame = game.tick(now: Double(tick)/30)
                for item in frame.pickups {
                    let before = game.frame
                    let useful: Bool
                    switch item.kind {
                    case .restore: useful = before.playerHP < 100
                    case .shield: useful = before.shield < 4-1e-9
                    case .rapidFire: useful = before.rapidFire < 5-1e-9
                    }
                    game.collect(pickupID: item.id)
                    game.collect(pickupID: item.id)
                    XCTAssertEqual(game.stats.manualPickups-before.stats.manualPickups, useful ? 1 : 0)
                    if useful { effectivePickups += 1 } else if item.kind == .restore { fullHeals += 1 }
                }
            }
            XCTAssertEqual(game.stats.score, 5*game.stats.manualPickups)
        }
        XCTAssertGreaterThan(effectivePickups, 0)
        XCTAssertGreaterThan(fullHeals, 0)
    }

    func testBossBonusIsBasedOnActualDamageToTheBoss() throws {
        var game = VirusArcade(seed: 2)
        var bossMaxHP = 0, damageBeforeBoss = 0, bonusBeforeBoss = 0
        var observedManualBossFinish = false
        for tick in 0...2000 {
            let frame = game.tick(now: Double(tick)/30)
            if let enemy = frame.enemies.first {
                if enemy.kind == .boss && bossMaxHP == 0 {
                    bossMaxHP = enemy.maxHP
                    damageBeforeBoss = game.stats.manualDamage
                    bonusBeforeBoss = game.stats.killBonus
                }
                game.hit(enemyID: enemy.id)
                if enemy.kind == .boss && game.frame.phase == .victory { observedManualBossFinish = true }
            }
            if frame.phase == .victory { break }
        }
        XCTAssertGreaterThan(bossMaxHP, 0)
        XCTAssertTrue(game.stats.personalBoss)
        XCTAssertEqual(game.stats.bossLastHit, observedManualBossFinish)
        XCTAssertEqual(game.stats.personalVictories, 1)
        let bossDamage = game.stats.manualDamage-damageBeforeBoss
        XCTAssertEqual(game.stats.killBonus-bonusBeforeBoss, 50*bossDamage/max(1, bossMaxHP))
    }
}
