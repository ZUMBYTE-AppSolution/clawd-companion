import XCTest
@testable import ClawdCompanion

final class SoundPreferencesTests: XCTestCase {
    func testVolumeAndIndividualMutesSurviveMasterSwitchAndRestart() async throws {
        try await MainActor.run {
            let suite = "ClawdSounds." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = CompanionState(defaults: defaults)
            XCTAssertEqual(first.soundVolume, 0.28)
            first.setSound(.steps, enabled: false)
            first.setSound(.letters, enabled: false)
            first.soundVolume = 0.19
            first.soundEnabled = false
            let reopened = CompanionState(defaults: defaults)
            XCTAssertFalse(reopened.soundEnabled)
            XCTAssertEqual(reopened.soundVolume, 0.19)
            reopened.soundEnabled = true
            for kind in PetSound.allCases {
                XCTAssertEqual(reopened.isSoundEnabled(kind), kind != .steps && kind != .letters)
            }
            reopened.setSound(.steps, enabled: true)
            reopened.soundVolume = 0
            let last = CompanionState(defaults: defaults)
            XCTAssertTrue(last.isSoundEnabled(.steps))
            XCTAssertFalse(last.isSoundEnabled(.letters))
            XCTAssertEqual(last.soundVolume, 0)
        }
    }
}
