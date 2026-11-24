import XCTest
@testable import ClawdCompanion

final class ArcadePreferencesTests: XCTestCase {
    func testOnlyExplicitOptInEnablesPlayWhileActiveAcrossLaunches() async throws {
        try await MainActor.run {
            let suite = "ClawdArcade." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = CompanionState(defaults: defaults)
            XCTAssertTrue(state.arcadeEnabled)
            XCTAssertFalse(state.arcadeWhileActive)
            state.requestArcade()
            state.arcadeEnabled = false
            state.arcadeEnabled = true
            XCTAssertFalse(CompanionState(defaults: defaults).arcadeWhileActive)
            state.arcadeWhileActive = true
            XCTAssertTrue(CompanionState(defaults: defaults).arcadeWhileActive)
            state.arcadeEnabled = false
            XCTAssertEqual(CompanionState(defaults: defaults).arcadeStatus, .disabled)
            state.arcadeWhileActive = false
            XCTAssertFalse(CompanionState(defaults: defaults).arcadeWhileActive)
        }
    }

    func testGraveHasPriorityAndKeepsItsDeadlineAcrossSettingsAndLaunches() async throws {
        try await MainActor.run {
            let suite = "ClawdGrave." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let until = Date().addingTimeInterval(292)
            defaults.set(until, forKey: "arcadeGraveUntil")
            defaults.set("de", forKey: "language")
            let state = CompanionState(defaults: defaults)
            XCTAssertEqual(state.arcadeStatus, .grave(until: until))
            XCTAssertEqual(state.presentedPose, .grave)
            XCTAssertTrue(state.presentedLabel.hasPrefix("Auferstehung in 4:"))
            state.toggleApprovalPreview()
            state.play(.happy)
            state.arcadeEnabled = false
            state.arcadeEnabled = true
            state.requestArcade()
            XCTAssertFalse(state.previewingApproval)
            XCTAssertFalse(state.canRequestArcade)
            XCTAssertEqual(CompanionState(defaults: defaults).arcadeStatus, .grave(until: until))
        }
    }
}
