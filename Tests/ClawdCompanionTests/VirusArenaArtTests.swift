import AppKit
import XCTest
@testable import ClawdCompanion

final class VirusArenaArtTests: XCTestCase {
    private let center = CGPoint(x: 150, y: 80)

    private func frame(_ kind: VirusArcade.Kind, time: Double = 0, pickup: VirusArcade.PickupKind? = nil,
                       hp: Int = 7, shield: Double = 0, rapid: Double = 0) -> VirusArcade.Frame {
        let enemy = VirusArcade.Enemy(id: 2, kind: kind, position: center,
                                      radius: 16.5, hp: hp, maxHP: 10, hurt: 0)
        let pickups = pickup.map { [VirusArcade.Pickup(id: 7, kind: $0, position: center, radius: 8)] } ?? []
        return VirusArcade.Frame(phase: kind == .boss ? .boss : .wave, wave: 1, playerHP: 95,
                                 hero: CGPoint(x: 43, y: 80), enemies: [enemy], shots: [], time: time,
                                 heroHurt: 0, heroFiring: true, event: nil, cues: [], pickups: pickups,
                                 shield: shield, rapidFire: rapid, enemyTotal: 2, defeated: 0)
    }
    private struct Raster {
        let data: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let i = (300 * (159-y) + x) * 4
            return data[i..<(i+4)]
        }
        func region(_ xr: Range<Int>, _ yr: Range<Int>) -> [UInt8] {
            yr.flatMap { y in xr.flatMap { x in pixel(x, y) } }
        }
    }
    private func raster(_ frame: VirusArcade.Frame, mirrored: Bool = false) throws -> Raster {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 300, height: 160, bitsPerComponent: 8,
                                             bytesPerRow: 300 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                 CGBitmapInfo.byteOrder32Big.rawValue))
        VirusArenaPixels.draw(frame, in: bitmap, mirrored: mirrored)
        let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        return Raster(data: Array(UnsafeBufferPointer(start: pixels, count: 300*160*4)))
    }

    func testEnemiesHaveDistinctSpritesAndAnimateAtActualOutputSize() throws {
        var images: Set<Data> = []
        for kind in VirusArcade.Kind.allCases {
            let idle = try raster(frame(kind)).region(128..<172, 62..<99)
            let moving = try raster(frame(kind, time: 0.4)).region(128..<172, 62..<99)
            XCTAssertNotEqual(idle, moving, "\(kind) has two distinct animation frames")
            XCTAssertTrue(images.insert(Data(idle)).inserted)
        }
    }
    func testSolidEnemyStripsMatchPixelsAndDesktopOutsideThemPassesThrough() throws {
        let state = frame(.spore)
        let image = try raster(state)
        // The test size gives the eleven-cell spore exactly three screen pixels per cell.
        for y in 63...97 {
            for x in 131...169 {
                let point = CGPoint(x: CGFloat(x)+0.5, y: CGFloat(y)+0.5)
                let hit = VirusArenaPixels.target(at: point, in: state)
                XCTAssertEqual(hit?.target == .enemy(2), image.pixel(x, y).last == 255,
                               "Target and visible ink differ at \(x), \(y)")
                if let strip = hit?.strip { XCTAssertTrue(strip.contains(point)) }
            }
        }
        XCTAssertNil(VirusArenaPixels.target(at: CGPoint(x: 90, y: 75), in: state))
        XCTAssertNil(VirusArenaPixels.target(at: CGPoint(x: 150, y: 59), in: state), "Enemy health meter is click-through")
        XCTAssertNil(VirusArenaPixels.target(at: CGPoint(x: 20, y: 147), in: state), "HUD is click-through")
        XCTAssertEqual(image.pixel(90, 75).last, 0, "Desktop around the fighters is transparent")
    }
    func testVisiblePickupsTakePriorityAndEachPowerHasItsOwnIcon() throws {
        var icons: Set<Data> = []
        for power in VirusArcade.PickupKind.allCases {
            let state = frame(.bug, pickup: power)
            XCTAssertEqual(VirusArenaPixels.target(at: center, in: state)?.target, .pickup(7))
            XCTAssertTrue(try icons.insert(Data(raster(state).region(141..<160, 71..<90))).inserted)
        }
        let plain = try raster(frame(.bug)), shielded = try raster(frame(.bug, shield: 3))
        let rapid = try raster(frame(.bug, rapid: 3))
        XCTAssertNotEqual(plain.region(15..<70, 65..<98), shielded.region(15..<70, 65..<98))
        XCTAssertNotEqual(plain.region(60..<75, 75..<90), rapid.region(60..<75, 75..<90))
        XCTAssertNotEqual(shielded.region(7..<34, 127..<139), rapid.region(7..<34, 127..<139))
    }
    func testBossHealthChangesInTheRenderedMeterAndLastPointStaysVisible() throws {
        let healthy = try raster(frame(.boss, hp: 10)), hurt = try raster(frame(.boss, hp: 1))
        XCTAssertNotEqual(healthy.region(130..<170, 57..<63), hurt.region(130..<170, 57..<63))
        XCTAssertEqual(healthy.region(128..<172, 64..<99), hurt.region(128..<172, 64..<99))
        XCTAssertEqual(VirusArenaPixels.healthFill(width: 20, hp: 1, maxHP: 99), 1)
        XCTAssertEqual(VirusArenaPixels.healthFill(width: 20, hp: 0, maxHP: 99), 0)
        XCTAssertEqual(VirusArenaPixels.healthFill(width: 20, hp: 999, maxHP: 99), 20)
    }
    func testMirroringProjectsOnlyTheVisibleStripEvenOnAnOffsetScreen() throws {
        let state = frame(.boss)
        let strip = try XCTUnwrap(VirusArenaPixels.target(at: center, in: state)?.strip)
        for mirrored in [false, true] {
            let p = VirusArenaProjection(rect: CGRect(x: -885, y: -43, width: 450, height: 272), mirrored: mirrored)
            let screen = p.screenRect(strip)
            let point = p.worldPoint(CGPoint(x: screen.midX, y: screen.midY))
            XCTAssertEqual(point.x, strip.midX, accuracy: 0.0001)
            XCTAssertEqual(point.y, strip.midY, accuracy: 0.0001)
            XCTAssertEqual(VirusArenaPixels.target(at: point, in: state)?.target, .enemy(2))
            let image = try raster(state, mirrored: mirrored)
            XCTAssertEqual(image.pixel(mirrored ? 284 : 15, 145).last, 255)
        }
    }
}
