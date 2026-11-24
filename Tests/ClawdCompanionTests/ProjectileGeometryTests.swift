import AppKit
import XCTest
@testable import ClawdCompanion

final class ProjectileGeometryTests: XCTestCase {
    private func touches(_ word: String, letter: Bool = true, scale: CGFloat = 1,
                         from start: CGPoint, to end: CGPoint) -> Bool {
        ProjectileGeometry.touches(word: word, letter: letter, scale: scale, from: .zero, to: .zero,
                                   mouseFrom: start, mouseTo: end)
    }

    func testTransparentHolesPaddingAndTrailsAreHarmless() {
        for point in [CGPoint.zero, CGPoint(x: 0, y: 3), CGPoint(x: -10, y: 0), CGPoint(x: 4.5, y: 7)] {
            XCTAssertFalse(touches("O", from: point, to: point))
        }
        XCTAssertFalse(touches("O", from: CGPoint(x: -2, y: -2), to: CGPoint(x: 2, y: 2)))
        XCTAssertTrue(touches("O", from: CGPoint(x: 3, y: -2), to: CGPoint(x: 3, y: 2)))
        XCTAssertTrue(touches("A", from: .zero, to: .zero))
        XCTAssertFalse(touches("ZZ", from: .zero, to: .zero))
        XCTAssertFalse(touches("A", scale: 0, from: .zero, to: .zero))
    }

    func testFastSweepsUseRelativeCoordinatesAndScale() {
        XCTAssertTrue(ProjectileGeometry.touches(word: "I", letter: true, scale: 1.65,
            from: CGPoint(x: 23.3, y: -90.8), to: CGPoint(x: 203.3, y: -30.8),
            mouseFrom: CGPoint(x: 178.3, y: -90.8), mouseTo: CGPoint(x: 38.3, y: -30.8)))
        XCTAssertFalse(ProjectileGeometry.touches(word: "I", letter: true, scale: 1.65,
            from: CGPoint(x: 23.3, y: -90.8), to: CGPoint(x: 203.3, y: -30.8),
            mouseFrom: CGPoint(x: 30.3, y: -90.8), mouseTo: CGPoint(x: 210.3, y: -30.8)))
        // Passing through long empty columns is safe even inside the letter's outer extents.
        XCTAssertFalse(touches("L", from: CGPoint(x: 3, y: 7), to: CGPoint(x: 3, y: -3)))
        XCTAssertTrue(touches("L", from: CGPoint(x: 3, y: 7), to: CGPoint(x: 3, y: -15)))
    }

    func testOnlyVisibleBodyOfRoundedCodeTagCounts() {
        let rect = ProjectileGeometry.tagBounds(for: "fn()")
        let corner = CGPoint(x: rect.maxX - 0.3, y: rect.maxY - 0.3)
        XCTAssertFalse(touches("fn()", letter: false, from: corner, to: corner))
        XCTAssertFalse(touches("fn()", letter: false, from: CGPoint(x: rect.maxX + 1, y: -12), to: CGPoint(x: rect.maxX + 1, y: 12)))
        XCTAssertTrue(touches("fn()", letter: false, from: CGPoint(x: rect.maxX - 1, y: 0), to: CGPoint(x: rect.maxX - 1, y: 0)))
        XCTAssertTrue(touches("fn()", letter: false, from: CGPoint(x: rect.maxX + 4, y: rect.maxY-2), to: CGPoint(x: rect.maxX - 4, y: rect.maxY-2)))
    }

    func testOnscreenGlyphInkMatchesHotspotMaskAcrossAlphabet() async throws {
        try await MainActor.run {
            let view = CodeSparkView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            // Two physical pixels per point, like a Retina screen.
            let size = 64, colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            for symbol in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
                let word = String(symbol)
                let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: size*4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.scaleBy(x: 2, y: 2)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                view.effect = CodeSpark(point: .zero, direction: CGVector(dx: 1, dy: 0), text: word, style: .letter, progress: 0, scale: 1)
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
                let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                for x in 20..<44 {
                    for y in 16..<48 {
                        let relative = CGPoint(x: (CGFloat(x) + 0.5) / 2 - 16, y: (CGFloat(y) + 0.5) / 2 - 16)
                        let painted = bytes[((size-1-y) * size + x) * 4 + 3] > 0
                        XCTAssertEqual(touches(word, from: relative, to: relative), painted, "\(word) at \(relative)")
                    }
                }
            }
        }
    }
}
