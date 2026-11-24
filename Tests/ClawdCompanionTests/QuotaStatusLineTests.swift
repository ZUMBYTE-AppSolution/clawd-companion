import Foundation
import XCTest
@testable import ClawdCompanion

final class QuotaStatusLineTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_700_000_000)

    func testSubscriptionLimitsAreIndependentOfContextAndSpend() throws {
        let input = Data("""
            {"context_window":{"remaining_percentage":93},"rate_limits":{
             "five_hour":{"used_percentage":12.5,"resets_at":1700000100},
             "seven_day":{"used_percentage":100,"resets_at":1700005000},
             "spend_limit":{"used_percentage":4,"resets_at":1700007000}}}
            """.utf8)
        let snapshot = try XCTUnwrap(QuotaStatusLine.parse(input, at: observed))
        XCTAssertEqual(snapshot.observedAt, observed)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 87.5)
        XCTAssertEqual(snapshot.sevenDay?.remainingPercent, 0)
        XCTAssertNil(snapshot.valid(at: observed.addingTimeInterval(100))?.fiveHour)
        XCTAssertEqual(snapshot.valid(at: observed.addingTimeInterval(100))?.sevenDay?.remainingPercent, 0)
        XCTAssertNil(snapshot.valid(at: observed.addingTimeInterval(5000)))
    }

    func testMalformedWindowDoesNotHideValidSibling() throws {
        let input = Data("""
            {"rate_limits":{"five_hour":{"used_percentage":"90","resets_at":1700000300},
             "seven_day":{"used_percentage":0,"resets_at":1700006000}}}
            """.utf8)
        let snapshot = try XCTUnwrap(QuotaStatusLine.parse(input, at: observed))
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.sevenDay?.remainingPercent, 100)
    }

    func testUnknownAndExpiredValuesStayUnavailable() {
        let inputs = [
            #"{}"#,
            #"{"context_window":{"remaining_percentage":78}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":101,"resets_at":1700009000}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1699999999}}}"#,
            #"{"rate_limits":{"spend_limit":{"used_percentage":9,"resets_at":1700009000}}}"#
        ]
        for input in inputs {
            XCTAssertNil(QuotaStatusLine.parse(Data(input.utf8), at: observed))
        }
    }
}
