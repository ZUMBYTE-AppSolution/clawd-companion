import AppKit

struct PetPlayFrame {
    let origin: CGPoint?
    let pose: MascotPose
    let facingLeft: Bool
    var blasterGaze: CGVector?
}

struct CodeSpark {
    enum Style { case flying, letter, hit, dodge }
    let point: CGPoint
    let direction: CGVector
    var text: String
    let style: Style
    let progress: Double
    let scale: CGFloat
}

struct PlayTick {
    var pet: PetPlayFrame?
    var spark: CodeSpark?
    var hit: Bool?
    var letterSprites: [Int: CodeSpark] = [:]
    var letterOutcomes: [Bool] = []
    var releaseSound: PetSound?
}

/// The owner calls this on its existing overlay clock. Idle play has no additional
/// timers; only a moving pet, flying token, or short result animation needs frames.
@MainActor
final class PetPlayController {
    var onRoundResolved: ((Bool) -> Void)?
    var onSound: ((PetSound) -> Void)?
    var hitCountForHUD: (() -> Int)?
    private var hitTotalForFlash: Int?
    var roamingEnabled = true
    var chaseEnabled = true
    var bowEnabled = true
    private var game = PetPlaySession()
    private var effect: CodeSparkPanel?
    private var letterPanels: [CodeSparkPanel] = []
    var needsFastTicks: Bool { game.inProgress }
    var bowInProgress: Bool { game.bowInProgress }
    var isWalking: Bool { game.isWalking }

    func yieldWalk() { game.yieldWalk() }

    func requestBow() { if bowEnabled { game.requestBow() } }
    func requestLetters() { if bowEnabled { game.requestLetters() } }

    func cancel() {
        game.cancel()
        hitTotalForFlash = nil
        if effect?.isVisible == true { effect?.orderOut(nil) }
        for panel in letterPanels where panel.isVisible { panel.orderOut(nil) }
    }

    func tick(now: TimeInterval, pet: CGRect, cursor: CGPoint, screens: [CGRect], mayRoam: Bool) -> PetPlayFrame? {
        let result = game.tick(now: now, pet: pet, cursor: cursor, screens: screens,
                               roam: mayRoam && roamingEnabled, chase: mayRoam && chaseEnabled, bow: bowEnabled)
        if let sound = result.releaseSound { onSound?(sound) }
        if let hit = result.hit {
            onRoundResolved?(hit)
            hitTotalForFlash = hit ? hitCountForHUD?() : nil
        }
        for hit in result.letterOutcomes { onRoundResolved?(hit) }
        let letters = result.letterSprites.sorted { $0.key < $1.key }
        for (index, item) in letters.enumerated() {
            if index == letterPanels.count { letterPanels.append(CodeSparkPanel()) }
            letterPanels[index].display(item.value)
        }
        for panel in letterPanels.dropFirst(letters.count) where panel.isVisible {
            panel.orderOut(nil)
        }
        if var spark = result.spark {
            if spark.style == .hit, spark.text == L("HIT +1"), let count = hitTotalForFlash {
                let formatted = count < 100_000 ? count.formatted(.number.grouping(.never).locale(L10n.locale)) : count.formatted(.number.notation(.compactName).locale(L10n.locale))
                spark.text = L("HIT +1 · {0}", formatted)
            }
            if effect == nil { effect = CodeSparkPanel() }
            effect?.display(spark)
        } else if effect?.isVisible == true { effect?.orderOut(nil) }
        return result.pet
    }
}

struct PetPlaySession {
    private struct Walk {
        var route: PetPlayRoute
        var began: Double
        var duration: Double
    }

    private struct Chase {
        var began: Double
        var until: Double
        var lastTick: Double
        var replanAt: Double
        var goal: CGPoint
        var route: PetPlayRoute
        var travelled: CGFloat = 0
    }

    private struct Shot {
        var word: String
        var target: CGPoint
        var left: Bool
        var scale: CGFloat
    }

    private struct Flight {
        var shot: Shot
        var path: CodeFlight
        var release: Double
        var previousPoint: CGPoint
        var previousCursor: CGPoint
        var previousTick: Double
    }

    private struct Flash {
        var shot: Shot
        var hit: Bool
        var point: CGPoint
        var began: Double
    }

    private enum Action {
        case walk(Walk), chase(Chase), windup(Shot, Double), flight(Flight), flash(Flash)
        case letters(LetterSalvo), dance(left: Bool, until: Double)
    }

