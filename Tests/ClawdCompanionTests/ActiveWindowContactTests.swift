import XCTest
@testable import ClawdCompanion

final class ActiveWindowContactTests: XCTestCase {
    private let display = CGRect(x: -1280, y: 180, width: 1280, height: 780)
    private let frame = CGRect(x: -980, y: 280, width: 500, height: 380)
    private let size = CGSize(width: 105, height: 90)

    private func contact(_ frame: CGRect, left: Bool = true, roofLeft: Bool = true,
                         roofRight: Bool = true, inset: Bool = false) -> ActiveWindowContact {
        let target = SceneryWindow(id: 21, pid: 38, frame: frame, screen: display,
                                   leftClear: left, rightClear: true, roofClear: roofLeft && roofRight,
                                   leftInside: inset, rightInside: inset, leftRoofClear: roofLeft, rightRoofClear: roofRight,
                                   isActive: true)
        return ActiveWindowContact(window: target, size: size)
    }

    func testSittingAndKeyboardContactActualTitleEdgeBeyondBothClimbingWalls() {
        let ledge = contact(frame)
        for side in [ActiveWindowContact.Side.left, .right] {
            for (pose,row) in [(MascotPose.typing,42.0),(.perched,38.0),(.perchThinking,38.0),
                               (.planning,44.0),(.executing,44.0),(.drawing,44.0),(.reading,43.0),(.researching,43.0)] {
                let p = ledge.rest(side, pose: pose)
                XCTAssertEqual(p.y + WindowLedge.offset(forRow: row, pet: size), frame.maxY, accuracy: 0.001)
                XCTAssertGreaterThan(p.x, frame.minX)
                XCTAssertLessThan(p.x+size.width,frame.maxX)
                XCTAssertTrue(display.contains(CGRect(origin:p,size: size)))
            }
        }
    }

    func testAcquiresTheAvailableSideAndFollowsWindowTranslationAtEachContact() {
        let ledge = contact(frame, left: false, roofLeft: false)
        XCTAssertEqual(ledge.side(near: frame.minX),.right)
        let dx: CGFloat = 65, dy: CGFloat = -54
        let moved = contact(frame.offsetBy(dx:dx,dy:dy),left: false,roofLeft: false)
        let ground = ledge.wall(.right, upper: false), high = ledge.wall(.right, upper: true)
        let seat = ledge.rest(.right, pose: .typing)
        for (before,after) in [(ground,moved.wall(.right,upper: false)),(high,moved.wall(.right,upper: true)),
                               (seat,moved.rest(.right,pose: .typing))] {
            XCTAssertEqual(after.x - before.x,dx,accuracy: 0.001)
            XCTAssertEqual(after.y - before.y,dy,accuracy: 0.001)
        }
    }

    func testVeryHighWindowHasAnInsideGripAndNeverInventsASeatAboveTheScreen() {
        let maximized = display.insetBy(dx:1,dy:0)
        let ledge = contact(maximized, roofLeft: false, roofRight: false, inset: true)
        XCTAssertFalse(ledge.canStand(.right))
        XCTAssertFalse(ledge.looksLeft(on: .right))
        XCTAssertEqual(ledge.rest(.right,pose: .typing),ledge.wall(.right,upper: true))
        let top = ledge.wall(.right,upper: true)
        let highestVisibleClaw = top.y + WindowLedge.offset(forRow: 8, pet: size)
        XCTAssertLessThanOrEqual(highestVisibleClaw, display.maxY)
        XCTAssertGreaterThanOrEqual(highestVisibleClaw, display.maxY - 24)
        XCTAssertEqual(top.x+size.width*51/56,maximized.maxX,accuracy: 0.001)
        let titleDepth = maximized.maxY - (top.y + WindowLedge.offset(forRow: 14,pet: size))
        XCTAssertLessThanOrEqual(titleDepth, 28)
    }
}
