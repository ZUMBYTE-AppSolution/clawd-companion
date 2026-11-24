import XCTest
@testable import ClawdCompanion

@MainActor final class ManualArenaIntegrationTests: XCTestCase {
    func testOfflinePanelStartsWhileAmbientIsDisabledAndPausesOnTabChange() {
        let suite = "ManualPanel-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "arcadeEnabled")
        defaults.set(false, forKey: "arcadeWhileActive")
        defaults.set(false, forKey: "soundEnabled")
        let state = CompanionState(defaults: defaults)
        XCTAssertNil(state.arenaAccount.username)
        XCTAssertTrue(state.canStartManualArena)
        state.page = .highscores
        state.startManualArena()
        XCTAssertTrue(state.manualArena.playing)
        XCTAssertTrue(state.panelArenaReserved)
        XCTAssertFalse(state.canStartRankedArena)
        XCTAssertFalse(state.canRequestArcade)
        state.page = .connections
        XCTAssertTrue(state.manualArena.paused)
        XCTAssertFalse(state.canStartRankedArena)
        state.manualArena.end()
        XCTAssertFalse(state.panelArenaReserved)
        XCTAssertTrue(state.canStartRankedArena)
        XCTAssertEqual(state.arenaTotals.rounds, 0)
    }

    func testNaturalManualDeathCreatesOneSharedFiveMinuteGraveWithoutFreePoints() throws {
        let suite = "ManualGrave-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "soundEnabled")
        let arena = ManualArena(makeGame: { VirusArcade(seed: 2) })
        let state = CompanionState(defaults: defaults, manualArena: arena, uptime: { 0 })
        state.startManualArena()
        let started = Date()
        for i in 1...10_800 where arena.playing { arena.tick(now: Double(i) / 60) }
        guard case .grave(let until) = state.arcadeStatus else { return XCTFail("Expected the desktop pet’s shared grave") }
        XCTAssertEqual(until.timeIntervalSince(started), 300, accuracy: 1)
        XCTAssertEqual(state.arenaTotals.rounds, 0)
        XCTAssertFalse(state.canStartRankedArena)
        XCTAssertFalse(state.canStartManualArena)
        state.startManualArena()
        arena.tick(now: 200)
        XCTAssertFalse(arena.playing)
        XCTAssertEqual(state.arcadeStatus, .grave(until: until))
        let reloaded = CompanionState(defaults: defaults)
        XCTAssertEqual(reloaded.arcadeStatus, .grave(until: until))
    }

    func testAmbientRunCanBeAdoptedExactlyOnceAndRetainsItsSimulation() throws {
        let ambient = ArcadeCoordinator(delay: { 60 }, makeGame: { VirusArcade(seed: 2) })
        ambient.configure(enabled: true, allowWhileActive: true)
        XCTAssertTrue(ambient.request())
        _ = ambient.tick(now: 0, date: Date(), available: true, idleSeconds: 0)
        let initial = try XCTUnwrap(ambient.tick(now: 0.25, date: Date(), available: true, idleSeconds: 0))
        let (id, game) = try XCTUnwrap(ambient.takeForPanel())
        XCTAssertFalse(ambient.hasRound)
        XCTAssertNil(ambient.takeForPanel())
        let local = ManualArena()
        local.start(now: 50, existing: (id, game))
        XCTAssertEqual(local.frame?.enemies, initial.enemies)
        XCTAssertEqual(local.frame?.time, initial.time)
        _ = ambient.tick(now: 100, date: Date(), available: false, idleSeconds: 900)
        XCTAssertFalse(ambient.hasRound)
        XCTAssertTrue(local.playing)
    }
}
