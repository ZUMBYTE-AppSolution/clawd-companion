import AppKit
import XCTest
@testable import ClawdCompanion

final class ArcadeCoordinatorTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 3_000)

    func testExplicitRequestWaitsForGenuineIdleAndHigherPriorityWork() throws {
        let arcade = ArcadeCoordinator()
        arcade.configure(enabled: true, allowWhileActive: false)
        XCTAssertTrue(arcade.request())
        XCTAssertNil(arcade.tick(now: 20, date: date, available: true, idleSeconds: 0))
        XCTAssertEqual(arcade.status, .waitingForIdle)
        XCTAssertNil(arcade.tick(now: 110, date: date, available: false, idleSeconds: 90))
        XCTAssertNil(arcade.tick(now: 111, date: date, available: true, idleSeconds: 89.99))
        let frame = try XCTUnwrap(arcade.tick(now: 112, date: date, available: true, idleSeconds: 90))
        XCTAssertEqual(frame.playerHP, 100)
        XCTAssertEqual(arcade.status, .wave(1, hp: 100))
        XCTAssertFalse(arcade.request())
    }

    func testFirstAmbientRoundAndPausePreserveBattleWithoutCatchUp() throws {
        let arcade = ArcadeCoordinator(makeGame: { VirusArcade(seed: 42) })
        arcade.configure(enabled: true, allowWhileActive: false)
        XCTAssertNil(arcade.tick(now: 10, date: date, available: true, idleSeconds: .nan))
        XCTAssertNotNil(arcade.tick(now: 90, date: date, available: true, idleSeconds: 90))
        let last = try XCTUnwrap(arcade.tick(now: 90.1, date: date, available: true, idleSeconds: 90.1))
        XCTAssertGreaterThan(last.time, 0)
        XCTAssertNil(arcade.tick(now: 90.15, date: date, available: true, idleSeconds: 0.01))
        XCTAssertEqual(arcade.status, .paused(hp: last.playerHP))
        XCTAssertNil(arcade.tick(now: 179, date: date, available: true, idleSeconds: 89))
        XCTAssertNil(arcade.tick(now: 900, date: date, available: false, idleSeconds: 780))
        let resumed = try XCTUnwrap(arcade.tick(now: 950, date: date, available: true, idleSeconds: 830))
        XCTAssertEqual(last.time, resumed.time)
        XCTAssertEqual(last.enemies, resumed.enemies)
        XCTAssertEqual(last.shots, resumed.shots)
        XCTAssertEqual(last.hero, resumed.hero)
    }

    func testAllowWhileActiveStillRequiresSceneAvailabilityAndRespectsRevocation() throws {
        let arcade = ArcadeCoordinator(delay: { 73 })
        arcade.configure(enabled: true, allowWhileActive: true)
        XCTAssertNil(arcade.tick(now: 0, date: date, available: true, idleSeconds: 0))
        XCTAssertNil(arcade.tick(now: 72, date: date, available: true, idleSeconds: 0))
        XCTAssertNotNil(arcade.tick(now: 73, date: date, available: true, idleSeconds: 0))
        XCTAssertNil(arcade.tick(now: 74, date: date, available: false, idleSeconds: 0))
        XCTAssertEqual(arcade.status, .paused(hp: 100))
        XCTAssertNotNil(arcade.tick(now: 75, date: date, available: true, idleSeconds: 0))
        arcade.configure(enabled: true, allowWhileActive: false)
        XCTAssertNil(arcade.tick(now: 76, date: date, available: true, idleSeconds: 0))
        XCTAssertEqual(arcade.status, .paused(hp: 100))
        arcade.configure(enabled: false, allowWhileActive: false)
        XCTAssertEqual(arcade.status, .disabled)
        XCTAssertFalse(arcade.request())
        arcade.configure(enabled: true, allowWhileActive: true)
        XCTAssertTrue(arcade.request())
        XCTAssertNil(arcade.tick(now: 99, date: date, available: false, idleSeconds: 0))
        XCTAssertEqual(arcade.status, .waitingForCompanion)
        XCTAssertNotNil(arcade.tick(now: 100, date: date, available: true, idleSeconds: 0))
    }

    func testGraveSurvivesSettingsChangeAndRelaunchAndExpiresWhileHidden() throws {
        let first = ArcadeCoordinator()
        first.configure(enabled: true, allowWhileActive: true)
        var deadline: Date?
        first.onGraveChanged = { deadline = $0 }
        first.registerDeath(at: date)
        XCTAssertEqual(deadline, date.addingTimeInterval(300))
        first.configure(enabled: false, allowWhileActive: false)
        XCTAssertEqual(first.status, .grave(until: date.addingTimeInterval(300)))
        let restored = ArcadeCoordinator(delay: { 100 })
        restored.restoreGrave(until: deadline)
        restored.configure(enabled: true, allowWhileActive: true)
        var cleared = 0
        restored.onGraveChanged = { if $0 == nil { cleared += 1 } }
        XCTAssertFalse(restored.request())
        _ = restored.tick(now: 8_000, date: date.addingTimeInterval(299.99), available: false, idleSeconds: 0)
        XCTAssertEqual(restored.status, .grave(until: date.addingTimeInterval(300)))
        _ = restored.tick(now: 8_001, date: date.addingTimeInterval(300), available: false, idleSeconds: 0)
        XCTAssertEqual(restored.status, .reviving)
        _ = restored.tick(now: 8_001 + MascotPose.revivalDuration, date: date.addingTimeInterval(302), available: false, idleSeconds: 0)
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(restored.status, .ready)
        XCTAssertTrue(restored.request())
        let fresh = try XCTUnwrap(restored.tick(now: 9000, date: date.addingTimeInterval(400), available: true, idleSeconds: 0))
        XCTAssertEqual(fresh.playerHP, 100)
    }

    func testDesktopControllerYieldsMusicAndSpriteToClaude() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            try XCTSkipIf(NSScreen.screens.isEmpty || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                          "This integration check needs a display with animation enabled.")
            let overlay = OverlayController(onOpenPanel: {})
            var status: ArcadeStatus?
            var pose: MascotPose?
            var music: [ArcadeMusicPhase?] = []
            overlay.onArcadeStatus = { status = $0 }
            overlay.onDisplayPose = { pose = $0 }
            overlay.onArcadeMusic = { music.append($0) }
            overlay.configurePlay(roaming: false, chase: false, bow: false)
            overlay.configure(visible: true, followsWindows: false, reducedMotion: false)
            defer { overlay.configure(visible: false, followsWindows: false, reducedMotion: false) }
            overlay.configureArcade(enabled: true, allowWhileActive: true)
            XCTAssertTrue(overlay.requestArcade())
            XCTAssertEqual(status, .wave(1, hp: 100))
            XCTAssertEqual(music, [.wave])
            XCTAssertEqual(pose, .virusFight)
            overlay.setPose(.planning)
            XCTAssertEqual(status, .paused(hp: 100))
            XCTAssertEqual(music, [.wave, nil])
            XCTAssertEqual(pose, .planning)
            overlay.setApprovalWaiting(true)
            overlay.setPose(.idle)
            XCTAssertEqual(status, .paused(hp: 100))
            overlay.configure(visible: false, followsWindows: false, reducedMotion: false)
        }
    }

    func testHiddenDesktopControllerRestoresGraveAheadOfApprovalAndAgentSignals() async {
        await MainActor.run {
            _ = NSApplication.shared
            let overlay = OverlayController(onOpenPanel: {})
            var status: ArcadeStatus?
            var pose: MascotPose?
            overlay.onArcadeStatus = { status = $0 }
            overlay.onDisplayPose = { pose = $0 }
            overlay.configureArcade(enabled: false, allowWhileActive: false)
            overlay.setApprovalWaiting(true)
            let until = Date().addingTimeInterval(240)
            overlay.restoreArcadeGrave(until: until)
            overlay.setAgentCount(3)
            XCTAssertEqual(status, .grave(until: until))
            XCTAssertEqual(pose, .grave)
            XCTAssertFalse(overlay.requestArcade())
            overlay.restoreArcadeGrave(until: Date().addingTimeInterval(-2))
            XCTAssertEqual(status, .reviving)
            XCTAssertEqual(pose, .reviving)
        }
    }

    func testHeroAnchorForBothFacingsAndConstrainedDisplay() {
        let area = CGRect(x: -1400, y: -130, width: 1300, height: 700)
        let hero = CGPoint(x: 43, y: 77)
        for x in [-1070, -560] {
            let pet = CGRect(x: x, y: 90, width: 105, height: 90)
            let layout = VirusArenaProjection(fitting: area, pet: pet, hero: hero)
            XCTAssertEqual(layout.mirrored, pet.midX > area.midX)
            let point = layout.screenRect(CGRect(origin: hero, size: .zero)).origin
            XCTAssertEqual(point.x, pet.midX, accuracy: 1e-8)
            XCTAssertEqual(point.y, pet.midY, accuracy: 1e-8)
            XCTAssertTrue(area.contains(layout.rect))
        }
        let tiny = CGRect(x: -74, y: 120, width: 150, height: 140)
        let largePet = CGRect(x: -140, y: 0, width: 200, height: 180)
        let fitted = VirusArenaProjection(fitting: tiny, pet: largePet, hero: hero)
        XCTAssertTrue(tiny.contains(fitted.rect))
        XCTAssertEqual(fitted.rect.width / fitted.rect.height, 300.0 / 160.0, accuracy: 1e-8)
    }
}
