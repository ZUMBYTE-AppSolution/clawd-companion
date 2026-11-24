import XCTest
import CoreGraphics
@testable import ClawdCompanion

final class WindowSceneryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1200, height: 845)
    private let primaryTop: CGFloat = 900
    private let pet = CGSize(width: 100, height: 80)
    private let normal = CGRect(x: 300, y: 230, width: 500, height: 330)

    private func item(_ id: UInt32, _ bounds: CGRect, owner: Int32 = 42, layer: Int = 0,
                      visible: Bool = true, alpha: Double = 1, name: String = "Editor") -> [String: Any] {
        let quartz = CGRect(x: bounds.minX, y: primaryTop - bounds.maxY,
                            width: bounds.width, height: bounds.height)
        return [kCGWindowNumber as String: NSNumber(value: id),
                kCGWindowBounds as String: quartz.dictionaryRepresentation,
                kCGWindowOwnerPID as String: NSNumber(value: owner),
                kCGWindowOwnerName as String: name,
                kCGWindowLayer as String: NSNumber(value: layer),
                kCGWindowAlpha as String: NSNumber(value: alpha),
                kCGWindowIsOnscreen as String: NSNumber(value: visible)]
    }

    private func scan(_ entries: [[String: Any]], screens: [CGRect]? = nil) -> [SceneryWindow] {
        WindowScenery.candidates(in: entries, primaryTop: primaryTop, screens: screens ?? [screen],
                                 petSize: pet, ownPID: 150)
    }

    func testEmptyDesktopAndMinimizedOrSystemWindowsProvideNoTerrain() {
        XCTAssertTrue(scan([]).isEmpty)
        let entries = [item(1, screen), item(2, normal, visible: false), item(3, normal, layer: -1),
                       item(4, normal, name: "Dock"), item(5, normal, alpha: 0), item(6, normal, owner: 150)]
        XCTAssertTrue(scan(entries).isEmpty)
    }

    func testFocusingUsesTheFrontWindowOfThePIDOrAnExactAccessibilityMatch() throws {
        let first = CGRect(x: 170, y: 215, width: 270, height: 200)
        let other = first.offsetBy(dx: 595, dy: -45)
        let list = [item(90, CGRect(x: 7,y: 45,width: 66,height: 24)), item(10, first), item(11, other)]
        func scanFocused(_ focus: CGRect?) -> [CGWindowID] {
            WindowScenery.candidates(in: list, primaryTop: primaryTop, screens: [screen], petSize: pet,
                                     ownPID: 150, activePID: 42, focusedFrame: focus).filter(\.isActive).map(\.id)
        }
        XCTAssertEqual(scanFocused(nil), [10])
        XCTAssertEqual(scanFocused(other), [11])
        XCTAssertEqual(scanFocused(normal.offsetBy(dx: 50, dy: 0)), [])
    }

    func testAnAppMaximizedBelowTheMenuStillHasAReachableTitleGrip() throws {
        let full = CGRect(x: 0, y: 0, width: 1200, height: 900)
        func discover(_ rect: CGRect) -> [SceneryWindow] {
            WindowScenery.candidates(in: [item(7, rect)], primaryTop: primaryTop, screens: [screen],
                petSize: pet, ownPID: 150, activePID: 42, displayFrames: [full])
        }
        let maximized = try XCTUnwrap(discover(screen).first)
        XCTAssertTrue(maximized.isActive && maximized.leftInside && maximized.rightInside)
        XCTAssertFalse(maximized.roofClear)
        XCTAssertTrue(discover(full).isEmpty)
    }

    func testOcclusionUsesFrontToBackOrderAndTransparentPetDoesNotBlockItself() throws {
        let crossing = CGRect(x: 245, y: 360, width: 125, height: 90)
        let petOverlay = item(13, normal, owner: 150, layer: 3)
        let ownPanel = item(14, crossing, owner: 150)
        let back = item(4, normal)
        let transparent = item(16, normal, layer: 5, alpha: 0)
        var candidate = try XCTUnwrap(scan([petOverlay, transparent, ownPanel, back]).first { $0.id == 4 })
        XCTAssertFalse(candidate.leftClear)
        XCTAssertTrue(candidate.rightClear)
        XCTAssertTrue(candidate.roofClear)
        candidate = try XCTUnwrap(scan([back, ownPanel]).first)
        XCTAssertTrue(candidate.leftClear)
        XCTAssertEqual(candidate.frame, normal)
        XCTAssertFalse(candidate.leftInside)
    }

    func testRoofBlockedButExposedWallsRemainAndFullyHiddenWindowIsSkipped() throws {
        let menu = item(51, CGRect(x: 460, y: 550, width: 90, height: 130), layer: 24)
        let target = item(7, normal)
        let visible = try XCTUnwrap(scan([menu, target]).first)
        XCTAssertTrue(visible.leftClear && visible.rightClear)
        XCTAssertFalse(visible.roofClear)
        XCTAssertTrue(scan([item(52, normal.insetBy(dx: -30, dy: -30), layer: 24), target]).isEmpty)
    }

    func testSmallWindowOverOneUpperCornerLeavesTheOppositeRoofWalkable() throws {
        let document = item(7, normal)
        for left in [false, true] {
            // Geometry of the 66 × 20 pt floating strip observed on the live desktop.
            let x = left ? normal.minX + 6 : normal.maxX - 72
            let chip = item(9, CGRect(x: x, y: normal.maxY - 26, width: 66, height: 20))
            let window = try XCTUnwrap(scan([chip, document]).first { $0.id == 7 })
            XCTAssertFalse(window.roofClear)
            XCTAssertEqual(window.leftRoofClear, !left)
            XCTAssertEqual(window.rightRoofClear, left)
            XCTAssertEqual(window.leftClear, !left)
            XCTAssertEqual(window.rightClear, left)
        }
    }

    func testRoofChecksIncludeTheMiddleAndTheHeadroomBeyondTheLip() throws {
        let document = item(7, normal)
        let middle = item(9, CGRect(x: normal.midX - 3, y: normal.maxY, width: 6, height: 16))
        let blocked = try XCTUnwrap(scan([middle, document]).first { $0.id == 7 })
        XCTAssertTrue(blocked.leftClear && blocked.rightClear)
        XCTAssertFalse(blocked.leftRoofClear || blocked.rightRoofClear)

        let aboveGrip = item(10, CGRect(x: normal.minX - 40, y: normal.maxY + 25, width: 10, height: 12))
        let openRight = try XCTUnwrap(scan([aboveGrip, document]).first { $0.id == 7 })
        XCTAssertTrue(openRight.leftClear && openRight.rightClear)
        XCTAssertFalse(openRight.leftRoofClear)
        XCTAssertTrue(openRight.rightRoofClear)
    }

    func testFullDisplayStatusHUDAllowsRoutesWhileMenusAndFullSizeAppWindowsBlock() throws {
        let fullDisplay = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let hud = item(50, fullDisplay, layer: statusLayer)
        let document = item(7, normal)
        let clear = try XCTUnwrap(scan([hud, document]).first)
        XCTAssertTrue(clear.leftClear && clear.rightClear && clear.roofClear)

        let menu = item(51, CGRect(x: 450, y: 550, width: 90, height: 130), layer: statusLayer)
        let obscured = try XCTUnwrap(scan([hud, menu, document]).first)
        XCTAssertFalse(obscured.roofClear)
        XCTAssertTrue(obscured.leftClear && obscured.rightClear)
        for layer in [0, Int(CGWindowLevelForKey(.floatingWindow))] {
            XCTAssertTrue(scan([hud, item(52, fullDisplay, layer: layer), document]).isEmpty)
        }
    }

    func testStatusCanvasReachingPartwayOntoAnotherDisplayStillOccludesThatPart() throws {
        let next = screen.offsetBy(dx: screen.width, dy: 0)
        let hud = item(50, CGRect(x: 0, y: 0, width: 1400, height: 900),
                       layer: Int(CGWindowLevelForKey(.statusWindow)))
        let document = item(7, normal.offsetBy(dx: 1100, dy: 0))
        let window = try XCTUnwrap(scan([hud, document], screens: [screen, next]).first)
        XCTAssertEqual(window.screen, next)
        XCTAssertFalse(window.leftClear)
        XCTAssertTrue(window.rightClear)
    }

    func testNearlyMaximizedUsesInsideRimsWithNoFabricatedRoofAtMenuOrDisplaySeams() throws {
        let almostFull = CGRect(x: 6, y: 29, width: screen.width - 12, height: screen.height - 8)
        let wall = try XCTUnwrap(scan([item(8, almostFull)]).first)
        XCTAssertTrue(wall.leftInside && wall.rightInside)
        XCTAssertFalse(wall.roofClear)
        let leftDisplay = CGRect(x: -1100, y: 200, width: 1100, height: 700)
        let across = CGRect(x: -235, y: 320, width: 970, height: 280)
        let seam = try XCTUnwrap(scan([item(10, across)], screens: [screen, leftDisplay]).first)
        XCTAssertEqual(seam.screen, screen)
        XCTAssertFalse(seam.leftClear)
        XCTAssertTrue(seam.rightClear)
        XCTAssertFalse(seam.roofClear)
    }

    func testWindowMovedToVerticallyOffsetDisplayPreservesIdentity() throws {
        let secondary = CGRect(x: -1280, y: 150, width: 1280, height: 780)
        let first = try XCTUnwrap(scan([item(991, normal)]).first)
        let moved = CGRect(x: -1000, y: 360, width: 510, height: 330)
        let second = try XCTUnwrap(scan([item(991, moved)], screens: [screen, secondary]).first)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.pid, second.pid)
        XCTAssertEqual(second.frame, moved)
        XCTAssertEqual(second.screen, secondary)
        XCTAssertTrue(second.roofClear)
    }
}
