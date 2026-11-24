import XCTest
@testable import ClawdCompanion

final class ArenaTotalsTests: XCTestCase {
    func testOnlyCompletedParticipatingRoundsCountAndRetriesAreIdempotent() throws {
        var totals = ArenaTotals()
        let id = UUID()
        var autoplay = VirusArcade.RunStats()
        autoplay.kills = 8
        autoplay.victories = 1
        XCTAssertFalse(totals.record(id: id, stats: autoplay))
        var assisted = VirusArcade.RunStats()
        assisted.manualDamage = 7
        assisted.personalKills = 2
        assisted.lastHits = 1
        assisted.kills = 3
        XCTAssertFalse(totals.record(id: id, stats: assisted))
        assisted.deaths = 1
        XCTAssertTrue(totals.record(id: id, stats: assisted))
        var restored = try JSONDecoder().decode(ArenaTotals.self, from: JSONEncoder().encode(totals))
        XCTAssertFalse(restored.record(id: id, stats: assisted))
        XCTAssertEqual(restored.points, 7)
        XCTAssertEqual(restored.kills, 1)
        XCTAssertEqual(restored.deaths, 1)
        XCTAssertEqual(restored.rounds, 1)
        XCTAssertEqual(restored.wins, 0)
    }
}
