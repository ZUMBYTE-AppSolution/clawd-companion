import XCTest
@testable import ClawdCompanion

final class PlayScoreTests: XCTestCase {
    func testHitsAndDodgesPersistSeparatelyAcrossLaunches() async throws {
        try await MainActor.run {
            let name = "Clawd.ScoreFixture." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let game = CompanionState(defaults: defaults)
            XCTAssertEqual(game.playScore, PlayScore())
            game.recordRound(hit: false)
            game.recordRound(hit: true)
            game.recordRound(hit: false)
            let reopened = CompanionState(defaults: defaults)
            XCTAssertEqual(reopened.playScore.hits, 1)
            XCTAssertEqual(reopened.playScore.dodges, 2)
        }
    }
}
