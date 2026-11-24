import XCTest
@testable import ClawdCompanion

final class WindowPinTests: XCTestCase {
    func testInteriorPinUsesStableOffsetFromWindowTopLeft() {
        let window = CGRect(x: 200, y: 100, width: 720, height: 540)
        let sprite = CGRect(x: 320, y: 410, width: 100, height: 90)
        let offset = WindowPinOffset(pet: sprite, window: window)
        XCTAssertEqual(offset.origin(in: window, petSize: sprite.size), sprite.origin)

        // Moving to a left-hand display and resizing about the top-left corner.
        let moved = CGRect(x: -1200, y: 200, width: 800, height: 700)
        XCTAssertEqual(offset.origin(in: moved, petSize: sprite.size), CGPoint(x: -1080, y: 670))
    }

    func testRightAndBottomEdgePinTracksTheirResizeAndSpriteScaling() {
        let window = CGRect(x: 150, y: -120, width: 500, height: 380)
        let sprite = CGRect(x: 630, y: -140, width: 100, height: 80)
        let offset = WindowPinOffset(pet: sprite, window: window)
        let changed = CGRect(x: -400, y: 50, width: 950, height: 700)
        let size = CGSize(width: 130, height: 100)
        let restored = CGRect(origin: offset.origin(in: changed, petSize: size), size: size)
        XCTAssertEqual(restored.midX - changed.maxX, sprite.midX - window.maxX)
        XCTAssertEqual(restored.midY - changed.minY, sprite.midY - window.minY)
    }

    func testScreenConversionAcrossVerticallyArrangedDisplays() {
        let quartz = CGRect(x: -600, y: -780, width: 640, height: 480)
        let native = WindowPinTarget.quartzFlip(quartz, primaryTop: 900)
        XCTAssertEqual(native, CGRect(x: -600, y: 1200, width: 640, height: 480))
        XCTAssertEqual(WindowPinTarget.quartzFlip(native, primaryTop: 900), quartz)
    }
}
