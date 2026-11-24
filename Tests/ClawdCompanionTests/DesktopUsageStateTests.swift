import Combine
import XCTest
@testable import ClawdCompanion

@MainActor final class DesktopUsageStateTests: XCTestCase {
    func testPartialDesktopReadingsRetainEachWindowsOwnFreshness() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let old = LimitReport(seen: start, session: LimitWindow(remaining: 12, reset: nil), week: nil)
        let later = start.addingTimeInterval(890)
        let week = LimitWindow(remaining: 79, reset: later.addingTimeInterval(86400))
        let next = try XCTUnwrap(LimitReport(seen: later, session: nil, week: week)
            .desktopObservation(preserving: old, now: later))
        XCTAssertEqual(next.session?.observedAt, start)
        XCTAssertEqual(next.week?.observedAt, later)
        XCTAssertEqual(next.current(weekly: false, at: later)?.remaining, 12)
        XCTAssertNil(next.current(weekly: false, at: later.addingTimeInterval(10)))
        XCTAssertEqual(next.current(weekly: true, at: later.addingTimeInterval(10))?.remaining, 79)
        let older = LimitReport(seen: start, session: nil, week: LimitWindow(remaining: 17, reset: nil))
        XCTAssertEqual(older.desktopObservation(preserving: next, now: later)?.week, next.week)
        XCTAssertNil(LimitReport(seen: later, session: nil, week: nil).desktopObservation(preserving: next, now: later))
    }

    func testCompactWeeklyMeterKeepsOnlyAnUnexpiredVerifiedReset() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = start.addingTimeInterval(500), later = start.addingTimeInterval(70)
        let observed = LimitReport(seen: start, session: LimitWindow(remaining: 96, reset: nil),
                                   week: LimitWindow(remaining: 62, reset: reset))
        let compact = LimitReport(seen: later, session: nil, week: LimitWindow(remaining: 60, reset: nil))
        let result = try XCTUnwrap(compact.desktopObservation(preserving: observed, now: later, fromCompactButton: true))
        XCTAssertEqual(result.week?.remaining, 60)
        XCTAssertEqual(result.week?.reset, reset)
        XCTAssertEqual(result.session?.observedAt, start)
        let nextWeek = LimitReport(seen: reset, session: nil, week: LimitWindow(remaining: 98, reset: nil))
        XCTAssertNil(nextWeek.desktopObservation(preserving: result, now: reset, fromCompactButton: true)?.week?.reset)
    }

    func testOptInSelectsDesktopAndCacheSurvivesDisableAndSourceChanges() async throws {
        let suite = "DesktopQuota-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let browser = LimitReport(seen: now, session: LimitWindow(remaining: 25, reset: nil), week: nil)
        let desktop = LimitReport(seen: now, session: LimitWindow(remaining: 41, reset: nil), week: nil)
        defaults.set(try JSONEncoder().encode(browser), forKey: "webReport")
        let state = CompanionState(defaults: defaults, readDesktopUsage: {
            XCTAssertFalse(Thread.isMainThread)
            return .usage(desktop)
        })
        XCTAssertFalse(state.desktopUsageEnabled)
        XCTAssertNil(state.desktopReport)
        let completion = expectation(description: "Desktop measurement")
        let reception = state.$desktopReport.compactMap { $0 }.sink { _ in completion.fulfill() }
        state.desktopUsageEnabled = true
        XCTAssertEqual(state.quotaSource, .desktop)
        await fulfillment(of: [completion], timeout: 3)
        reception.cancel()
        XCTAssertEqual(state.selectedReport?.session?.remaining, 41)
        XCTAssertEqual(state.webReport, browser)
        state.quotaSource = .browser
        let restoredWhileEnabled = CompanionState(defaults: defaults, readDesktopUsage: { .unavailable })
        XCTAssertTrue(restoredWhileEnabled.desktopUsageEnabled)
        XCTAssertEqual(restoredWhileEnabled.quotaSource, .browser)
        state.desktopUsageEnabled = false
        let restored = CompanionState(defaults: defaults, readDesktopUsage: { .unavailable })
        XCTAssertEqual(restored.desktopUsageStatus, .disabled)
        XCTAssertEqual(restored.quotaSource, .browser)
        XCTAssertEqual(restored.selectedReport?.session?.remaining, 25)
        restored.quotaSource = .desktop
        XCTAssertEqual(restored.selectedReport?.session?.remaining, 41)
        restored.quotaSource = .code
        XCTAssertNil(restored.selectedReport)
    }

    func testRefreshIsSingleFlightAndDropsLateResultAfterDisabling() async {
        final class Reader: @unchecked Sendable {
            let firstRead: XCTestExpectation, release = DispatchSemaphore(value: 0)
            private let lock = NSLock()
            private(set) var attempts = 0
            init(_ started: XCTestExpectation) { firstRead = started }
            func read() -> DesktopUsageSample {
                lock.lock()
                attempts += 1
                let index = attempts
                lock.unlock()
                if index == 1 {
                    firstRead.fulfill()
                    _ = release.wait(timeout: .now() + 3)
                }
                return .usage(LimitReport(seen: Date(), session: LimitWindow(remaining: index == 1 ? 1 : 72, reset: nil), week: nil))
            }
        }
        let suite = "DesktopQuota-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = Reader(expectation(description: "First scan started on worker"))
        let state = CompanionState(defaults: defaults, readDesktopUsage: { reader.read() })
        let fresh = expectation(description: "New authorized measurement")
        let observed = state.$desktopReport.compactMap { $0 }.sink { report in
            XCTAssertEqual(report.session?.remaining, 72)
            fresh.fulfill()
        }
        state.desktopUsageEnabled = true
        await fulfillment(of: [reader.firstRead], timeout: 3)
        state.refreshDesktopUsage()
        state.refreshDesktopUsage()
        state.desktopUsageEnabled = false
        XCTAssertEqual(state.desktopUsageStatus, .disabled)
        state.desktopUsageEnabled = true
        reader.release.signal()
        await fulfillment(of: [fresh], timeout: 3)
        observed.cancel()
        XCTAssertEqual(reader.attempts, 2)
        state.stop()
        state.refreshDesktopUsage()
        XCTAssertEqual(reader.attempts, 2)
    }

    func testUnavailableObservationLeavesIndependentPreviousReportAndTimestamp() async throws {
        let suite = "DesktopQuota-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Date().addingTimeInterval(-1000)
        let cache = LimitReport(seen: old, session: LimitWindow(remaining: 26, reset: nil), week: nil)
        defaults.set(true, forKey: "desktopUsageEnabled")
        defaults.set(QuotaSource.desktop.rawValue, forKey: "quotaSource")
        defaults.set(try JSONEncoder().encode(cache), forKey: "desktopUsageReport")
        let state = CompanionState(defaults: defaults, readDesktopUsage: { .notRunning })
        let status = expectation(description: "Desktop app unavailable")
        let observed = state.$desktopUsageStatus.filter { $0 == .notRunning }.sink { _ in status.fulfill() }
        state.refreshDesktopUsage()
        await fulfillment(of: [status], timeout: 3)
        observed.cancel()
        XCTAssertEqual(state.selectedReport, cache)
        XCTAssertNil(state.selectedReport?.current(weekly: false, at: Date()))
        XCTAssertNil(state.webReport)
    }
}
