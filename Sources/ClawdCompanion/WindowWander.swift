import CoreGraphics
import Foundation

/// A free-roaming encounter with a real window. Coordinates are global AppKit
/// points; the caller owns the desktop clock and all higher-priority activities.
struct WindowWander {
    enum Phase: Hashable { case approach, climb, crest, ledge, perch, peek, jump, land }

    struct Frame {
        var origin: CGPoint
        var pose: MascotPose
        var facingLeft: Bool
        var phase: Phase
    }

    private enum Side: CaseIterable {
        case left, right
        var opposite: Self { self == .left ? .right : .left }
        var outward: CGFloat { self == .left ? -1 : 1 }
        func edge(_ r: CGRect) -> CGFloat { self == .left ? r.minX : r.maxX }
        func available(_ w: SceneryWindow) -> Bool { self == .left ? w.leftClear : w.rightClear }
        func inside(_ w: SceneryWindow) -> Bool { self == .left ? w.leftInside : w.rightInside }
        func hasPerch(_ w: SceneryWindow, petWidth: CGFloat) -> Bool {
            let safe = self == .left ? w.leftRoofClear : w.rightRoofClear
            return safe && w.frame.width * SceneryWindow.surveyedRoofFraction >= petWidth
        }
    }

    private enum Contact: Equatable { case start, runUp, wallFoot, wallTop, crest, roofTurn, lip, onRoof(CGFloat) }

    private struct Leg {
        let from: Contact
        let to: Contact
        let phase: Phase
        let duration: Double
    }

    private struct Route {
        let start: CGPoint
        let pet: CGSize
        let screen: CGRect
        var side: Side
        var exitSide: Side
        let inside: Bool
        let roof: Bool
        var footOffset: CGFloat = 0

        var scale: CGFloat { pet.width / 105 }
        var facesWallLeft: Bool { (side == .right) != inside }
        var jumpDirection: CGFloat { exitSide.outward * (inside ? -1 : 1) }

        func position(_ mark: Contact, window r: CGRect) -> CGPoint {
            let edge = side.edge(r), inward = -side.outward
            // Wall claws and walking soles occupy different offsets in the
            // original 56×48 sprite. Align visible pixels, not the panel border.
            let gripX = edge - pet.width * (facesWallLeft ? 5 : 51) / 56
            // At a flush inside rim the sprite's transparent margin would
            // extend beyond the display. Keep the whole overlay on this screen.
            let wallX = inside ? min(allowedOrigins.maxX, max(allowedOrigins.minX, gripX)) : gripX
            let wallTop = WindowLedge.gripY(window: r, screen: screen, pet: pet)
            let roofY = WindowLedge.standY(window: r, screen: screen, pet: pet) ?? wallTop
            func rimX(_ x: CGFloat) -> CGFloat { min(allowedOrigins.maxX, max(allowedOrigins.minX, x)) }
            let crestX = rimX(edge + inward * pet.width * 0.22 - pet.width / 2)
            // The whole pet, including its inward-facing claws, must fit on
            // the surveyed part of a partially covered roof at the turn.
            let maxDepth = r.width * SceneryWindow.surveyedRoofFraction - pet.width / 2
            let turnDepth = min(pet.width * 1.57, maxDepth)
            let lipX = rimX(exitSide.edge(r) - exitSide.outward * pet.width * 0.14 - pet.width / 2)
            switch mark {
            case .start: return start
            case .runUp:
                // Keep the approach level until the last stride below a raised window.
                let remaining = min(pet.width * 0.53, abs(wallX - start.x))
                let x = wallX + (start.x < wallX ? -remaining : remaining)
                return CGPoint(x: x, y: start.y)
            case .wallFoot: return CGPoint(x: wallX, y: max(screen.minY + 2, r.minY + footOffset))
            case .wallTop: return CGPoint(x: wallX, y: wallTop)
            case .crest: return CGPoint(x: crestX, y: roofY)
            case .roofTurn: return CGPoint(x: edge + inward * turnDepth - pet.width / 2, y: roofY)
            case .lip: return CGPoint(x: lipX, y: roofY)
            case let .onRoof(fraction): return CGPoint(x: r.minX + r.width * fraction - pet.width / 2, y: roofY)
            }
        }

