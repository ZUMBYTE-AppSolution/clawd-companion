import CoreGraphics
import Foundation

struct LetterSalvoFrame {
    var letters: [Int: CodeSpark] = [:]
    var outcomes: [Bool] = []
    var flash: CodeSpark?
    var fired = false
    var finished = false
    var interrupted = false
    var pose: MascotPose = .idle
    var aim: CGVector?
}

/// The blaster tracks the cursor between releases. Every letter in flight
/// keeps the muzzle position and aim sampled for that particular launch.
struct LetterSalvo {
    private struct Flight {
        let path: CodeFlight
        let released: Double

        func point(at time: Double) -> CGPoint {
            path.point(at: (time - released) / path.duration)
        }
    }

    private(set) var left: Bool
    private var lastTarget: CGPoint
    private let scale: CGFloat
    private let glyphs: [String]
    private var nextRelease: Double
    private var released = 0
    private var flying: [Int: Flight] = [:]
    private var previousTick: Double
    private var previousCursor: CGPoint
    private var hits = 0
    private var lastHit: CGPoint?
    private var flashBegan: Double?
    private var finished = false

    init(now: Double, target: CGPoint, left: Bool, scale: CGFloat,
         drawCount: (ClosedRange<Int>) -> Int = { Int.random(in: $0) },
         random: (ClosedRange<Double>) -> Double) {
        self.left = left
        self.scale = scale
        self.lastTarget = target
        self.nextRelease = now + 0.80
        self.previousTick = now
        self.previousCursor = target
        let count = drawCount(3...42)
        var available: [Character] = []
        self.glyphs = (0..<count).map { _ in
            if available.isEmpty { available = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
            let index = min(available.count - 1, Int(random(0...Double(available.count))))
            return String(available.remove(at: index))
        }
    }

    mutating func tick(now: Double, pet: CGRect, cursor: CGPoint) -> LetterSalvoFrame {
        guard !finished else { return LetterSalvoFrame(finished: true) }
        if let began = flashBegan {
            if now - began < 0.72 { return feedback(elapsed: now - began) }
            finished = true
            return LetterSalvoFrame(finished: true)
        }

        let dt = now - previousTick
        // Never infer cursor travel over a sleep or replay missed releases after it.
        if dt < 0 || (dt > 0.35 && (released > 0 || now > nextRelease + 0.35)) {
            finished = true
            return LetterSalvoFrame(finished: true, interrupted: true)
        }
        defer { previousTick = now; previousCursor = cursor }

        let aiming = released < glyphs.count || now < nextRelease
        if aiming { left = cursor.x < pet.midX }
        let aim = BlasterAim(pet: pet, cursor: cursor, facingLeft: left)
        var result = LetterSalvoFrame(pose: aiming ? .letterBlaster : .idle, aim: aiming ? aim.gaze : nil)
        for id in flying.keys.sorted() {
            guard let flight = flying[id] else { continue }
            let sample = flight.path.sample(now: now, release: flight.released, previous: previousTick,
                                            mouseFrom: previousCursor, mouseTo: cursor)
            let point = sample.point
            let old = flight.point(at: previousTick)
            let hit = ProjectileGeometry.touches(word: glyphs[id], letter: true, scale: scale,
                                                  from: old, to: point, mouseFrom: previousCursor, mouseTo: sample.mouse)
            if hit || sample.ended {
                result.outcomes.append(hit)
                flying[id] = nil
                if hit {
                    hits += 1
                    lastHit = sample.mouse
                }
            } else {
                result.letters[id] = spark(id, at: point, towards: CGVector(dx: point.x - old.x, dy: point.y - old.y))
            }
        }
        if released < glyphs.count && now >= nextRelease {
            let muzzle = aim.muzzle
            lastTarget = cursor
            flying[released] = Flight(path: CodeFlight(letterFrom: muzzle, through: cursor, scale: scale), released: now)
            result.letters[released] = spark(released, at: muzzle, towards: CGVector(dx: cursor.x - muzzle.x, dy: cursor.y - muzzle.y))
            result.fired = true
            released += 1
            nextRelease = now + 0.19
        }
        if released == glyphs.count && flying.isEmpty {
            flashBegan = now
            var frame = feedback(elapsed: 0)
            frame.outcomes = result.outcomes
            return frame
        }
        return result
    }

    private func spark(_ id: Int, at point: CGPoint, towards direction: CGVector) -> CodeSpark {
        CodeSpark(point: point, direction: direction, text: glyphs[id], style: .letter, progress: 0, scale: scale)
    }

    private func feedback(elapsed: Double) -> LetterSalvoFrame {
        let total = glyphs.count.formatted(.number.locale(L10n.locale))
        let score = hits.formatted(.number.locale(L10n.locale))
        let flash = CodeSpark(point: lastHit ?? lastTarget, direction: .zero,
                              text: hits > 0 ? L("HIT {0}/{1}", score, total) : L("{0}/{1} TREFFER", score, total),
                              style: hits > 0 ? .hit : .dodge, progress: elapsed / 0.72, scale: scale)
        return LetterSalvoFrame(flash: flash, pose: hits > 0 ? .happy : .thinking)
    }
}
