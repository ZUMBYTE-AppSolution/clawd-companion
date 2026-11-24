import XCTest
@testable import ClawdCompanion

final class LetterSalvoTests: XCTestCase {
    private let pet = CGRect(x: 0, y: 0, width: 56, height: 48)
    private let target = CGPoint(x: 350, y: 19)
    private let away = CGPoint(x: 400, y: 320)

    private func salvo(maximum: Bool = false) -> LetterSalvo {
        LetterSalvo(now: 0, target: target, left: false, scale: 1, drawCount: { range in
            XCTAssertEqual(range, 3...42)
            return maximum ? range.upperBound : range.lowerBound
        }, random: { $0.upperBound })
    }

    func testBothCountBoundsSpacingShuffleBagsAndSinglePerLetterScore() {
        for maximum in [false, true] {
            let count = maximum ? 42 : 3
            var game = salvo(maximum: maximum)
            var releases: [Double] = [], labels: [Int: String] = [:]
            var outcomes: [Bool] = [], flashes = 0
            var lastProgress: Double?
            var peak = 0
            for i in 0...800 {
                let now = Double(i) / 60
                let frame = game.tick(now: now, pet: pet, cursor: target)
                if now < 0.80 {
                    XCTAssertEqual(frame.pose, .letterBlaster)
                    XCTAssertTrue(frame.letters.isEmpty)
                }
                if frame.fired { releases.append(now) }
                peak = max(peak, frame.letters.count)
                for (id, letter) in frame.letters {
                    XCTAssertEqual(letter.style, .letter)
                    if let label = labels[id] { XCTAssertEqual(letter.text, label) }
                    labels[id] = letter.text
                }
                outcomes += frame.outcomes
                if let flash = frame.flash {
                    if let previous = lastProgress { XCTAssertGreaterThan(flash.progress, previous) }
                    else { flashes += 1; XCTAssertEqual(flash.progress, 0) }
                    lastProgress = flash.progress
                    XCTAssertEqual(flash.text, "HIT \(count)/\(count)")
                    XCTAssertEqual(flash.style, .hit)
                    XCTAssertEqual(frame.pose, .happy)
                } else { lastProgress = nil }
            }
            XCTAssertEqual(releases.count, count)
            XCTAssertEqual(labels.count, count)
            let letters = labels.sorted { $0.key < $1.key }.map(\.value)
            XCTAssertEqual(Array(letters.prefix(3)), ["Z", "Y", "X"])
            if maximum {
                XCTAssertEqual(Set(letters.prefix(26)).count, 26)
                XCTAssertEqual(Set(letters.dropFirst(26)).count, 16)
                XCTAssertLessThan(peak, 10)
            }
            XCTAssertEqual(releases.first ?? 0, 0.80, accuracy: 0.017)
            for (a, b) in zip(releases, releases.dropFirst()) { XCTAssertTrue((0.18...0.23).contains(b - a)) }
            XCTAssertEqual(outcomes, Array(repeating: true, count: count))
            XCTAssertEqual(flashes, 1)
            let end = game.tick(now: 20, pet: pet, cursor: target)
            XCTAssertTrue(end.finished)
            XCTAssertNil(end.flash)
            XCTAssertTrue(end.outcomes.isEmpty)
        }
    }

    func testMovingPinAndCursorRetargetMuzzleWithoutSteeringLettersAlreadyInFlight() throws {
        var game = salvo()
        let leftTarget = CGPoint(x: -400, y: 290)
        let relocated = pet.offsetBy(dx: 30, dy: 22)
        let first = game.tick(now: 0.80, pet: pet, cursor: target)
        let rightAim = BlasterAim(pet: pet, cursor: target, facingLeft: false)
        XCTAssertEqual(first.letters[0]?.point, rightAim.muzzle)
        XCTAssertEqual(first.aim, rightAim.gaze)
        let path = CodeFlight(letterFrom: rightAim.muzzle, through: target, scale: 1)
        let next = game.tick(now: 1.00, pet: relocated, cursor: leftTarget)
        XCTAssertTrue(game.left)
        let leftAim = BlasterAim(pet: relocated, cursor: leftTarget, facingLeft: true)
        XCTAssertEqual(next.letters[1]?.point, leftAim.muzzle)
        XCTAssertEqual(next.aim, leftAim.gaze)
        let expected = path.point(at: 0.20 / path.duration)
        let old = try XCTUnwrap(next.letters[0])
        XCTAssertEqual(old.point.x, expected.x, accuracy: 1e-6)
        XCTAssertEqual(old.point.y, expected.y, accuracy: 1e-6)

        let turnedAgain = game.tick(now: 1.20, pet: relocated, cursor: away)
        XCTAssertFalse(game.left)
        XCTAssertEqual(turnedAgain.letters[2]?.point, BlasterAim(pet: relocated, cursor: away, facingLeft: false).muzzle)
    }

    func testPointerCrossingRenderedFirstLetterBetweenFramesOnlyScoresOnce() throws {
        var game = salvo()
        let first = game.tick(now: 0.80, pet: pet, cursor: target)
        let muzzle = try XCTUnwrap(first.letters[0]).point
        let path = CodeFlight(letterFrom: muzzle, through: target, scale: 1)
        let head = path.point(at: 0.10 / path.duration)
        // Z's diagonal passes through its centre. The swept cursor reaches it.
        let crossed = game.tick(now: 0.90, pet: pet, cursor: head)
        XCTAssertEqual(crossed.outcomes, [true])
        XCTAssertNil(crossed.letters[0])
        var outcomes = crossed.outcomes
        var finalText: String?
        for i in 0...220 {
            let now = 0.91 + Double(i) / 60
            let cursor = now < 1.23 ? target : away
            let frame = game.tick(now: now, pet: pet, cursor: cursor)
            outcomes += frame.outcomes
            if let flash = frame.flash { finalText = flash.text }
        }
        XCTAssertEqual(outcomes, [true, false, false])
        XCTAssertEqual(finalText, "HIT 1/3")
    }

    func testMouseReachingAimAfterFirstFlightExpiredCountsAsDodge() throws {
        var game = salvo()
        let frame = game.tick(now: 0.80, pet: pet, cursor: target)
        let muzzle = try XCTUnwrap(frame.letters[0]).point
        let path = CodeFlight(letterFrom: muzzle, through: target, scale: 1)
        let end = 0.8 + path.duration
        let waiting = CGPoint(x: target.x, y: target.y + 180)
        var now = 0.90
        while now < end - 0.04 {
            _ = game.tick(now: now, pet: pet, cursor: waiting)
            now += 0.10
        }
        _ = game.tick(now: end - 0.03, pet: pet, cursor: waiting)
        let late = game.tick(now: end + 0.13, pet: pet, cursor: target)
        XCTAssertEqual(late.outcomes, [false])
    }

    func testClockGapCancelsRemainingLettersWithoutScoring() {
        var game = salvo(maximum: true)
        for i in 0...72 {
            let frame = game.tick(now: Double(i) / 60, pet: pet, cursor: away)
            XCTAssertTrue(frame.outcomes.isEmpty)
        }
        for now in [1.57, 2.8, 20] {
            let frame = game.tick(now: now, pet: pet, cursor: target)
            XCTAssertTrue(frame.finished)
            XCTAssertTrue(frame.outcomes.isEmpty)
            XCTAssertTrue(frame.letters.isEmpty)
            XCTAssertNil(frame.flash)
        }
    }
}