        func leg(_ from: Contact, _ to: Contact, _ phase: Phase, speed: CGFloat, window: CGRect) -> Leg {
            let a = position(from, window: window), b = position(to, window: window)
            let duration = max(0.18, WindowWander.distance(a, b) / (speed * scale))
            return Leg(from: from, to: to, phase: phase, duration: duration)
        }

        func ledgeLegs(window: CGRect) -> [Leg] {
            if exitSide != side { return [leg(.crest, .lip, .ledge, speed: 168, window: window)] }
            return [leg(.crest, .roofTurn, .ledge, speed: 150, window: window),
                    leg(.roofTurn, .lip, .ledge, speed: 155, window: window)]
        }

        var allowedOrigins: CGRect {
            CGRect(x: screen.minX, y: screen.minY, width: screen.width - pet.width,
                   height: screen.height - pet.height)
        }

        func supports(_ w: SceneryWindow) -> Bool {
            guard screen == w.screen, side.available(w), side.inside(w) == inside else { return false }
            let bottom = position(.wallFoot, window: w.frame), top = position(.wallTop, window: w.frame)
            let area = allowedOrigins.insetBy(dx: -0.55, dy: -0.55)
            let gripArea = CGRect(x: area.minX, y: area.minY, width: area.width,
                height: area.height + pet.height - WindowLedge.offset(forRow: 6, pet: pet))
            guard area.contains(bottom), gripArea.contains(top), top.y - bottom.y >= 0.47 * pet.height else { return false }
            if roof {
                guard exitSide.available(w), exitSide == side || !exitSide.inside(w),
                      (exitSide == side ? side.hasPerch(w, petWidth: pet.width) : w.roofClear) else { return false }
                let marks: [Contact] = exitSide == side ? [.crest, .roofTurn, .lip] : [.crest, .lip]
                for mark in marks {
                    guard area.contains(position(mark, window: w.frame)) else { return false }
                }
                return WindowLedge.standY(window: w.frame, screen: screen, pet: pet) != nil
            }
            return true
        }
    }

    private struct Visit {
        var targetID: CGWindowID
        var pid: pid_t
        var route: Route
        var legs: [Leg]
        var began: TimeInterval
        var visibleRect: CGRect

        func isSitting(at time: Double) -> Bool {
            var elapsed = time - began
            for leg in legs {
                if elapsed <= leg.duration { return leg.phase == .perch }
                elapsed -= leg.duration
            }
            return false
        }

        mutating func endRest(at time: Double) {
            guard let index = legs.firstIndex(where: { $0.phase == .perch }) else { return }
            let start = began + legs.prefix(index).reduce(0) { $0 + $1.duration }
            if time < start { legs.remove(at: index) }
            else if time < start + legs[index].duration {
                legs[index] = Leg(from: legs[index].from, to: legs[index].to, phase: .perch, duration: max(0.001, time-start))
            }
        }

        /// A new foreground window can cover the planned crossing after takeoff
        /// from the floor. Preserve progress when a connected way back exists.
        mutating func keepSupport(on window: SceneryWindow, pet: CGRect, now: TimeInterval) -> Bool {
            if route.supports(window) { return true }
            guard route.roof, route.exitSide != route.side else { return false }
            let approach = legs.prefix { $0.phase != .ledge }
            let onRoof = now - began > approach.reduce(0) { $0 + $1.duration }
            let peek = legs.last?.phase == .peek ? legs.last : nil
            let sides = onRoof ? [route.side, route.exitSide] : [route.side]
            for side in sides {
                var shorter = route
                shorter.side = side
                shorter.exitSide = side
                guard shorter.supports(window) else { continue }
                if onRoof {
                    // Only return along a side which still contains the whole
                    // sprite. Occlusion underneath the pet releases its grip.
                    let coveredDepth = side == .left ? pet.maxX - window.frame.minX : window.frame.maxX - pet.minX
                    guard coveredDepth <= window.frame.width * SceneryWindow.surveyedRoofFraction else { continue }
                    let fraction = (pet.midX - visibleRect.minX) / visibleRect.width
                    legs = [shorter.leg(.onRoof(fraction), .lip, .ledge, speed: 155, window: visibleRect)]
                    began = now
                } else {
                    legs = Array(approach) + shorter.ledgeLegs(window: visibleRect)
                }
                if let peek { legs.append(peek) }
                route = shorter
                return true
            }
            return false
        }
    }

