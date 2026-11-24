import XCTest
@testable import ClawdCompanion

final class CompanionApprovalTests: XCTestCase {
    func testWebActivityMapsToPropsAndLatestPropReturnsAfterApproval() async throws {
        try await MainActor.run {
            let suite = "ClawdProps." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = CompanionState(defaults: defaults)
            state.webEnabled = true
            let events: [(String, MascotPose)] = [("planning", .planning), ("reading", .reading),
                ("working", .typing), ("searching", .researching), ("executing", .executing), ("drawing", .drawing)]
            for (event, expected) in events {
                state.receive(.activity(event))
                XCTAssertEqual(state.presentedPose, expected)
            }
            state.receive(.approval(sourceID: "safari", waiting: true))
            state.receive(.activity("executing"))
            XCTAssertEqual(state.presentedPose, .awaitingApproval)
            state.receive(.approval(sourceID: "safari", waiting: false))
            XCTAssertEqual(state.presentedPose, .executing)
        }
    }

    func testIndependentBrowsersDoNotDismissEachOtherOrExtendAnExpiredWait() async throws {
        try await MainActor.run {
            let suite = "ClawdApprovals." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var time = 50.0
            let state = CompanionState(defaults: defaults, uptime: { time })
            state.webEnabled = true
            state.receive(.approval(sourceID: "safari", waiting: true))
            state.receive(.approval(sourceID: "chrome", waiting: true))
            state.receive(.approval(sourceID: "safari", waiting: false))
            state.receive(.activity("working"))
            XCTAssertEqual(state.presentedPose, .awaitingApproval)
            XCTAssertEqual(state.activitySource, "Claude.ai")
            time += 100
            state.receive(.approval(sourceID: "chrome", waiting: true))
            time += 110
            state.receive(.activity("thinking"))
            XCTAssertTrue(state.isAwaitingApproval)
            time += 41
            state.receive(.activity("working"))
            XCTAssertEqual(state.presentedPose, .typing)
            XCTAssertFalse(state.isAwaitingApproval)
        }
    }

    func testPreviewCanRollUpAndRealPromptTakesPriority() async throws {
        try await MainActor.run {
            let suite = "ClawdApprovalPreview." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = CompanionState(defaults: defaults)
            state.webEnabled = true
            state.toggleApprovalPreview()
            XCTAssertTrue(state.previewingApproval)
            state.toggleApprovalPreview()
            XCTAssertFalse(state.isAwaitingApproval)
            state.toggleApprovalPreview()
            state.receive(.approval(sourceID: "browser", waiting: true))
            state.toggleApprovalPreview()
            XCTAssertFalse(state.previewingApproval)
            XCTAssertTrue(state.isAwaitingApproval)
            state.webEnabled = false
            XCTAssertFalse(state.isAwaitingApproval)
        }
    }
}
