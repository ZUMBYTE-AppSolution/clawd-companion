import XCTest
@testable import ClawdCompanion

final class LimitReportTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 12345678)

    func testSessionResetDoesNotInvalidateWeekOrPretendQuotaIsFull() {
        let report = LimitReport(seen: date,
                                 session: LimitWindow(remaining: 4, reset: date.addingTimeInterval(60)),
                                 week: LimitWindow(remaining: 67, reset: date.addingTimeInterval(86400)))
        XCTAssertEqual(report.current(weekly: false, at: date)?.remaining, 4)
        XCTAssertNil(report.current(weekly: false, at: date.addingTimeInterval(60)))
        XCTAssertEqual(report.current(weekly: true, at: date.addingTimeInterval(61))?.remaining, 67)
    }

    func testUnknownResetExpiresAndDoesNotInventAnInstant() {
        let window = LimitWindow(remaining: 72, reset: nil, resetLabel: "Resets next Tuesday")
        let report = LimitReport(seen: date, session: nil, week: window)
        XCTAssertNil(report.current(weekly: false, at: date))
        XCTAssertEqual(report.current(weekly: true, at: date), window)
        XCTAssertNil(report.current(weekly: true, at: date.addingTimeInterval(900)))
    }
}
