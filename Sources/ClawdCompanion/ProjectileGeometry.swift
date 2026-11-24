import CoreGraphics
import Foundation

/// Ink in AppKit points, relative to the projectile's center. The FX view
/// paints these same shapes. Transparent space and the cosmetic trail stay clear.
enum ProjectileGeometry {
    struct Glyph {
        let fill: [CGRect]
        let outline: [CGRect]
    }

    // Top-to-bottom row masks of the uppercase letters in ClawdDialogue.ttf.
    // Run rectangles are cached once and shared by drawing and swept hit tests.
    private static let alphabet: [String: Glyph] = {
        let rows: [[UInt8]] = [
            [14,17,17,31,17,17,17], [30,17,17,30,17,17,30], [14,17,16,16,16,17,14],
            [28,18,17,17,17,18,28], [31,16,16,30,16,16,31], [31,16,16,30,16,16,16],
            [14,17,16,23,17,17,15], [17,17,17,31,17,17,17], [14,4,4,4,4,4,14],
            [7,2,2,2,18,18,12], [17,18,20,24,20,18,17], [16,16,16,16,16,16,31],
            [17,27,21,21,17,17,17], [17,25,25,21,19,19,17], [14,17,17,17,17,17,14],
            [30,17,17,30,16,16,16], [14,17,17,17,21,18,13], [30,17,17,30,20,18,17],
            [15,16,16,14,1,1,30], [31,4,4,4,4,4,4], [17,17,17,17,17,17,14],
            [17,17,17,17,17,10,4], [17,17,17,21,21,21,10], [17,17,10,4,10,17,17],
            [17,17,10,4,4,4,4], [31,1,2,4,8,16,31]
        ]
        let cell: CGFloat = 2
        return Dictionary(uniqueKeysWithValues: zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ", rows).map { letter, mask in
            var runs: [CGRect] = []
            for (row, bits) in mask.enumerated() {
                var start: Int?
                for column in 0...5 {
                    let on = column < 5 && bits & (16 >> column) != 0
                    if on && start == nil { start = column }
                    if !on, let first = start {
                        runs.append(CGRect(x: (CGFloat(first) - 2.5) * cell, y: CGFloat(3 - row) * cell - cell / 2,
                                           width: CGFloat(column - first) * cell, height: cell))
                        start = nil
                    }
                }
            }
            return (String(letter), Glyph(fill: runs, outline: runs.map { $0.insetBy(dx: -0.5, dy: -0.5) }))
        })
    }()

    static func glyph(for word: String) -> Glyph? { alphabet[word] }

    static let tagRadius: CGFloat = 4.5

    static func tagBounds(for word: String) -> CGRect {
        let width = ceil(CGFloat(word.count) * 6.2) + 13
        return CGRect(x: -width / 2, y: -8.5, width: width, height: 17)
    }

    /// Tests the segment between consecutive relative cursor positions. Both
    /// the pointer and projectile can move between two display updates.
    static func touches(word: String, letter: Bool, scale: CGFloat, from old: CGPoint, to new: CGPoint,
                        mouseFrom a: CGPoint, mouseTo b: CGPoint) -> Bool {
        guard scale.isFinite && scale > 0 else { return false }
        let start = CGPoint(x: (a.x - old.x) / scale, y: (a.y - old.y) / scale)
        let end = CGPoint(x: (b.x - new.x) / scale, y: (b.y - new.y) / scale)
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return false }
        if letter {
            guard let glyph = glyph(for: word) else { return false }
            guard intersects(CGRect(x: -5.5, y: -7.5, width: 11, height: 15), start, end) else { return false }
            return glyph.outline.contains { intersects($0, start, end) }
        }
        let rect = tagBounds(for: word), radius = tagRadius
        guard intersects(rect, start, end) else { return false }
        if intersects(rect.insetBy(dx: radius, dy: 0), start, end)
            || intersects(rect.insetBy(dx: 0, dy: radius), start, end) { return true }

        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        for x in [rect.minX + radius, rect.maxX - radius] {
            for y in [rect.minY + radius, rect.maxY - radius] {
                let t = lengthSquared > 0 ? min(1, max(0, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared)) : 0
                let fx = start.x + t * dx - x, fy = start.y + t * dy - y
                if fx * fx + fy * fy <= radius * radius { return true }
            }
        }
        return false
    }

    private static func intersects(_ rect: CGRect, _ start: CGPoint, _ end: CGPoint) -> Bool {
        var enter: CGFloat = 0, leave: CGFloat = 1
        func clip(_ first: CGFloat, _ last: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> Bool {
            let delta = last - first
            if delta == 0 { return first >= lower && first <= upper }
            let t1 = (lower - first) / delta, t2 = (upper - first) / delta
            enter = max(enter, min(t1, t2))
            leave = min(leave, max(t1, t2))
            return enter <= leave
        }
        return clip(start.x, end.x, rect.minX, rect.maxX) && clip(start.y, end.y, rect.minY, rect.maxY)
    }
}