    private struct Leap {
        var start: CGPoint
        var end: CGPoint
        var riseVelocity: CGFloat
        var began: TimeInterval
        var duration: TimeInterval
        var facingLeft: Bool
    }

    private enum Action {
        case visit(Visit), jump(Leap), land(Frame, until: TimeInterval)
    }

    private let random: (ClosedRange<Double>) -> Double
    private var action: Action?
    private var attemptAt: TimeInterval?
    private var lastSample: TimeInterval?
    private var originalScreen: CGRect?
    private var originalSize: CGSize?
    var isActive: Bool { action != nil }

    init(random: @escaping (ClosedRange<Double>) -> Double = { .random(in: $0) }) { self.random = random }

    mutating func cancel() {
        action = nil
        attemptAt = nil
        lastSample = nil
        originalScreen = nil
        originalSize = nil
    }

    mutating func tick(now: TimeInterval, pet: CGRect, screen: CGRect, windows: [SceneryWindow],
                       mayStart: Bool = true, requestSeat: Bool = false) -> Frame? {
        guard screen.width > pet.width, screen.height > pet.height, pet.width > 0, pet.height > 0 else {
            cancel()
            return nil
        }
        if action == nil {
            if attemptAt == nil { attemptAt = now + random(4...8) }
            guard requestSeat || (mayStart && now >= (attemptAt ?? .infinity)) else { return nil }
            attemptAt = now + random(1.8...3.8)
            guard let visit = choose(now: now, pet: pet, screen: screen, windows: windows, requestSeat: requestSeat) else { return nil }
            action = .visit(visit)
            originalScreen = screen
            originalSize = pet.size
            lastSample = now
        }
        let dt = now - (lastSample ?? now)
        guard dt >= 0, dt < 1.1, originalScreen == screen, originalSize == pet.size else {
            cancel()
            return nil
        }
        lastSample = now
        switch action {
        case var .visit(visit):
            let match = windows.first {
                $0.id == visit.targetID && $0.pid == visit.pid &&
                    (($0.isActive && visit.isSitting(at: now)) || Self.geometryChange($0.frame, visit.visibleRect) < max(85, pet.width * 1.5))
            }
            if let w = match, visit.keepSupport(on: w, pet: pet, now: now) {
                // Window lists arrive more slowly than animation frames. Ease
                // ordinary motion between samples; a teleport loses support.
                let weight = min(1, 1 - exp(-max(0, dt) * 20))
                if !w.isActive { visit.endRest(at: now) }
                visit.visibleRect = visit.isSitting(at: now) ? w.frame : Self.blend(visit.visibleRect, w.frame, weight)
                action = .visit(visit)
                var elapsed = now - visit.began
                for leg in visit.legs {
                    if elapsed <= leg.duration {
                        let a = visit.route.position(leg.from, window: visit.visibleRect)
                        let b = visit.route.position(leg.to, window: visit.visibleRect)
                        let t = max(0, min(1, elapsed / leg.duration))
                        let eased = t * t * (3 - 2 * t)
                        var origin = Self.blend(a, b, eased)
                        let pose: MascotPose
                        let left: Bool
                        switch leg.phase {
                        case .approach where leg.from == .runUp:
                            // A hop catches the lower side of a floating window.
                            // Rise quickly, then slow into the handhold.
                            origin.y = a.y + (b.y - a.y) * t * (2 - t)
                            pose = .jumping
                            left = abs(b.x - a.x) < 1 ? visit.route.facesWallLeft : b.x < a.x
                        case .climb, .crest:
                            pose = .climbing
                            left = visit.route.facesWallLeft
                        case .peek:
                            pose = .peek
                            left = visit.route.exitSide == .left
                        case .perch:
                            pose = t > 0.30 && t < 0.74 ? .perchThinking : .perched
                            left = t < 0.54 ? visit.route.side == .left : visit.route.side == .right
                            origin.y = WindowLedge.seatY(window: visit.visibleRect, screen: screen, pet: pet.size) ?? origin.y
                        default:
                            pose = .walking
                            left = b.x < a.x
                        }
                        return Frame(origin: origin, pose: pose, facingLeft: left, phase: leg.phase)
                    }
                    elapsed -= leg.duration
                }
                let mark: Contact = visit.route.roof ? .lip : .wallTop
                let lip = visit.route.position(mark, window: visit.visibleRect)
                startJump(from: lip, now: now, route: visit.route, window: visit.visibleRect)
            } else {
                // Approaching a vanished window simply gives control back to
                // the current walk. A pet already clinging to it drops from the
                // last displayed point without following the vanished window.
                if let leg = visit.legs.first, leg.phase == .approach, now - visit.began <= leg.duration {
                    cancel()
                    return nil
                }
                startJump(from: pet.origin, now: now, route: visit.route, window: visit.visibleRect, recovering: true)
            }
            return airborneFrame(now: now)
        case .jump: return airborneFrame(now: now)
        case let .land(frame, until):
            if now < until { return frame }
            action = nil
            attemptAt = now + random(16...36)
            return nil
        case nil: return nil
        }
    }