    private enum GameChoice { case bow, letters }
    private var action: Action?
    private var walkAt: Double?
    private var chaseAt: Double?
    private var bowAt: Double?
    private var requestedGame: GameChoice?
    private var nextSalvo = -Double.infinity
    private var consecutiveDodges = 0
    private var earnedDance = false
    private let drawCount: (ClosedRange<Int>) -> Int
    private let random: (ClosedRange<Double>) -> Double
    var inProgress: Bool { action != nil }
    var isWalking: Bool {
        if case .walk = action { return true }
        return false
    }
    var bowInProgress: Bool {
        switch action {
        case .windup, .flight, .flash, .letters, .dance: return true
        default: return requestedGame != nil
        }
    }

    init(random: @escaping (ClosedRange<Double>) -> Double = { .random(in: $0) }) {
        self.init(random: random, drawCount: { Int.random(in: $0) })
    }

    init(random: @escaping (ClosedRange<Double>) -> Double, drawCount: @escaping (ClosedRange<Int>) -> Int) {
        self.drawCount = drawCount
        self.random = random
    }

    mutating func requestBow() { requestedGame = .bow }
    mutating func requestLetters() { requestedGame = .letters }

    // A window excursion takes over the current walk. The next chase and bow
    // retain their deadlines, and the next ordinary walk starts at the landing.
    mutating func yieldWalk() {
        guard isWalking else { return }
        action = nil
        walkAt = nil
    }

    mutating func cancel() {
        action = nil
        walkAt = nil
        chaseAt = nil
        bowAt = nil
        requestedGame = nil
        earnedDance = false
    }

