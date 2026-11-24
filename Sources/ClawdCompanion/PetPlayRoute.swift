import CoreGraphics
import Foundation

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
}

/// A whole sprite stays inside its display, except while walking through the shared
/// edge into a neighbouring display. Coordinates are global AppKit points.
struct PetPlayRoute {
    let stops: [CGPoint]
    let length: CGFloat
    private let spans: [CGFloat]

    init?(_ start: CGPoint, to proposedEnd: CGPoint, petSize: CGSize, screens: [CGRect]) {
        guard let first = Self.screen(containing: start, among: screens),
              let last = Self.screen(containing: proposedEnd, among: screens) else { return nil }
        let end = Self.clamp(proposedEnd, size: petSize, inside: last)
        var points = [start]
        if first != last {
            guard let seam = Self.crossing(first, last, petSize, start, end) else { return nil }
            points += seam
        }
        points.append(end)
        stops = points
        spans = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        length = spans.reduce(0, +)
    }

    func point(at distance: CGFloat) -> CGPoint {
        var remaining = max(0, distance)
        for (i, span) in spans.enumerated() where span > 0.001 {
            if remaining < span {
                let t = remaining / span
                return CGPoint(x: stops[i].x + (stops[i + 1].x - stops[i].x) * t,
                               y: stops[i].y + (stops[i + 1].y - stops[i].y) * t)
            }
            remaining -= span
        }
        return stops.last!
    }

    static func screen(containing center: CGPoint, among screens: [CGRect]) -> CGRect? {
        func distance(_ area: CGRect) -> CGFloat {
            hypot(max(0, area.minX - center.x, center.x - area.maxX),
                  max(0, area.minY - center.y, center.y - area.maxY))
        }
        return screens.min { distance($0) < distance($1) }
    }

    static func clamp(_ center: CGPoint, size: CGSize, inside screen: CGRect) -> CGPoint {
        let dx = min(screen.width / 2, size.width / 2 + 3)
        let dy = min(screen.height / 2, size.height / 2 + 3)
        return CGPoint(x: max(screen.minX + dx, min(screen.maxX - dx, center.x)),
                       y: max(screen.minY + dy, min(screen.maxY - dy, center.y)))
    }

    private static func crossing(_ a: CGRect, _ b: CGRect, _ size: CGSize,
                                 _ start: CGPoint, _ end: CGPoint) -> [CGPoint]? {
        // A menu bar or Dock can inset one visible frame at an otherwise continuous seam.
        let gapLimit: CGFloat = 80
        let yMin = max(a.minY, b.minY) + size.height / 2 + 3
        let yMax = min(a.maxY, b.maxY) - size.height / 2 - 3
        let xMin = max(a.minX, b.minX) + size.width / 2 + 3
        let xMax = min(a.maxX, b.maxX) - size.width / 2 - 3
        if yMin <= yMax {
            let right = b.midX > a.midX
            let exit = right ? a.maxX : a.minX, entry = right ? b.minX : b.maxX
            if abs(exit - entry) <= gapLimit {
                let y = min(yMax, max(yMin, (start.y + end.y) / 2))
                return [CGPoint(x: exit, y: y), CGPoint(x: entry, y: y)]
            }
        }
        if xMin <= xMax {
            let up = b.midY > a.midY
            let exit = up ? a.maxY : a.minY, entry = up ? b.minY : b.maxY
            if abs(exit - entry) <= gapLimit {
                let x = min(xMax, max(xMin, (start.x + end.x) / 2))
                return [CGPoint(x: x, y: exit), CGPoint(x: x, y: entry)]
            }
        }
        return nil
    }
}

/// The code token follows one locked point. Collision tests both moving objects
/// in relative coordinates, including the space between two animation frames.
struct CodeFlight {
    let start: CGPoint
    let target: CGPoint
    let distance: CGFloat
    let duration: TimeInterval
    let lift: CGFloat

    init(start: CGPoint, target: CGPoint, scale: CGFloat, arcing: Bool = true) {
        self.start = start
        self.target = target
        distance = start.distance(to: target)
        duration = min(1.7, max(0.68, distance / (440 * scale)))
        lift = arcing ? min(40 * scale, distance * 0.10) : 0
    }

    init(letterFrom muzzle: CGPoint, through aim: CGPoint, scale: CGFloat) {
        let dx = aim.x - muzzle.x, dy = aim.y - muzzle.y
        let length = hypot(dx, dy)
        // Let even an open glyph such as C cross the aim point completely.
        let margin = length > 0 ? 10 * scale / length : 0
        let end = CGPoint(x: aim.x + dx * margin, y: aim.y + dy * margin)
        self.init(start: muzzle, target: end, scale: scale, arcing: false)
    }

    func point(at progress: CGFloat) -> CGPoint {
        let t = min(1, max(0, progress))
        return CGPoint(x: start.x + (target.x - start.x) * t,
                       y: start.y + (target.y - start.y) * t + sin(t * .pi) * lift)
    }

    /// A frame can arrive after the projectile has expired. Only the portion
    /// of the cursor segment during the projectile's actual flight can hit.
    func sample(now: Double, release: Double, previous: Double, mouseFrom old: CGPoint,
                mouseTo new: CGPoint) -> (point: CGPoint, mouse: CGPoint, ended: Bool) {
        let end = release + duration
        let time = min(now, end)
        let fraction = now > previous ? min(1, max(0, (time - previous) / (now - previous))) : 1
        let mouse = CGPoint(x: old.x + (new.x - old.x) * fraction, y: old.y + (new.y - old.y) * fraction)
        return (point(at: (time - release) / duration), mouse, now >= end)
    }
}
