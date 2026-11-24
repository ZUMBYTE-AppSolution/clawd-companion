import CoreGraphics
import XCTest
@testable import ClawdCompanion

final class MascotArtTests: XCTestCase {
    private func pixels(_ pose: MascotPose, left: Bool = false, gaze: CGVector = .zero,
                        count: Int = 0, frame: Int = 0) throws -> [UInt8] {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 56, height: 48,
                                             bitsPerComponent: 8, bytesPerRow: 56 * 4,
                                             space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                 | CGBitmapInfo.byteOrder32Big.rawValue))
        bitmap.translateBy(x: 0, y: 48)
        bitmap.scaleBy(x: 1, y: -1)
        MascotPixels.draw(in: bitmap, size: .init(width: 56, height: 48),
                          pose: pose, facingLeft: left, frame: frame, gaze: gaze, agentCount: count)
        let bytes = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: 56 * 48 * 4))
    }

    private func eyeCenter(_ pixels: [UInt8], rows: ClosedRange<Int> = 15...26) throws -> CGPoint {
        var eyes: [CGPoint] = []
        for y in rows {
            for x in 12...43 {
                let i = 4 * (y * 56 + x)
                if pixels[i] == 0x38 && pixels[i + 1] == 0x2B && pixels[i + 2] == 0x2C {
                    eyes.append(CGPoint(x: x, y: y))
                }
            }
        }
        XCTAssertFalse(eyes.isEmpty)
        return CGPoint(x: eyes.reduce(0) { $0 + $1.x } / CGFloat(eyes.count),
                       y: eyes.reduce(0) { $0 + $1.y } / CGFloat(eyes.count))
    }

    func testPupilsLookTowardDisplayCursorEvenWhenTheBodyIsMirrored() throws {
        for left in [true, false] {
            let northwest = try eyeCenter(pixels(.walking, left: left, gaze: .init(dx: -1, dy: 1)))
            let southeast = try eyeCenter(pixels(.walking, left: left, gaze: .init(dx: 1, dy: -1)))
            XCTAssertEqual(southeast.x - northwest.x, 4, accuracy: 0.001)
            XCTAssertEqual(southeast.y - northwest.y, 4, accuracy: 0.001)
        }
        XCTAssertEqual(try pixels(.sleeping, gaze: .init(dx: -1, dy: 1)),
                       try pixels(.sleeping, gaze: .init(dx: 1, dy: -1)))
    }

    func testDistinctJugglingCountsAndAnimationFrames() throws {
        for count in 1...5 {
            XCTAssertNotEqual(try pixels(.juggling, count: count, frame: 6),
                              try pixels(.juggling, count: count - 1, frame: 6))
        }
        XCTAssertEqual(try pixels(.juggling, count: .max), try pixels(.juggling, count: 5))
        XCTAssertEqual(try pixels(.juggling, count: -3), try pixels(.juggling, count: 0))
        XCTAssertNotEqual(try pixels(.juggling, count: 1, frame: 2), try pixels(.juggling, count: 1, frame: 8))
        XCTAssertNotEqual(try pixels(.archery, frame: 1), try pixels(.archery, frame: 8))
    }

    func testJumpTucksFeetAndLandingCompressesSilhouette() throws {
        func bounds(_ pose: MascotPose) throws -> ClosedRange<Int> {
            let rgba = try pixels(pose)
            let rows = (0..<48).filter { y in
                (0..<56).contains { x in rgba[4 * (56*y+x) + 3] != 0 }
            }
            return try XCTUnwrap(rows.first)...XCTUnwrap(rows.last)
        }
        let rising = try bounds(.jumping)
        let falling = try bounds(.falling)
        let landed = try bounds(.landing)
        XCTAssertLessThan(rising.upperBound, falling.upperBound)
        XCTAssertGreaterThan(landed.lowerBound, falling.lowerBound)
        XCTAssertLessThanOrEqual(abs(landed.upperBound - falling.upperBound), 1)
        for phase: MascotPose in [.jumping, .falling, .landing] {
            XCTAssertNotEqual(try pixels(phase), try pixels(phase, frame: 2))
            XCTAssertNotEqual(try pixels(phase, left: true, gaze: .init(dx: 1, dy: -1)),
                              try pixels(phase, left: true, gaze: .init(dx: -1, dy: 1)))
        }
    }

    func testLetterBlasterMirrorsItsMuzzleAndKeepsItsEyesVisible() throws {
        for left in [false, true] {
            let frame = try pixels(.letterBlaster, left: left)
            let muzzleX = left ? 2 : 53
            let muzzle = (29 * 56 + muzzleX) * 4
            XCTAssertEqual(Array(frame[muzzle..<muzzle + 4]), [0xFF, 0xD8, 0xAE, 0xFF])
            XCTAssertNotEqual(frame, try pixels(.archery, left: left))
            XCTAssertNotEqual(frame, try pixels(.letterBlaster, left: left, frame: 2))
            let northwest = try eyeCenter(pixels(.letterBlaster, left: left, gaze: .init(dx: -1, dy: 1)))
            let southeast = try eyeCenter(pixels(.letterBlaster, left: left, gaze: .init(dx: 1, dy: -1)))
            XCTAssertGreaterThan(southeast.x - northwest.x, 3)
            XCTAssertGreaterThan(southeast.y - northwest.y, 3)
        }
    }

    func testProjectileStartsAtTheLitMuzzleAtEveryAimAngle() throws {
        let directions: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1),
                                                 (0.8, 0.6), (0.35, -0.94), (-0.55, 0.84), (-0.8, -0.6)]
        for size in [CGSize(width: 105, height: 90), CGSize(width: 150, height: 90),
                     CGSize(width: 110, height: 155)] {
            let pet = CGRect(origin: CGPoint(x: -245, y: 176), size: size)
            let scale = min(size.width / 56, size.height / 48)
            for (dx, dy) in directions {
                let cursor = CGPoint(x: pet.midX + 500 * dx, y: pet.midY + 500 * dy)
                let left = cursor.x < pet.midX
                let aim = BlasterAim(pet: pet, cursor: cursor, facingLeft: left)
                let distance = hypot(cursor.x - aim.muzzle.x, cursor.y - aim.muzzle.y)
                XCTAssertEqual((cursor.x - aim.muzzle.x) / distance, aim.gaze.dx, accuracy: 1e-10)
                XCTAssertEqual((cursor.y - aim.muzzle.y) / distance, aim.gaze.dy, accuracy: 1e-10)
                let image = try pixels(.letterBlaster, left: left, gaze: aim.gaze)
                // Compare the real rendered cel with the flight system's release point in AppKit space.
                let gx = 28 + (aim.muzzle.x - pet.midX) / scale
                let gy = 24 - (aim.muzzle.y - pet.midY) / scale
                var nearest = CGFloat.infinity
                for y in 0..<48 {
                    for x in 0..<56 {
                        let i = (y * 56 + x) * 4
                        if Array(image[i..<i + 4]) == [0xFF, 0xD8, 0xAE, 0xFF] {
                            nearest = min(nearest, hypot(CGFloat(x) + 0.5 - gx, CGFloat(y) + 0.5 - gy))
                        }
                    }
                }
                XCTAssertLessThanOrEqual(nearest, 1.1, "Missing lit muzzle at \(gx), \(gy)")
            }
        }
    }

    func testPeekKeepsItsGripAndLooksPastTheLedge() throws {
        for left in [false, true] {
            let restingEyes = try eyeCenter(pixels(.walking, left: left))
            let gripX = left ? 20 : 35
            for frame in [0, 2] {
                let pose = try pixels(.peek, left: left, frame: frame)
                let peekingEyes = try eyeCenter(pose, rows: 26...33)
                XCTAssertGreaterThan(peekingEyes.y - restingEyes.y, 5)
                XCTAssertGreaterThan((peekingEyes.x - restingEyes.x) * (left ? -1 : 1), 4)
                XCTAssertEqual(pose[4 * (56 * 42 + gripX) + 3], 255)
            }
        }
        XCTAssertNotEqual(try pixels(.peek), try pixels(.peek, frame: 2))
    }

    func testVictoryDanceAlternatesFeetAndCarriesASparkAboveTheShell() throws {
        for (frame, planted, lifted, starX, starY) in [(0, 15, 40, 11, 8), (4, 40, 15, 36, 5)] {
            let pose = try pixels(.dancing, frame: frame)
            XCTAssertEqual(pose[4 * (42 * 56 + planted) + 3], 255)
            XCTAssertEqual(pose[4 * (42 * 56 + lifted) + 3], 0)
            let star = 4 * (starY * 56 + starX)
            XCTAssertEqual(Array(pose[star..<star + 4]), [0xFF, 0xD8, 0xAE, 0xFF])
        }
    }

    func testApprovalScrollOpensOnceAndRetracesTheSameFiveCels() throws {
        for left in [false, true] {
            let open = try (0...4).map { try pixels(.approvalOpening, left: left, frame: $0) }
            XCTAssertEqual(Set(open).count, 5)
            for step in 0...4 {
                XCTAssertEqual(open[step], try pixels(.approvalClosing, left: left, frame: 4 - step))
            }
            XCTAssertEqual(open[4], try pixels(.approvalOpening, left: left, frame: 960))
            XCTAssertEqual(open[4], try pixels(.awaitingApproval, left: left))
            XCTAssertEqual(open[0], try pixels(.approvalClosing, left: left, frame: 960))
            XCTAssertNotEqual(open[4], try pixels(.awaitingApproval, left: left, frame: 53))
        }
        XCTAssertEqual(MascotArt.transitionFrame(since: 10, now: 9), 0)
        XCTAssertEqual(MascotArt.transitionFrame(since: 10, now: 10.375), 3)
        XCTAssertEqual(MascotArt.transitionFrame(since: 10, now: 100), 4)
    }

    func testEpitaphReadsGITInEitherDirectionWhileOnlyTheCandleFlickers() throws {
        let frames = try [0, 4, 8, 12].map { try pixels(.grave, frame: $0) }
        XCTAssertEqual(Set(frames).count, 4)
        for (left, image) in [(false, frames[0]), (true, try pixels(.grave, left: true))] {
            XCTAssertEqual(image, frames[0], "Facing left must preserve the monument: \(left)")
            for (y, row) in GraveInscription.rows.enumerated() {
                for (x, letter) in row.enumerated() {
                    for sy in 0..<2 {
                        for sx in 0..<2 {
                            let i = ((20 + y * 2 + sy) * 56 + 13 + x * 2 + sx) * 4
                            XCTAssertEqual(Array(image[i..<i + 4]), letter == "1"
                                           ? [0x48, 0x30, 0x30, 255] : [0xC6, 0xDB, 0xD6, 255])
                        }
                    }
                }
            }
        }
        for frame in frames.dropFirst() {
            for i in stride(from: 0, to: frame.count, by: 4) where frame[i..<i+4] != frames[0][i..<i+4] {
                XCTAssertTrue((4...7).contains(i / 4 % 56))
                XCTAssertTrue((28...33).contains(i / 4 / 56))
            }
        }
    }

    func testResurrectionEmergesFromTheSameGraveAndHoldsTheLastCel() throws {
        for left in [false, true] {
            let cels = try (0..<MascotPose.revivalFrames).map { try pixels(.reviving, left: left, frame: $0) }
            XCTAssertEqual(Set(cels).count, 12)
            XCTAssertEqual(cels.first, try pixels(.grave, left: left))
            XCTAssertEqual(cels.last, try pixels(.reviving, left: left, frame: 960))
            XCTAssertEqual(cels.last, try pixels(.reviving, left: left, frame: MascotPose.reviving.stillFrame))
            func shellTop(_ image: [UInt8]) -> Int? {
                stride(from: 0, to: image.count, by: 4).first {
                    image[$0] == 0xE7 && image[$0 + 1] == 0x86 && image[$0 + 2] == 0x64
                }.map { $0 / 4 / 56 }
            }
            XCTAssertNil(shellTop(cels[0]))
            let emerged = try XCTUnwrap(shellTop(cels[4]))
            let peak = try XCTUnwrap(shellTop(cels[9]))
            let landed = try XCTUnwrap(shellTop(cels[11]))
            XCTAssertGreaterThan(emerged, landed + 10)
            XCTAssertLessThan(peak, landed)
            XCTAssertEqual(cels[11][(42 * 56 + (left ? 40 : 15)) * 4 + 3], 255)
            for frame in cels { XCTAssertTrue(frame[(43 * 56 * 4)...].allSatisfy { $0 == 0 }) }
        }
        XCTAssertTrue(MascotPose.reviving.isOneShot)
        XCTAssertEqual(MascotArt.transitionFrame(since: 12, now: 11, pose: .reviving), 0)
        XCTAssertEqual(MascotArt.transitionFrame(since: 12, now: 13, pose: .reviving), 8)
        XCTAssertEqual(MascotArt.transitionFrame(since: 12, now: 12 + MascotPose.revivalDuration, pose: .reviving), 11)
    }

    func testArcadeHeroKeepsCursorGazeAndCarriesDistinctShieldAndTrophy() throws {
        for left in [false, true] {
            let frame = try pixels(.virusFight, left: left)
            let cup = try pixels(.virusVictory, left: left)
            XCTAssertEqual(Set([frame, cup, try pixels(.happy, left: left), try pixels(.grave, left: left)]).count, 4)
            let shieldPixel = ((26 + 1) * 56 + (left ? 7 : 48)) * 4
            XCTAssertEqual(Array(frame[shieldPixel..<shieldPixel + 4]), [0xA6, 0xC9, 0xBF, 255])
            let gold = ((19 - 14 + 3) * 56 + (left ? 9 : 46)) * 4
            XCTAssertEqual(Array(cup[gold..<gold + 4]), [0xED, 0xBB, 0x77, 255])
            XCTAssertNotEqual(frame, try pixels(.virusFight, left: left, frame: 2))
            XCTAssertNotEqual(cup, try pixels(.virusVictory, left: left, frame: 2))
            for pose: MascotPose in [.virusFight, .virusVictory] {
                let west = try eyeCenter(pixels(pose, left: left, gaze: .init(dx: -1, dy: 0)), rows: 19...25)
                let east = try eyeCenter(pixels(pose, left: left, gaze: .init(dx: 1, dy: 0)), rows: 19...25)
                XCTAssertEqual(east.x - west.x, 4, accuracy: 0.01)
            }
        }
    }

    func testOKTextIsReadableInBothDirectionsWhileWaitingEyesFollowTheMouse() throws {
        for left in [false, true] {
            let rgba = try pixels(.awaitingApproval, left: left)
            let originX = left ? 7 : 38
            for (y, row) in ApprovalLettering.rows.enumerated() {
                for (x, char) in row.enumerated() {
                    let i = ((y + 6) * 56 + x + originX) * 4
                    let rgb = Array(rgba[i..<i + 3])
                    XCTAssertEqual(rgb, char == "1" ? [0x48, 0x30, 0x30] : [0xFF, 0xD8, 0xAE])
                }
            }
            let northwest = try eyeCenter(pixels(.awaitingApproval, left: left, gaze: .init(dx: -1, dy: 1)))
            let southeast = try eyeCenter(pixels(.awaitingApproval, left: left, gaze: .init(dx: 1, dy: -1)), rows: 15...28)
            XCTAssertEqual(southeast.x - northwest.x, 4)
            XCTAssertEqual(southeast.y - northwest.y, 4)
        }
    }

    func testPerchedHeelsStayOnTheTitleBarWhileFeetDangleAndEyesBlink() throws {
        for pose: MascotPose in [.perched, .perchThinking] {
            for left in [false, true] {
                let heelX = left ? 39 : 16, clawX = left ? 11 : 44
                for t in [0, 5, 20, 53] {
                    let img = try pixels(pose, left: left, frame: t)
                    XCTAssertEqual(img[(37 * 56 + heelX) * 4 + 3], 255)
                    XCTAssertEqual(img[(37 * 56 + clawX) * 4 + 3], 255)
                    XCTAssertEqual(img[(38 * 56 + heelX) * 4 + 3], 0)
                    XCTAssertEqual(img[(41 * 56 + (left ? 34 : 21)) * 4 + 3], 255)
                }
                let gaze1 = try eyeCenter(pixels(pose, left: left, gaze: .init(dx: -1, dy: 0)), rows: 20...30)
                let gaze2 = try eyeCenter(pixels(pose, left: left, gaze: .init(dx: 1, dy: 0)), rows: 20...30)
                XCTAssertGreaterThan(gaze2.x - gaze1.x, 3)
                XCTAssertNotEqual(try pixels(pose, left: left), try pixels(pose, left: left, frame: 53))
            }
        }
    }

    func testActivityToolsHaveDistinctSilhouettesAndMovingDetails() throws {
        let activities: [MascotPose] = [.planning, .researching, .reading, .executing, .drawing, .typing]
        for left in [false, true] {
            var signatures = Set<[UInt8]>()
            for pose in activities {
                let still = try pixels(pose, left: left)
                signatures.insert(still)
                XCTAssertNotEqual(still, try pixels(pose, left: left, frame: 4), pose.rawValue)
            }
            XCTAssertEqual(signatures.count, activities.count)
        }
    }
}
