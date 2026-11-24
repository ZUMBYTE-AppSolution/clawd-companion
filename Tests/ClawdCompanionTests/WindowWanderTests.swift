import XCTest
@testable import ClawdCompanion

final class WindowWanderTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 760)
    private let pet = CGRect(x: 730, y: 142, width: 105, height: 90)
    private let box = CGRect(x: 200, y: 170, width: 470, height: 335)

    private func window(_ rect: CGRect, screen: CGRect, pid: pid_t = 17,
                        roof: Bool = true, right: Bool = true, leftInside: Bool = false) -> SceneryWindow {
        SceneryWindow(id: 8, pid: pid, frame: rect, screen: screen, leftClear: true, rightClear: right,
                      roofClear: roof, leftInside: leftInside)
    }

    private struct Walk {
        var engine = WindowWander { $0.lowerBound }
        var time = 0.0
        var pet: CGRect
        var screen: CGRect
        var windows: [SceneryWindow]

        mutating func tick(_ seconds: Double = 1.0/60, mayStart: Bool = true) -> WindowWander.Frame? {
            time += seconds
            let frame = engine.tick(now: time, pet: pet, screen: screen, windows: windows, mayStart: mayStart)
            if let frame { pet.origin = frame.origin }
            return frame
        }

        mutating func reach(_ phase: WindowWander.Phase) throws -> WindowWander.Frame {
            for _ in 0..<1500 {
                if let frame = tick(), frame.phase == phase { return frame }
            }
            throw NSError(domain: "Unreached phase \(phase)", code: 1)
        }
    }

    private func walk() -> Walk {
        Walk(pet: pet, screen: screen, windows: [window(box, screen: screen)])
    }

    func testSittingKeepsItsVisibleHeelsOnTheMovingActiveWindowAndLooksAround() throws {
        func active(_ bounds: CGRect, focused: Bool = true) -> SceneryWindow {
            SceneryWindow(id: 8, pid: 17, frame: bounds, screen: screen,
                          leftClear: true, rightClear: true, isActive: focused)
        }
        var walker = Walk(pet: pet, screen: screen, windows: [active(box)])
        let arrival = try walker.reach(.perch)
        XCTAssertEqual(arrival.pose, .perched)
        XCTAssertEqual(walker.pet.minY + pet.height * 10/48, box.maxY, accuracy: 0.01)
        let moved = box.offsetBy(dx: -116, dy: 22)
        walker.windows = [active(moved)]
        let attached = try XCTUnwrap(walker.tick())
        XCTAssertEqual(attached.origin.x - arrival.origin.x, -116, accuracy: 0.01)
        XCTAssertEqual(attached.origin.y + pet.height * 10/48, moved.maxY, accuracy: 0.01)
        var poses: Set<MascotPose> = [], facings: Set<Bool> = []
        for _ in 0..<185 {
            let f = try XCTUnwrap(walker.tick())
            XCTAssertEqual(f.phase, .perch)
            XCTAssertEqual(f.origin, attached.origin)
            poses.insert(f.pose)
            facings.insert(f.facingLeft)
        }
        XCTAssertEqual(poses, [.perched, .perchThinking])
        XCTAssertEqual(facings, [true, false])
        let shifted = moved.offsetBy(dx: 210, dy: -40)
        walker.windows = [active(shifted, focused: false)]
        for _ in 0..<1800 {
            let sitting = try XCTUnwrap(walker.tick())
            XCTAssertEqual(sitting.phase, .perch)
            XCTAssertEqual(sitting.origin.x, attached.origin.x + 210, accuracy: 0.01)
            XCTAssertEqual(sitting.origin.y, attached.origin.y - 40, accuracy: 0.01)
        }
        let secondScreen = screen.offsetBy(dx: screen.width, dy: 0)
        let relocated = shifted.offsetBy(dx: screen.width, dy: 0)
        walker.windows = [SceneryWindow(id: 8, pid: 17, frame: relocated, screen: secondScreen,
                                        leftClear: true, rightClear: true)]
        XCTAssertEqual(walker.tick()?.phase, .perch)
        walker.screen = secondScreen
        XCTAssertEqual(walker.tick()?.phase, .perch)
        XCTAssertEqual(walker.pet.midX, relocated.midX, accuracy: 0.01)
        walker.windows = []
        XCTAssertEqual(walker.tick()?.pose, .falling)
    }

    func testManualSeatOnlyStartsWithRealActiveReachableTitleAndCanBeginImmediately() throws {
        var game = WindowWander { $0.upperBound }
        func start(_ windows: [SceneryWindow]) -> WindowWander.Frame? {
            game.tick(now: 0, pet: pet, screen: screen, windows: windows, mayStart: false, requestSeat: true)
        }
        XCTAssertNil(start([]))
        XCTAssertNil(start([window(box, screen: screen)]))
        let covered = SceneryWindow(id: 8, pid: 17, frame: box, screen: screen,
                                   leftClear: true, rightClear: true, roofClear: false, isActive: true)
        XCTAssertNil(start([covered]))
        let real = SceneryWindow(id: 8, pid: 17, frame: box, screen: screen,
                                leftClear: true, rightClear: true, isActive: true)
        XCTAssertEqual(try XCTUnwrap(start([real])).phase, .approach)
    }

    func testLowHeadroomReachesTheActualTitleBeforeJumping() throws {
        let high = CGRect(x: 160,y: 80,width: 540,height: 676)
        var walker = Walk(pet: pet, screen: screen, windows: [window(high, screen: screen, roof: false)])
        var highestPaw = -CGFloat.infinity
        for _ in 0..<1400 {
            guard let f = walker.tick() else { continue }
            if f.phase == .climb { highestPaw = max(highestPaw, walker.pet.minY + pet.height*34/48) }
            if f.phase == .jump { break }
        }
        XCTAssertGreaterThanOrEqual(highestPaw, high.maxY - 24)
        XCTAssertLessThanOrEqual(highestPaw, high.maxY)
        let large = CGSize(width: 105 * 1.65, height: 90 * 1.65)
        let flushGrip = WindowLedge.gripY(window: screen, screen: screen, pet: large)
        XCTAssertGreaterThanOrEqual(flushGrip + WindowLedge.offset(forRow: 14, pet: large), screen.maxY - 25)
        XCTAssertLessThanOrEqual(flushGrip + WindowLedge.offset(forRow: 6, pet: large), screen.maxY)
        let near = high.offsetBy(dx: 0, dy: -60)
        let standing = try XCTUnwrap(WindowLedge.standY(window: near, screen: screen, pet: pet.size))
        let sitting = try XCTUnwrap(WindowLedge.seatY(window: near, screen: screen, pet: pet.size))
        let contact = standing + WindowLedge.offset(forRow: 43, pet: pet.size)
        XCTAssertEqual(sitting + WindowLedge.offset(forRow: 38, pet: pet.size), contact, accuracy: 0.001)
        XCTAssertLessThanOrEqual(near.maxY - contact, 24)
        XCTAssertLessThanOrEqual(standing + pet.height, screen.maxY)
    }

    func testLargestClimbingSpriteKeepsActualInkOutOfMenuAndHandOnTitle() throws {
        let size = CGSize(width: 105 * 1.65, height: 90 * 1.65)
        let y = WindowLedge.gripY(window: screen, screen: screen, pet: size)
        for left in [true, false] {
            for frame in 0..<8 {
                let c = try XCTUnwrap(CGContext(data: nil, width: 56, height: 48, bitsPerComponent: 8,
                    bytesPerRow: 56 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                c.translateBy(x: 0, y: 48)
                c.scaleBy(x: 1, y: -1)
                MascotPixels.draw(in: c, size: CGSize(width: 56, height: 48), pose: .climbing, facingLeft: left, frame: frame)
                let bytes = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
                func hasInk(_ x: Int, _ row: Int) -> Bool { bytes[(row * 56 + x) * 4 + 3] > 0 }
                let head = try XCTUnwrap((0..<48).first { row in (0..<56).contains { hasInk($0, row) } })
                XCTAssertLessThanOrEqual(y + WindowLedge.offset(forRow: CGFloat(head), pet: size), screen.maxY)
                let gripColumns = left ? 7...12 : 43...48
                let paw = try XCTUnwrap((0..<20).first { row in gripColumns.contains { hasInk($0, row) } })
                XCTAssertGreaterThanOrEqual(y + WindowLedge.offset(forRow: CGFloat(paw), pet: size), screen.maxY - 24)
            }
        }
    }

    func testWalkClimbsCrossesRoofAndJumpsOutwardWithContinuousVisibleArc() throws {
        var walk = walk()
        var phases: [WindowWander.Phase] = []
        var poses: [MascotPose] = []
        var heights: [CGFloat] = []
        var launchX = 0.0
        var landingTime: Double?
        var peekFrames: [WindowWander.Frame] = []
        for _ in 0..<1500 {
            let last = walk.pet.origin
            guard let frame = walk.tick() else {
                if !phases.isEmpty { break }
                continue
            }
            if phases.last != frame.phase { phases.append(frame.phase) }
            XCTAssertTrue(screen.contains(walk.pet))
            XCTAssertLessThan(hypot(frame.origin.x - last.x, frame.origin.y - last.y), 24)
            if frame.phase == .climb { XCTAssertTrue(frame.facingLeft) }
            if frame.phase == .ledge {
                XCTAssertTrue(frame.facingLeft)
                XCTAssertEqual(frame.origin.y + pet.height * 5/48, box.maxY, accuracy: 0.01)
            }
            if frame.phase == .peek { peekFrames.append(frame) }
            if frame.phase == .jump {
                if heights.isEmpty { launchX = frame.origin.x }
                heights.append(frame.origin.y)
                if poses.last != frame.pose { poses.append(frame.pose) }
            }
            if frame.phase == .land {
                if landingTime == nil { landingTime = walk.time }
                XCTAssertEqual(frame.pose, .landing)
                XCTAssertEqual(frame.origin.y, screen.minY + 1)
                XCTAssertLessThan(frame.origin.x, launchX)
            }
        }
        XCTAssertEqual(phases, [.approach, .climb, .crest, .ledge, .peek, .jump, .land])
        XCTAssertGreaterThan(peekFrames.count, 40)
        XCTAssertTrue(peekFrames.allSatisfy { $0.pose == .peek && $0.facingLeft && $0.origin == peekFrames.first?.origin })
        XCTAssertEqual(poses, [.jumping, .falling])
        XCTAssertGreaterThan(try XCTUnwrap(heights.max()) - XCTUnwrap(heights.first), 25)
        XCTAssertGreaterThanOrEqual(walk.time - (try XCTUnwrap(landingTime)), 0.26)
        XCTAssertFalse(walk.engine.isActive)
        XCTAssertNil(walk.tick(15.9))
    }

    func testRoofPeekIsOccasionalAndLeavesTheRegularJumpIntact() throws {
        var walker = walk()
        walker.engine = WindowWander { $0.upperBound }
        _ = try walker.reach(.ledge)
        while let frame = walker.tick() {
            XCTAssertNotEqual(frame.phase, .peek)
            if frame.phase == .land { return }
        }
        XCTFail("The roof crossing should end with a jump and landing")
    }

    private func rightPerch() -> SceneryWindow {
        SceneryWindow(id: 8, pid: 17, frame: box, screen: screen, leftClear: false, rightClear: true,
                      roofClear: false, leftRoofClear: false, rightRoofClear: true)
    }

    func testPartiallyCoveredRoofUsesClearHalfThenReturnsToSameRim() throws {
        var walker = walk()
        walker.windows = [rightPerch()]
        var directions: [Bool] = []
        var positions: [CGFloat] = []
        _ = try walker.reach(.crest)
        while let frame = walker.tick() {
            if frame.phase == .ledge {
                positions.append(frame.origin.x)
                if directions.last != frame.facingLeft { directions.append(frame.facingLeft) }
                XCTAssertGreaterThanOrEqual(walker.pet.minX, box.maxX - box.width * SceneryWindow.surveyedRoofFraction)
            }
            if frame.phase == .peek { XCTAssertFalse(frame.facingLeft) }
            if frame.phase == .land { break }
        }
        XCTAssertEqual(directions, [true, false])
        XCTAssertGreaterThan(try XCTUnwrap(positions.max()) - XCTUnwrap(positions.min()), pet.width * 0.6)
        XCTAssertGreaterThan(walker.pet.midX, box.maxX)
    }

    func testNewOccluderDuringClimbOrEarlyCrossingShortensRouteWithoutMovingThePetAbruptly() throws {
        for phase in [WindowWander.Phase.climb, .ledge] {
            var walker = walk()
            _ = try walker.reach(phase)
            for _ in 0..<12 { _ = walker.tick() }
            walker.windows = [rightPerch()]
            let before = walker.pet.origin
            let after = try XCTUnwrap(walker.tick())
            XCTAssertEqual(after.phase, phase)
            XCTAssertLessThan(hypot(after.origin.x - before.x, after.origin.y - before.y), 6)
            let peek = try walker.reach(.peek)
            XCTAssertTrue(peek.origin.x > box.midX)
            XCTAssertFalse(peek.facingLeft)
            _ = try walker.reach(.land)
            XCTAssertGreaterThan(walker.pet.midX, box.maxX)
        }
    }

    func testLosingTheRemainingPerchDropsFromTheCurrentRoofPosition() throws {
        var walker = walk()
        _ = try walker.reach(.ledge)
        for _ in 0..<8 { _ = walker.tick() }
        walker.windows = [rightPerch()]
        _ = try XCTUnwrap(walker.tick())
        walker.windows = [window(box, screen: screen, roof: false)]
        let last = walker.pet.origin
        let drop = try XCTUnwrap(walker.tick())
        XCTAssertEqual(drop.origin, last)
        XCTAssertEqual(drop.pose, .falling)
        XCTAssertEqual(try walker.reach(.land).pose, .landing)
    }

    func testRaisedWindowHasALevelRunUpThenAHopToTheWall() throws {
        var walker = walk()
        walker.pet.origin = CGPoint(x: 830, y: 12)
        let floor = walker.pet.minY
        var count = 0
        var caughtWall = false
        for _ in 0..<540 {
            guard let frame = walker.tick() else { continue }
            if frame.phase == .climb { caughtWall = true; break }
            if frame.pose == .walking { XCTAssertEqual(frame.origin.y, floor, accuracy: 0.01) }
            if frame.pose == .jumping { count += 1 }
        }
        XCTAssertTrue(caughtWall)
        XCTAssertGreaterThan(count, 12)
        XCTAssertGreaterThan(walker.pet.minY, floor + 80)
    }

    func testTallInsideRimOnSecondaryDisplayStaysVisibleAndPushesInward() throws {
        let other = screen.offsetBy(dx: -1100, dy: -215)
        let tall = CGRect(x: other.minX, y: other.minY + 12, width: 963, height: 725)
        var walker = Walk(pet: CGRect(origin: CGPoint(x: other.minX + 52, y: other.minY + 69), size: pet.size),
                          screen: other, windows: [window(tall, screen: other, roof: false, right: false, leftInside: true)])
        var phases: [WindowWander.Phase] = []
        var launch: CGPoint?
        var landing: CGPoint?
        for _ in 0..<1450 {
            guard let frame = walker.tick() else { if landing != nil { break }; continue }
            XCTAssertTrue(other.contains(walker.pet))
            if phases.last != frame.phase { phases.append(frame.phase) }
            if frame.phase == .climb {
                XCTAssertTrue(frame.facingLeft)
                XCTAssertEqual(frame.origin.x, other.minX, accuracy: 0.01)
            }
            if frame.phase == .jump && launch == nil { launch = frame.origin }
            if frame.phase == .land { landing = frame.origin }
        }
        XCTAssertEqual(phases, [.approach, .climb, .jump, .land])
        XCTAssertGreaterThan(try XCTUnwrap(launch).y, tall.midY)
        XCTAssertGreaterThan(try XCTUnwrap(landing).x, try XCTUnwrap(launch).x + 40)
    }

    func testMovingWindowCarriesClimberSmoothlyAndLossOfIdentityDropsFromLastPoint() throws {
        var walker = walk()
        let onWall = try walker.reach(.climb)
        let moved = box.offsetBy(dx: 24, dy: 5)
        walker.windows = [window(moved, screen: screen)]
        let first = try XCTUnwrap(walker.tick())
        XCTAssertGreaterThan(first.origin.x, onWall.origin.x)
        XCTAssertLessThan(first.origin.x, onWall.origin.x + 12)
        for _ in 0..<15 { _ = walker.tick() }
        XCTAssertEqual(walker.pet.minX, onWall.origin.x + 24, accuracy: 0.6)
        let last = walker.pet.origin
        walker.windows = [window(moved, screen: screen, pid: 99)]
        let detached = try XCTUnwrap(walker.tick())
        XCTAssertEqual(detached.origin, last)
        XCTAssertEqual(detached.pose, .falling)
        walker.windows = []
        let ground = try walker.reach(.land)
        XCTAssertEqual(ground.origin.y, screen.minY + 1)
        XCTAssertLessThan(abs(ground.origin.x - last.x), pet.width/2)
    }

    func testApproachCanYieldAndIneligibleOrDisabledWalkNeverStarts() throws {
        var walker = walk()
        for _ in 0..<420 { XCTAssertNil(walker.tick(mayStart: false)) }
        XCTAssertEqual(walker.tick()?.phase, .approach)
        walker.windows = []
        XCTAssertNil(walker.tick())
        XCTAssertFalse(walker.engine.isActive)
        walker.windows = [window(box, screen: screen.offsetBy(dx: -1000, dy: 0))]
        for _ in 0..<720 { XCTAssertNil(walker.tick()) }
    }

    func testWindowClosureDuringJumpKeepsArcButDisplayChangesAndSleepYield() throws {
        var walker = walk()
        _ = try walker.reach(.jump)
        walker.windows = []
        var slept = walker
        XCTAssertNil(slept.tick(2))
        XCTAssertFalse(slept.engine.isActive)
        var resized = walker
        resized.pet.size = CGSize(width: 112, height: 96)
        XCTAssertNil(resized.tick())
        var disconnected = walker
        disconnected.screen = screen.offsetBy(dx: 1050, dy: 0)
        XCTAssertNil(disconnected.tick())
        XCTAssertEqual(try walker.reach(.land).phase, .land)
        walker.engine.cancel()
        XCTAssertFalse(walker.engine.isActive)
        XCTAssertNil(walker.tick())
    }
}