    mutating func tick(now: Double, pet: CGRect, cursor: CGPoint, screens: [CGRect],
                       roam: Bool, chase: Bool, bow: Bool) -> PlayTick {
        let center = CGPoint(x: pet.midX, y: pet.midY)
        guard pet.width > 0, pet.height > 0, let home = PetPlayRoute.screen(containing: center, among: screens)
        else { cancel(); return PlayTick() }
        // Handles unplugged screens and pin/settings changes during an action.
        switch action {
        case .walk where !roam, .chase where !chase,
             .windup where !bow, .flight where !bow, .flash where !bow, .letters where !bow, .dance where !bow:
            action = nil
            earnedDance = false
        default: break
        }
        if walkAt == nil { walkAt = now + random(3.0...6.5) }
        if chaseAt == nil { chaseAt = now + random(13...33) }
        if bowAt == nil { bowAt = now + random(20...45) }
        let scale = min(2, max(0.6, pet.width / 105))
        if let choice = requestedGame {
            requestedGame = nil
            if bow, screens.contains(where: { $0.contains(cursor) }) {
                let canReplace: Bool
                switch action {
                case nil, .walk, .chase: canReplace = true
                default: canReplace = false
                }
                if canReplace { beginShot(choice, now, center, cursor, scale) }
            }
        }
        if action == nil {
            if bow, now >= bowAt! {
                bowAt = now + random(33...75)
                if screens.contains(where: { $0.contains(cursor) }), hypot(cursor.x-center.x, cursor.y-center.y) >= 95 * scale {
                    let game: GameChoice = now >= nextSalvo && random(0...1) > 0.84 ? .letters : .bow
                    beginShot(game, now, center, cursor, scale)
                }
            }
            if action == nil, chase, now >= chaseAt! {
                chaseAt = now + random(28...58)
                let goal = chaseGoal(cursor, from: center, size: pet.size, screens: screens)
                if let path = PetPlayRoute(center, to: goal, petSize: pet.size, screens: screens),
                   path.length > 80 * scale {
                    action = .chase(Chase(began: now, until: now + random(2.0...3.8), lastTick: now,
                                          replanAt: now + 0.22, goal: goal, route: path))
                }
            }
            if action == nil, roam, now >= walkAt! {
                walkAt = now + random(7...17)
                if let path = chooseWalk(from: center, home: home, pet: pet, screens: screens, scale: scale) {
                    let duration = min(14, max(0.9, path.length / (random(62...107) * scale)))
                    action = .walk(Walk(route: path, began: now, duration: duration))
                    walkAt = now + duration + random(2.2...8.4)
                }
            }
        }
        switch action {
        case nil: return PlayTick()
        case var .letters(salvo):
            let frame = salvo.tick(now: now, pet: pet, cursor: cursor)
            if frame.interrupted {
                action = nil
                earnedDance = false
                consecutiveDodges = 0
                return PlayTick()
            }
            for hit in frame.outcomes { score(hit) }
            if frame.finished { return endRound(now: now, left: salvo.left) }
            action = .letters(salvo)
            return PlayTick(pet: PetPlayFrame(origin: nil, pose: frame.pose, facingLeft: salvo.left, blasterGaze: frame.aim),
                            spark: frame.flash, letterSprites: frame.letters, letterOutcomes: frame.outcomes,
                            releaseSound: frame.fired ? .letters : nil)
        case let .dance(left, until):
            if now >= until { action = nil; return PlayTick() }
            return PlayTick(pet: PetPlayFrame(origin: nil, pose: .dancing, facingLeft: left))
        case let .walk(walk):
            let t = max(0, min(1, (now - walk.began) / walk.duration))
            let distance = walk.route.length * (0.5 - 0.5 * cos(t * .pi))
            let p = walk.route.point(at: distance)
            let heading = walk.route.point(at: min(walk.route.length, distance + 5))
            if t >= 1 { action = nil }
            return moving(to: p, towards: heading.x < p.x, size: pet.size)
        case var .chase(pursuit):
            if now >= pursuit.until { action = nil; return PlayTick() }
            let p = pursuit.route.point(at: pursuit.travelled)
            let goal = chaseGoal(cursor, from: p, size: pet.size, screens: screens)
            if now >= pursuit.replanAt, hypot(goal.x - pursuit.goal.x, goal.y - pursuit.goal.y) > 17 * scale {
                guard let path = PetPlayRoute(p, to: goal, petSize: pet.size, screens: screens) else {
                    action = nil
                    return PlayTick()
                }
                pursuit.route = path
                pursuit.goal = goal
                pursuit.travelled = 0
                pursuit.replanAt = now + 0.22
            }
            let remaining = pursuit.route.length - pursuit.travelled
            let speed = min(234 * scale, max(38 * scale, remaining * 2.3))
            let acceleration = min(1, 0.28 + (now - pursuit.began) * 3.2)
            let dt = min(0.13, max(0, now - pursuit.lastTick))
            pursuit.travelled += min(remaining, dt * speed * acceleration)
            pursuit.lastTick = now
            let destination = pursuit.route.point(at: pursuit.travelled)
            if pursuit.travelled >= pursuit.route.length - 1 { action = nil } else { action = .chase(pursuit) }
            let facingLeft = abs(destination.x - p.x) > 0.15 ? destination.x < p.x : cursor.x < p.x
            return moving(to: destination, towards: facingLeft, size: pet.size)
        case let .windup(shot, began):
            let stance = PetPlayFrame(origin: nil, pose: .archery, facingLeft: shot.left)
            guard now - began >= 0.82 else { return PlayTick(pet: stance) }
            // The target is locked when the bow appears. A moving pinned window
            // changes the muzzle's launch point but never retargets the token.
            let start = CGPoint(x: pet.minX + pet.width * (shot.left ? 6 : 50) / 56, y: pet.minY + pet.height * 22 / 48)
            let path = CodeFlight(start: start, target: shot.target, scale: shot.scale)
            action = .flight(Flight(shot: shot, path: path, release: now, previousPoint: start,
                                    previousCursor: cursor, previousTick: now))
            return PlayTick(pet: stance, spark: spark(shot: shot, point: start, direction: CGVector(dx: path.target.x-start.x, dy: path.target.y-start.y)),
                            releaseSound: .bow)
        case var .flight(flight):
            let elapsed = now - flight.previousTick
            if elapsed < 0 || elapsed > 0.35 { action = nil; return PlayTick() }
            let sample = flight.path.sample(now: now, release: flight.release, previous: flight.previousTick,
                                            mouseFrom: flight.previousCursor, mouseTo: cursor)
            let p = sample.point
            let hit = ProjectileGeometry.touches(word: flight.shot.word, letter: false, scale: flight.shot.scale,
                                                 from: flight.previousPoint, to: p,
                                                 mouseFrom: flight.previousCursor, mouseTo: sample.mouse)
            if hit || sample.ended {
                score(hit)
                let end = Flash(shot: flight.shot, hit: hit, point: hit ? sample.mouse : p, began: now)
                action = .flash(end)
                var result = flash(end, now: now)
                result.hit = hit
                return result
            }
            let direction = CGVector(dx: p.x - flight.previousPoint.x, dy: p.y - flight.previousPoint.y)
            flight.previousPoint = p
            flight.previousCursor = cursor
            flight.previousTick = now
            action = .flight(flight)
            let pose: MascotPose = now - flight.release < 0.32 ? .archery : .idle
            return PlayTick(pet: PetPlayFrame(origin: nil, pose: pose, facingLeft: flight.shot.left),
                            spark: spark(shot: flight.shot, point: p, direction: direction))
        case let .flash(end):
            if now - end.began >= 0.72 { return endRound(now: now, left: end.shot.left) }
            return flash(end, now: now)
        }
    }

