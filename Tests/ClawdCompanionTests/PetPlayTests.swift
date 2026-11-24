import XCTest
@testable import ClawdCompanion

final class PetPlayTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1280, height: 795)
    private let pet = CGRect(x: 80, y: 92, width: 105, height: 90)
    private let target = CGPoint(x: 630, y: 300)
    private func session() -> PetPlaySession {
        PetPlaySession(random: { ($0.lowerBound + $0.upperBound) / 2 }, drawCount: { $0.lowerBound })
    }

    private func rounds(cursorAfterWindup: CGPoint) -> (poses: [MascotPose], results: [Bool], tags: [String]) {
        var game = session()
        game.requestBow()
        var poses: [MascotPose] = [], results: [Bool] = [], tokens: [String] = []
        for i in 0...180 {
            let frame = game.tick(now: Double(i) / 60, pet: pet, cursor: i == 0 ? target : cursorAfterWindup,
                                  screens: [screen], roam: false, chase: false, bow: true)
            if let pose = frame.pet?.pose { poses.append(pose) }
            if let score = frame.hit { results.append(score) }
            if let fx = frame.spark { tokens.append(fx.text) }
        }
        return (poses, results, tokens)
    }

    func testStationaryCursorScoresExactlyOnceAndShowsFeedback() {
        let round = rounds(cursorAfterWindup: target)
        XCTAssertEqual(round.results, [true])
        XCTAssertEqual(round.poses.first, .archery)
        XCTAssertTrue(round.poses.contains(.happy))
        XCTAssertTrue(round.tags.contains("HIT +1"))
    }

    func testCursorCanActuallyDodgeAtStartOfWindup() {
        let round = rounds(cursorAfterWindup: CGPoint(x: 200, y: 700))
        XCTAssertEqual(round.results, [false])
        XCTAssertTrue(round.poses.contains(.thinking))
        XCTAssertFalse(round.tags.contains("HIT +1"))
    }

    func testAudioCuesCoincideWithEachActualProjectileRelease() {
        for sound in [PetSound.bow, .letters] {
            var game = session()
            if sound == .bow { game.requestBow() } else { game.requestLetters() }
            var seenLetters: Set<Int> = []
            var sawBow = false
            var cues: [PetSound] = []
            for i in 0...180 {
                let frame = game.tick(now: Double(i) / 60, pet: pet, cursor: target,
                                      screens: [screen], roam: false, chase: false, bow: true)
                let firstBowFrame = frame.spark?.style == .flying && !sawBow
                let newLetters = Set(frame.letterSprites.keys).subtracting(seenLetters)
                XCTAssertEqual(frame.releaseSound, firstBowFrame || !newLetters.isEmpty ? sound : nil)
                if let cue = frame.releaseSound { cues.append(cue) }
                if firstBowFrame { sawBow = true }
                seenLetters.formUnion(newLetters)
            }
            XCTAssertEqual(cues, sound == .bow ? [.bow] : [.letters, .letters, .letters])
        }
    }

    func testCancelAndSettingsNeverScoreAnInterruptedShot() {
        var game = session()
        game.requestBow()
        for i in 0...61 {
            _ = game.tick(now: Double(i)/60, pet: pet, cursor: target, screens: [screen],
                          roam: false, chase: false, bow: true)
        }
        XCTAssertTrue(game.bowInProgress)
        let disabled = game.tick(now: 1.1, pet: pet, cursor: target, screens: [screen], roam: false, chase: false, bow: false)
        XCTAssertNil(disabled.hit)
        XCTAssertFalse(game.inProgress)
        game.requestBow()
        XCTAssertTrue(game.bowInProgress)
        game.cancel()
        XCTAssertFalse(game.bowInProgress)
    }

    func testAutonomousBowWorksWithoutDisplacingPinnedPet() {
        var game = session()
        var shots = 0
        for i in 0...2200 {
            let frame = game.tick(now: Double(i) / 60, pet: pet, cursor: target, screens: [screen],
                                  roam: false, chase: false, bow: true)
            XCTAssertNil(frame.pet?.origin)
            if frame.hit == true { shots += 1 }
        }
        XCTAssertEqual(shots, 1)
    }

    func testRareSalvoCooldownSurvivesInterruptedRoamingAndManualBowStaysABow() {
        var game = PetPlaySession { $0.upperBound }
        func tick(_ time: Double) -> PlayTick {
            game.tick(now: time, pet: pet, cursor: target, screens: [screen], roam: false, chase: false, bow: true)
        }
        _ = tick(0)
        XCTAssertEqual(tick(46).pet?.pose, .letterBlaster)
        game.cancel()
        _ = tick(50)
        XCTAssertEqual(tick(96).pet?.pose, .archery)
        game.cancel()
        game.requestBow()
        XCTAssertEqual(tick(300).pet?.pose, .archery)
        game.cancel()
        _ = tick(301)
        XCTAssertEqual(tick(347).pet?.pose, .letterBlaster)
    }

    func testThreeEscapedLettersEarnOneShortCelebration() {
        var game = session()
        game.requestLetters()
        var results: [Bool] = []
        var poses: [MascotPose] = []
        for i in 0...360 {
            let cursor = i <= 74 ? target : CGPoint(x: 220, y: 700)
            let frame = game.tick(now: Double(i) / 60, pet: pet, cursor: cursor, screens: [screen],
                                  roam: false, chase: false, bow: true)
            results.append(contentsOf: frame.letterOutcomes)
            if let pose = frame.pet?.pose { poses.append(pose) }
        }
        XCTAssertEqual(results, [false, false, false])
        XCTAssertEqual(poses.first, .letterBlaster)
        XCTAssertEqual(poses.last, .dancing)
        XCTAssertTrue((77...80).contains(poses.filter { $0 == .dancing }.count))
        XCTAssertFalse(game.inProgress)
    }

    func testSleepGapDuringFlightDoesNotCreateAnUnobservedHit() {
        var game = session()
        game.requestBow()
        for i in 0...59 {
            _ = game.tick(now: Double(i) / 60, pet: pet, cursor: target, screens: [screen],
                          roam: false, chase: false, bow: true)
        }
        let resumed = game.tick(now: 11, pet: pet, cursor: target, screens: [screen], roam: false, chase: false, bow: true)
        XCTAssertNil(resumed.hit)
        XCTAssertFalse(game.inProgress)
    }

    func testActualCursorPathIsSweptBetweenFrames() {
        let old = CGPoint(x: 0, y: 20), end = CGPoint(x: 40, y: 20)
        XCTAssertTrue(ProjectileGeometry.touches(word: "A", letter: true, scale: 1, from: old, to: end,
                                                 mouseFrom: CGPoint(x: 12, y: 30), mouseTo: CGPoint(x: 30, y: 8)))
        XCTAssertFalse(ProjectileGeometry.touches(word: "A", letter: true, scale: 1, from: old, to: end,
                                                  mouseFrom: CGPoint(x: 12, y: 32), mouseTo: CGPoint(x: 30, y: 32)))
    }

    func testCursorArrivingAfterBowExpiredDoesNotHit() throws {
        var game = session()
        game.requestBow()
        _ = game.tick(now: 0, pet: pet, cursor: target, screens: [screen], roam: false, chase: false, bow: true)
        let away = CGPoint(x: target.x, y: target.y + 220)
        let release = game.tick(now: 0.83, pet: pet, cursor: away, screens: [screen], roam: false, chase: false, bow: true)
        let path = CodeFlight(start: try XCTUnwrap(release.spark?.point), target: target, scale: 1)
        let end = 0.83 + path.duration
        var time = 0.93
        while time < end - 0.05 {
            _ = game.tick(now: time, pet: pet, cursor: away, screens: [screen], roam: false, chase: false, bow: true)
            time += 0.1
        }
        _ = game.tick(now: end - 0.04, pet: pet, cursor: away, screens: [screen], roam: false, chase: false, bow: true)
        let expired = game.tick(now: end + 0.14, pet: pet, cursor: target, screens: [screen], roam: false, chase: false, bow: true)
        XCTAssertEqual(expired.hit, false)
    }

    func testWalksStartAndEndSmoothlyAndNeverLeaveOneScreen() throws {
        var game = session()
        var petFrame = pet
        var points: [CGPoint] = []
        var walking = false
        for i in 0..<1200 {
            let frame = game.tick(now: Double(i) / 60, pet: petFrame, cursor: target, screens: [screen],
                                  roam: true, chase: false, bow: false)
            if let pos = frame.pet?.origin {
                XCTAssertEqual(frame.pet?.pose, .walking)
                walking = true
                petFrame.origin = pos
                XCTAssertTrue(screen.contains(petFrame))
                points.append(pos)
            } else if walking { break }
        }
        XCTAssertGreaterThan(points.count, 30)
        let start = try XCTUnwrap(points.first), end = try XCTUnwrap(points.last)
        XCTAssertGreaterThan(hypot(end.x - start.x, end.y - start.y), 50)
        XCTAssertLessThan(hypot(points[1].x - start.x, points[1].y - start.y), 0.5)
    }

    func testCursorChaseStopsBesidePointerWithoutCoveringIt() {
        var game = session()
        var petFrame = pet
        let near = CGPoint(x: 375, y: 150)
        var ran = false
        for i in 0..<1800 {
            let frame = game.tick(now: Double(i) / 60, pet: petFrame, cursor: near, screens: [screen],
                                  roam: false, chase: true, bow: false)
            if let pos = frame.pet?.origin {
                ran = true
                petFrame.origin = pos
                XCTAssertFalse(petFrame.contains(near))
            }
        }
        XCTAssertTrue(ran)
        XCTAssertLessThan(abs(petFrame.midX - near.x), pet.width * 1.15)
    }

    func testNeighbouringDisplaysUseOverlapAndRejectUnreachableIslands() throws {
        let other = CGRect(x: -1200, y: 220, width: 1200, height: 860)
        let start = CGPoint(x: 140, y: 60), end = CGPoint(x: -300, y: 660)
        let route = try XCTUnwrap(PetPlayRoute(start, to: end, petSize: pet.size, screens: [screen, other]))
        XCTAssertEqual(route.point(at: 0), start)
        XCTAssertEqual(route.point(at: route.length + 20), end)
        for p in route.stops where p.x == 0 {
            XCTAssertGreaterThanOrEqual(p.y, other.minY + pet.height / 2)
            XCTAssertLessThanOrEqual(p.y, screen.maxY - pet.height / 2)
        }
        let island = other.offsetBy(dx: -400, dy: 0)
        XCTAssertNil(PetPlayRoute(start, to: CGPoint(x: -1000, y: 700), petSize: pet.size, screens: [screen, island]))
    }
}