    private func choose(now: TimeInterval, pet: CGRect, screen: CGRect, windows: [SceneryWindow], requestSeat: Bool) -> Visit? {
        var best: Visit?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let wantsSeat = requestSeat || (windows.contains { $0.screen == screen && $0.isActive } && random(0...1) < 0.38)
        var bestHasSeat = false
        for window in windows where window.screen == screen {
            for side in Side.allCases where side.available(window) {
                let inside = side.inside(window)
                // A narrow cap above a window can support a side push-off but
                // cannot support walking on top without clipping the sprite.
                let accessibleTitle = WindowLedge.standY(window: window.frame, screen: screen, pet: pet.size) != nil
                let across = accessibleTitle && !inside && window.roofClear && window.frame.width <= 6.0 * pet.width &&
                    side.opposite.available(window) && !side.opposite.inside(window)
                let roof = accessibleTitle && (across || side.hasPerch(window, petWidth: pet.width))
                var route = Route(start: pet.origin, pet: pet.size, screen: screen,
                                  side: side, exitSide: across ? side.opposite : side, inside: inside, roof: roof)
                let high = route.position(.wallTop, window: window.frame).y
                let foot = max(window.frame.minY - pet.height * 0.22, min(high - pet.height * 0.75, pet.minY))
                route.footOffset = foot - window.frame.minY
                guard route.supports(window) else { continue }
                let entry = route.position(.wallFoot, window: window.frame)
                let distance = Self.distance(entry, pet.origin)
                let hasSeat = wantsSeat && window.isActive && roof
                guard !requestSeat || hasSeat,
                      requestSeat || distance < (hasSeat ? 650 : 350) * route.scale,
                      hasSeat == bestHasSeat ? distance < bestDistance : hasSeat else { continue }
                // Do not make a pet on a neighbouring roof walk down a wall to join this one.
                let alreadyOnTop = hasSeat && pet.midX >= window.frame.minX && pet.midX <= window.frame.maxX &&
                    abs(pet.minY - route.position(.crest, window: window.frame).y) <= pet.height * 0.2
                guard requestSeat || alreadyOnTop || pet.minY < high - pet.height * 0.25 else { continue }
                var legs: [Leg] = []
                func leg(_ from: Contact, _ to: Contact, _ phase: Phase, speed: CGFloat) {
                    legs.append(route.leg(from, to, phase, speed: speed, window: window.frame))
                }
                if alreadyOnTop {
                    let start = Contact.onRoof((pet.midX - window.frame.minX) / window.frame.width)
                    leg(start, .lip, .ledge, speed: 150)
                } else {
                    if entry.y - pet.minY > pet.height * 0.38 {
                        leg(.start, .runUp, .approach, speed: 185)
                        leg(.runUp, .wallFoot, .approach, speed: 225)
                    } else {
                        leg(.start, .wallFoot, .approach, speed: 185)
                    }
                    leg(.wallFoot, .wallTop, .climb, speed: 162)
                    if roof {
                        leg(.wallTop, .crest, .crest, speed: 154)
                        legs.append(contentsOf: route.ledgeLegs(window: window.frame))
                    }
                }
                bestDistance = distance
                bestHasSeat = hasSeat
                best = Visit(targetID: window.id, pid: window.pid, route: route, legs: legs,
                             began: now, visibleRect: window.frame)
            }
        }
        if var visit = best, bestHasSeat,
           let i = visit.legs.firstIndex(where: { $0.phase == .ledge }) {
            let first = visit.legs[i]
            let destination: Contact = visit.route.exitSide == visit.route.side ? .roofTurn : .onRoof(0.5)
            var stops = [visit.route.leg(first.from, destination, .ledge, speed: 150, window: visit.visibleRect),
                         Leg(from: destination, to: destination, phase: .perch, duration: random(3.5...6.0))]
            if first.to != destination {
                stops.append(visit.route.leg(destination, first.to, .ledge, speed: 150, window: visit.visibleRect))
            }
            visit.legs.replaceSubrange(i...i, with: stops)
            best = visit
        }
        if let visit = best, visit.route.roof, random(0...1) < 0.55 {
            best?.legs.append(Leg(from: .lip, to: .lip, phase: .peek, duration: random(0.72...0.98)))
        }
        return best
    }