    private mutating func score(_ hit: Bool) {
        consecutiveDodges = hit ? 0 : consecutiveDodges + 1
        if consecutiveDodges == 3 { earnedDance = true; consecutiveDodges = 0 }
    }

    private mutating func endRound(now: Double, left: Bool) -> PlayTick {
        if earnedDance {
            earnedDance = false
            action = .dance(left: left, until: now + 1.3)
            return PlayTick(pet: PetPlayFrame(origin: nil, pose: .dancing, facingLeft: left))
        }
        action = nil
        return PlayTick()
    }

    private mutating func beginShot(_ choice: GameChoice, _ now: Double, _ center: CGPoint, _ cursor: CGPoint, _ scale: CGFloat) {
        bowAt = now + random(35...78)
        if choice == .letters {
            nextSalvo = now + 240
            action = .letters(LetterSalvo(now: now, target: cursor, left: cursor.x < center.x,
                                         scale: scale, drawCount: drawCount, random: random))
            return
        }
        let words = ["i++", "=>", "nil", "0x2A", "};", "fn()", "[]"]
        let i = min(words.count-1, Int(random(0...Double(words.count))))
        let shot = Shot(word: words[i], target: cursor, left: cursor.x < center.x, scale: scale)
        action = .windup(shot, now)
    }

    private func chooseWalk(from center: CGPoint, home: CGRect, pet: CGRect, screens: [CGRect],
                            scale: CGFloat) -> PetPlayRoute? {
        if screens.count > 1, random(0...1) < 0.30 {
            let others = screens.filter { $0 != home }
            let k = min(others.count-1, Int(random(0...Double(others.count))))
            if !others.isEmpty {
                for i in 0..<others.count {
                    let area = others[(k+i) % others.count]
                    let end = CGPoint(x: area.minX + area.width * random(0.12...0.88),
                                      y: area.minY + area.height * random(0.14...0.80))
                    if let path = PetPlayRoute(center, to: end, petSize: pet.size, screens: screens) { return path }
                }
            }
        }
        let destination: CGPoint
        if random(0...1) < 0.60 {
            let direction: CGFloat
            if center.x > home.maxX - pet.width * 1.4 { direction = -1 }
            else if center.x < home.minX + pet.width * 1.4 { direction = 1 }
            else { direction = random(0...1) < 0.5 ? -1 : 1 }
            destination = CGPoint(x: center.x + direction * random(90...290) * scale,
                                  y: center.y + random(-95...95) * scale)
        } else {
            destination = CGPoint(x: home.minX + home.width * random(0.10...0.90),
                                  y: home.minY + home.height * random(0.12...0.84))
        }
        let goal = PetPlayRoute.clamp(destination, size: pet.size, inside: home)
        guard let path = PetPlayRoute(center, to: goal, petSize: pet.size, screens: screens), path.length > 15 else { return nil }
        return path
    }

    private func chaseGoal(_ pointer: CGPoint, from pet: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint {
        let side: CGFloat = pointer.x >= pet.x ? -1 : 1
        let p = CGPoint(x: pointer.x + side * size.width * 0.78, y: pointer.y - size.height * 0.18)
        guard let area = PetPlayRoute.screen(containing: pointer, among: screens) else { return p }
        return PetPlayRoute.clamp(p, size: size, inside: area)
    }

    private func moving(to point: CGPoint, towards left: Bool, size: CGSize) -> PlayTick {
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        return PlayTick(pet: PetPlayFrame(origin: origin, pose: .walking, facingLeft: left))
    }

    private func spark(shot: Shot, point: CGPoint, direction: CGVector) -> CodeSpark {
        CodeSpark(point: point, direction: direction, text: shot.word, style: .flying, progress: 0, scale: shot.scale)
    }

    private func flash(_ end: Flash, now: Double) -> PlayTick {
        let effect = CodeSpark(point: end.point, direction: .zero, text: end.hit ? L("HIT +1") : end.shot.word,
                               style: end.hit ? .hit : .dodge, progress: min(1, (now-end.began) / 0.72), scale: end.shot.scale)
        let pose: MascotPose = end.hit ? .happy : .thinking
        return PlayTick(pet: PetPlayFrame(origin: nil, pose: pose, facingLeft: end.shot.left), spark: effect)
    }
}
