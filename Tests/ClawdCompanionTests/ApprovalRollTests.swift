import XCTest
@testable import ClawdCompanion

final class ApprovalRollTests: XCTestCase {
    private let duration = MascotPose.approvalTransitionDuration

    func testWaitHoldsAcrossArbitrarilyManyPollsAndOnlyDismissesOnResolution() {
        var roll = ApprovalRoll()
        XCTAssertFalse(roll.set(waiting: false, at: 1, reduced: false))
        XCTAssertTrue(roll.set(waiting: true, at: 10, reduced: false))
        XCTAssertEqual(roll.pose, .approvalOpening)
        XCTAssertFalse(roll.set(waiting: true, at: 10.12, reduced: false))
        XCTAssertEqual(roll.started, 10)
        XCTAssertFalse(roll.advance(to: 10 + duration - 0.01, reduced: false))
        XCTAssertTrue(roll.advance(to: 10 + duration, reduced: false))
        XCTAssertEqual(roll.pose, .awaitingApproval)
        XCTAssertFalse(roll.advance(to: 3_600, reduced: false))
        XCTAssertTrue(roll.set(waiting: false, at: 3_601, reduced: false))
        XCTAssertEqual(roll.pose, .approvalClosing)
        XCTAssertFalse(roll.set(waiting: false, at: 3_601.1, reduced: false))
        XCTAssertTrue(roll.advance(to: 3_601 + duration, reduced: false))
        XCTAssertNil(roll.pose)
        XCTAssertNil(roll.started)
    }

    func testQuickResolutionAndNewWaitReverseFromSameHeight() throws {
        var roll = ApprovalRoll()
        roll.set(waiting: true, at: 0, reduced: false)
        roll.set(waiting: false, at: duration * 0.4, reduced: false)
        XCTAssertEqual(roll.pose, .approvalClosing)
        XCTAssertEqual(try XCTUnwrap(roll.started), -duration * 0.2, accuracy: 1e-8)
        roll.set(waiting: true, at: duration * 0.5, reduced: false)
        XCTAssertEqual(roll.pose, .approvalOpening)
        XCTAssertEqual(try XCTUnwrap(roll.started), duration * 0.2, accuracy: 1e-8)
        roll.advance(to: duration * 1.21, reduced: false)
        XCTAssertEqual(roll.pose, .awaitingApproval)
    }

    func testReducedMotionSettlesEvenDuringAnOpenRollAndAfterChangingThePreference() {
        var roll = ApprovalRoll()
        roll.set(waiting: true, at: 0, reduced: false)
        roll.advance(to: 0.08, reduced: true)
        XCTAssertEqual(roll.pose, .awaitingApproval)
        XCTAssertNil(roll.started)
        roll.set(waiting: false, at: 1, reduced: false)
        roll.advance(to: 1.12, reduced: true)
        XCTAssertNil(roll.pose)
        roll.set(waiting: true, at: 2, reduced: true)
        XCTAssertEqual(roll.pose, .awaitingApproval)
        roll.set(waiting: false, at: 2, reduced: true)
        XCTAssertNil(roll.pose)
    }
}