    private mutating func startJump(from start: CGPoint, now: TimeInterval, route: Route, window: CGRect,
                                    recovering: Bool = false) {
        let area = route.allowedOrigins
        let direction = route.jumpDirection
        let reach = route.roof ? 0.88 : 1.10
        let targetX = recovering ? start.x + direction * route.pet.width * 0.35
            : route.exitSide.edge(window) + direction * route.pet.width * reach - route.pet.width / 2
        let end = CGPoint(x: min(area.maxX, max(area.minX, targetX)),
                          y: area.minY + 1)
        let drop = max(0, start.y - end.y)
        let lift = recovering ? 0 : min(32 * route.scale, max(0, area.maxY - start.y - 1))
        // y(t) = start + v*t - (v + drop)*t². Solve v for the desired
        // apex, so even a long fall first produces a visible upward push.
        let velocity = 2 * (lift + sqrt(lift * (lift + drop)))
        let duration = min(1.65, max(0.62, sqrt(2 * (velocity + drop) / (1050 * route.scale))))
        action = .jump(Leap(start: start, end: end, riseVelocity: velocity, began: now,
                            duration: duration, facingLeft: direction < 0))
    }

    private mutating func airborneFrame(now: TimeInterval) -> Frame? {
        guard case let .jump(leap) = action else { return nil }
        let t = max(0, min(1, (now - leap.began) / leap.duration))
        if t >= 1 {
            let frame = Frame(origin: leap.end, pose: .landing, facingLeft: leap.facingLeft, phase: .land)
            action = .land(frame, until: now + 0.27)
            return frame
        }
        let fall = leap.start.y - leap.end.y
        let gravity = leap.riseVelocity + fall
        let horizontal = 1 - (1-t)*(1-t)
        let origin = CGPoint(x: leap.start.x + (leap.end.x-leap.start.x)*horizontal,
                             y: leap.start.y + t*(leap.riseVelocity-gravity*t))
        let pose: MascotPose = leap.riseVelocity - 2*gravity*t > 0 ? .jumping : .falling
        return Frame(origin: origin, pose: pose, facingLeft: leap.facingLeft, phase: .jump)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x-a.x, b.y-a.y) }
    private static func blend(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
    }
    private static func blend(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(origin: blend(a.origin,b.origin,t),
               size: CGSize(width: a.width+(b.width-a.width)*t, height: a.height+(b.height-a.height)*t))
    }
    private static func geometryChange(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX-b.minX), abs(a.minY-b.minY), abs(a.maxX-b.maxX), abs(a.maxY-b.maxY))
    }
}
