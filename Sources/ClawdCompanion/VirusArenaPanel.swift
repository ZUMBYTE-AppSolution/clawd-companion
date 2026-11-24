import AppKit
import CoreText

extension VirusArcade {
    mutating func hit(at point: CGPoint) {
        guard let target = VirusArenaPixels.target(at: point, in: frame)?.target else { return }
        switch target {
        case .enemy(let id): hit(enemyID: id)
        case .pickup(let id): collect(pickupID: id)
        }
    }
}

/// The same pixel rows drive painting and mouse targeting. Rows are stored top first,
/// while the simulation and AppKit both measure y from the bottom of the arena.
enum VirusArenaPixels {
    static let size = CGSize(width: 300, height: 160)
    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static let ink = rgb(0x312936), cream = rgb(0xffedc9), coral = rgb(0xef9278)
    private static let mint = rgb(0x97d7b3), gold = rgb(0xf8c477), blue = rgb(0x98cddd)
    private static let plum = rgb(0x79516f), muted = rgb(0x584550)

    private struct Palette {
        let shadow: CGColor, body: CGColor, light: CGColor
        func color(_ value: UInt8, hurt: Bool) -> CGColor {
            switch value {
            case 98: return hurt ? coral : shadow // b
            case 99: return hurt ? cream : body   // c
            case 104: return hurt ? cream : light // h
            case 119: return cream                // w
            case 103: return gold                 // g
            case 114: return coral                // r
            default: return ink                   // x
            }
        }
    }
    private static let bugColors = Palette(shadow: rgb(0x66755f), body: rgb(0x96bc83), light: rgb(0xd0e9a8))
    private static let wormColors = Palette(shadow: rgb(0x855375), body: rgb(0xbb83ad), light: rgb(0xe7accc))
    private static let sporeColors = Palette(shadow: rgb(0x457e83), body: rgb(0x6eada8), light: rgb(0xb4e2c7))
    private static let bossColors = Palette(shadow: plum, body: rgb(0xb86c90), light: rgb(0xe89abb))
    private static let healColors = Palette(shadow: rgb(0x628a73), body: mint, light: cream)
    private static let shieldColors = Palette(shadow: rgb(0x508b9c), body: blue, light: cream)
    private static let rapidColors = Palette(shadow: rgb(0xb27c51), body: gold, light: cream)

    private struct Run {
        let col: Int, length: Int, value: UInt8
    }
    private struct Sprite {
        let width: Int, rows: [[UInt8]], runs: [[Run]]
        init(_ source: [String]) {
            rows = source.map { Array($0.utf8) }
            width = rows.map(\.count).max() ?? 0
            runs = rows.map { row in
                var groups: [Run] = []
                var start = 0
                while start < row.count {
                    let value = row[start]
                    var end = start + 1
                    while end < row.count && row[end] == value { end += 1 }
                    if value != 46 { groups.append(Run(col: start, length: end-start, value: value)) }
                    start = end
                }
                return groups
            }
        }
        func layout(center: CGPoint, radius: CGFloat) -> (origin: CGPoint, step: CGFloat) {
            let step = 2 * radius / CGFloat(max(width, rows.count))
            return (CGPoint(x: (center.x - step * CGFloat(width) / 2).rounded(),
                            y: (center.y + step * CGFloat(rows.count) / 2).rounded()), step)
        }
        func paint(in ctx: CGContext, center: CGPoint, radius: CGFloat, colors: Palette, hurt: Bool = false) {
            let (top, step) = layout(center: center, radius: radius)
            for (row, runs) in runs.enumerated() {
                for run in runs {
                    ctx.setFillColor(colors.color(run.value, hurt: hurt))
                    ctx.fill(CGRect(x: top.x + CGFloat(run.col) * step, y: top.y - CGFloat(row + 1) * step,
                                    width: CGFloat(run.length) * step, height: step))
                }
            }
        }
        /// One solid horizontal strip. A transparent corner, antenna gap or health bar
        /// never becomes an input surface, even when the pointer leaves between ticks.
        func strip(at point: CGPoint, center: CGPoint, radius: CGFloat) -> CGRect? {
            let (top, step) = layout(center: center, radius: radius)
            guard step > 0 else { return nil }
            let row = Int(ceil((top.y - point.y) / step)) - 1
            let col = Int(floor((point.x - top.x) / step))
            guard rows.indices.contains(row), rows[row].indices.contains(col), rows[row][col] != 46 else { return nil }
            var start = col, end = col + 1
            while start > 0 && rows[row][start - 1] != 46 { start -= 1 }
            while end < rows[row].count && rows[row][end] != 46 { end += 1 }
            return CGRect(x: top.x + CGFloat(start) * step, y: top.y - CGFloat(row + 1) * step,
                          width: CGFloat(end - start) * step, height: step)
        }
    }

    private static let bugs = [
        Sprite(["..x...x..", ".xhx.xhx.", "..xxxxx..", ".xhhccbx.", "xbwxxwbcx", ".xccccbx.", "..xbbbx..", ".xx...xx."]),
        Sprite([".x.....x.", "..x...x..", "..xxxxx..", ".xhhccbx.", "xbwxxwbcx", ".xccccbx.", ".xxbbbxx.", "x..xxx..x"])
    ]
    private static let worms = [
        Sprite([".......xx..", "......xhcx.", ".xxxx..xcbx", "xhhccx..xcx", "xwxxwxx.xbx", "xcccbccxcbx", ".xbbccbbbx.", "..xxxxxxx.."]),
        Sprite(["...........", ".xxxx...xx.", "xhhccx.xhcx", "xwxxwxx.xcx", "xcccbccxcbx", ".xbbccbbbx.", "..xxxxxxx..", "..........."])
    ]
    private static let spores = [
        Sprite(["....xhx....", ".xx..x..xx.", ".xhxxxxxhx.", "..xhcccbx..", ".xbwwxxcbx.", "xhcwxwxccbx", ".xbwwwcbbx.", "..xbbbbbx..", ".xhxxxxxhx.", ".xx..x..xx.", "....xbx...."]),
        Sprite([".....x.....", "..x.xhx.x..", ".xhxxxxxhx.", "..xhcccbx..", "xxbwwxxcbxx", ".hcwxwxccb.", "xxbwwwcbbxx", "..xbbbbbx..", ".xhxxxxxhx.", "..x.xbx.x..", ".....x....."])
    ]
    private static let monarchs = [
        Sprite([".......x.......", "...x..xgx..x...", "..xgxxgwgxxgx..", "...xgggggggx...", "...xgrgggrgx...", "...xxxxxxxxx...", ".xxhhccccccbbx.", "xhhwwxwwxwwcbcx", ".xcwxwwxwwxcbx.", "..xcccbbccbbx..", ".xbxxwwwxxbcbx.", "xbx.xxbbxx.xcbx", ".x.xbx..xbx..x.", "..xx......xx..."]),
        Sprite([".......x.......", "...x..xgx..x...", "..xgxxgwgxxgx..", "...xgggggggx...", "...xgrgggrgx...", "...xxxxxxxxx...", ".xxhhccccccbbx.", "xhhwwxwwxwwcbcx", ".xcwxwwxwwxcbx.", "..xcccbbccbbx..", ".xbxxwwwxxbcbx.", ".xbx.xbbx.xbx..", "..xbx.xx.xbx...", ".xx........xx.."])
    ]
    private static let restore = Sprite(["..xxxxx..", ".xhcccxx.", "xhccwccbx", "xccwwwcbx", "xcccwccbx", ".xbcccxx.", "..xxxxx.."])
    private static let shield = Sprite([".xxxxxxx.", "xhwwcccbx", "xhwccccbx", "xccccccbx", ".xccbcbx.", "..xcbbx..", "...xbx...", "....x...."])
    private static let rapid = Sprite(["...xxxxx.", "..xgggx..", ".xgwgx...", "xgggggggx", ".xxxgggx.", "...xggx..", "..xggx...", "..xxx...."])
    private static let heart = Sprite([".xx.xx.", "xrrxrrx", "xhrcrrx", ".xrrrx.", "..xrx..", "...x..."])
    private static func enemyArt(_ kind: VirusArcade.Kind, beat: Int) -> (Sprite, Palette) {
        switch kind {
        case .bug: return (bugs[beat], bugColors)
        case .worm: return (worms[beat], wormColors)
        case .spore: return (spores[beat], sporeColors)
        case .boss: return (monarchs[beat], bossColors)
        }
    }
    private static func pickupArt(_ kind: VirusArcade.PickupKind) -> (Sprite, Palette) {
        switch kind {
        case .restore: return (restore, healColors)
        case .shield: return (shield, shieldColors)
        case .rapidFire: return (rapid, rapidColors)
        }
    }
    private static func beat(_ time: Double, id: Int) -> Int { (Int(time * 3) + id) & 1 }
    static func enemyStrip(_ kind: VirusArcade.Kind, at point: CGPoint, center: CGPoint,
                           radius: CGFloat, time: Double, id: Int) -> CGRect? {
        enemyArt(kind, beat: beat(time, id: id)).0.strip(at: point, center: center, radius: radius)
    }
    static func pickupStrip(_ kind: VirusArcade.PickupKind, at point: CGPoint, center: CGPoint,
                            radius: CGFloat) -> CGRect? {
        pickupArt(kind).0.strip(at: point, center: center, radius: radius)
    }
    enum Target: Equatable { case enemy(Int), pickup(Int) }
    struct Hit {
        let target: Target
        let strip: CGRect
    }
    static func target(at point: CGPoint, in frame: VirusArcade.Frame) -> Hit? {
        for item in frame.pickups.reversed() {
            if let strip = pickupStrip(item.kind, at: point, center: item.position, radius: item.radius) {
                return Hit(target: .pickup(item.id), strip: strip)
            }
        }
        for enemy in frame.enemies.reversed() {
            if let strip = enemyStrip(enemy.kind, at: point, center: enemy.position, radius: enemy.radius,
                                      time: frame.time, id: enemy.id) {
                return Hit(target: .enemy(enemy.id), strip: strip)
            }
        }
        return nil
    }
    static func draw(_ frame: VirusArcade.Frame, in ctx: CGContext, mirrored: Bool = false) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(false)
        ctx.saveGState()
        if mirrored {
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        heroEffects(frame, in: ctx)
        for shot in frame.shots {
            let x = shot.position.x.rounded(), y = shot.position.y.rounded()
            if shot.hostile {
                fill(ctx, ink, x-3, y-1, 6, 3)
                fill(ctx, ink, x-1, y-3, 3, 6)
                fill(ctx, coral, x-2, y, 4, 1)
                fill(ctx, gold, x, y-2, 1, 4)
            } else {
                fill(ctx, ink, x-4, y-2, 8, 4)
                fill(ctx, mint, x-3, y-1, 5, 2)
                fill(ctx, cream, x+2, y-1, 1, 2)
            }
        }
        for enemy in frame.enemies {
            let (sprite, palette) = enemyArt(enemy.kind, beat: beat(frame.time, id: enemy.id))
            sprite.paint(in: ctx, center: enemy.position, radius: enemy.radius, colors: palette, hurt: enemy.hurt > 0.55)
            let boss = enemy.kind == .boss
            let width = boss ? max(36, enemy.radius*2) : max(11, enemy.radius*1.7)
            let rect = CGRect(x: (enemy.position.x - width/2).rounded(),
                              y: (enemy.position.y - enemy.radius - 6).rounded(), width: width.rounded(), height: boss ? 5 : 4)
            meter(ctx, in: rect, hp: enemy.hp, maxHP: enemy.maxHP, color: boss ? gold : palette.light)
            if enemy.hurt > 0.25 {
                let d = enemy.radius + 2 + 3 * (1 - enemy.hurt)
                fill(ctx, cream, (enemy.position.x - d).rounded(), (enemy.position.y + 3).rounded(), 2, 1)
                fill(ctx, gold, (enemy.position.x + d).rounded(), (enemy.position.y - 2).rounded(), 1, 2)
            }
        }
        for item in frame.pickups {
            let (sprite, palette) = pickupArt(item.kind)
            sprite.paint(in: ctx, center: item.position, radius: item.radius, colors: palette)
            let d = item.radius + 1
            let shine = beat(frame.time, id: item.id) == 0
            let x = (item.position.x + (shine ? d : -d)).rounded(), y = (item.position.y + d - 1).rounded()
            fill(ctx, cream, x, y, 1, 3)
            fill(ctx, cream, x-1, y+1, 3, 1)
        }
        ctx.restoreGState()
        hud(frame, in: ctx, mirrored: mirrored)
    }

    private static func fill(_ ctx: CGContext, _ color: CGColor, _ x: CGFloat, _ y: CGFloat,
                             _ w: CGFloat, _ h: CGFloat) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    static func healthFill(width: CGFloat, hp: Int, maxHP: Int) -> CGFloat {
        guard maxHP > 0, hp > 0, width >= 1 else { return 0 }
        return min(width, max(1, (width * CGFloat(hp) / CGFloat(maxHP)).rounded()))
    }
    private static func meter(_ ctx: CGContext, in rect: CGRect, hp: Int, maxHP: Int, color: CGColor) {
        ctx.setFillColor(ink)
        ctx.fill(rect)
        let bar = rect.insetBy(dx: 1, dy: 1)
        ctx.setFillColor(muted)
        ctx.fill(bar)
        fill(ctx, color, bar.minX, bar.minY, healthFill(width: bar.width, hp: hp, maxHP: maxHP), bar.height)
    }
    private static func heroEffects(_ frame: VirusArcade.Frame, in ctx: CGContext) {
        let x = frame.hero.x.rounded(), y = frame.hero.y.rounded()
        if frame.shield > 0 {
            for side: CGFloat in [-1, 1] {
                fill(ctx, blue, x + side*20, y-5, 2, 11)
                fill(ctx, blue, x + side*18, y+6, 2, 4)
                fill(ctx, blue, x + side*18, y-9, 2, 4)
                fill(ctx, blue, x + side*15, y+10, 3, 2)
                fill(ctx, blue, x + side*15, y-11, 3, 2)
            }
        }
        if frame.heroHurt > 0.15 {
            let d = CGFloat(18 + (1-frame.heroHurt)*4)
            fill(ctx, coral, (x-d).rounded(), y+9, 3, 2)
            fill(ctx, gold, x+4, (y+d).rounded(), 2, 3)
            fill(ctx, coral, (x+d).rounded(), y-6, 2, 2)
        }
        if frame.heroFiring && frame.rapidFire > 0 {
            fill(ctx, gold, x+20, y+1, 4, 2)
            fill(ctx, cream, x+24, y+4, 2, 1)
        }
    }
    private static let hudFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
    private static func textLine(_ string: String) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: string,
            attributes: [.font: hudFont, .foregroundColor: NSColor(cgColor: cream) ?? .white]))
    }
    private static func printLine(_ line: CTLine, in ctx: CGContext, x: CGFloat, y: CGFloat) {
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.setShouldAntialias(true)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
    private static func panel(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        fill(ctx, ink, x+2, y, w-4, h)
        fill(ctx, ink, x, y+2, w, h-4)
    }
    private static func hud(_ frame: VirusArcade.Frame, in ctx: CGContext, mirrored: Bool) {
        let x: CGFloat = mirrored ? size.width - 69 : 7
        let y: CGFloat = 140
        panel(ctx, x: x, y: y, w: 62, h: 15)
        heart.paint(in: ctx, center: CGPoint(x: x + 8, y: y + 8), radius: 4.5, colors: rapidColors)
        let hpColor = frame.playerHP <= 25 ? coral : mint
        meter(ctx, in: CGRect(x: x+15, y: y+5, width: 24, height: 5), hp: frame.playerHP, maxHP: 100, color: hpColor)
        printLine(textLine("\(frame.playerHP)%"), in: ctx, x: x+40, y: y+4)
        var badgeX = x
        for (kind, seconds) in [(VirusArcade.PickupKind.shield, frame.shield), (.rapidFire, frame.rapidFire)] where seconds > 0 {
            let (symbol, palette) = pickupArt(kind)
            panel(ctx, x: badgeX, y: y-12, w: 25, h: 11)
            symbol.paint(in: ctx, center: CGPoint(x: badgeX+6, y: y-6), radius: 4.5, colors: palette)
            printLine(textLine("\(Int(ceil(seconds)))"), in: ctx, x: badgeX+13, y: y-9)
            badgeX += 27
        }
        let phase = frame.phase == .boss ? L("Boss") : L("Welle {0}", String(frame.wave))
        let line = textLine(phase)
        let width = CGFloat(ceil(CTLineGetTypographicBounds(line, nil, nil, nil))) + 10
        let phaseX = mirrored ? 7 : size.width-7-width
        panel(ctx, x: phaseX, y: y, w: width, h: 15)
        printLine(line, in: ctx, x: phaseX+5, y: y+4)
    }
}

/// Projection shared by drawing and input, also on displays whose origins are negative.
struct VirusArenaProjection {
    let rect: CGRect
    let mirrored: Bool
    func worldPoint(_ screen: CGPoint) -> CGPoint {
        let x = (screen.x-rect.minX) / rect.width * VirusArenaPixels.size.width
        return CGPoint(x: mirrored ? VirusArenaPixels.size.width - x : x,
                       y: (screen.y-rect.minY) / rect.height * VirusArenaPixels.size.height)
    }
    func screenRect(_ world: CGRect) -> CGRect {
        let x = mirrored ? VirusArenaPixels.size.width-world.maxX : world.minX
        let sx = rect.width / VirusArenaPixels.size.width, sy = rect.height / VirusArenaPixels.size.height
        return CGRect(x: rect.minX + x*sx, y: rect.minY + world.minY*sy,
                      width: world.width*sx, height: world.height*sy)
    }
}

@MainActor
final class VirusArenaPanel {
    var onTap: ((CGPoint) -> Void)?
    var onStrike: ((Int) -> Void)?
    var onPickup: ((Int) -> Void)?
    private let canvas = VirusArenaView()
    private let paintWindow = ArcadeWindow()
    private let hitWindow = ArcadeWindow()
    private let hitView = VirusTargetView()
    private var projection: VirusArenaProjection?

    init() {
        paintWindow.contentView = canvas
        paintWindow.ignoresMouseEvents = true
        canvas.setAccessibilityElement(false)
        hitWindow.contentView = hitView
        // WindowServer can pass fully transparent pixels through. This near-transparent
        // input strip is only ever placed on top of pixels already painted by the sprite.
        hitWindow.backgroundColor = .black.withAlphaComponent(0.02)
        hitView.onMouseDown = { [weak self] point in self?.tap(at: point) }
    }
    func display(_ frame: VirusArcade.Frame, in screenRect: CGRect, mirrored: Bool = false, acceptsInput: Bool = true) {
        guard !screenRect.isEmpty else { hide(); return }
        if paintWindow.frame != screenRect { paintWindow.setFrame(screenRect, display: false) }
        let projection = VirusArenaProjection(rect: paintWindow.frame, mirrored: mirrored)
        self.projection = projection
        canvas.state = frame
        canvas.mirrored = mirrored
        canvas.needsDisplay = true
        if !paintWindow.isVisible { paintWindow.orderFrontRegardless() }

        let pointer = NSEvent.mouseLocation
        guard acceptsInput, projection.rect.contains(pointer),
              let hit = VirusArenaPixels.target(at: projection.worldPoint(pointer), in: frame) else {
            if hitWindow.isVisible { hitWindow.orderOut(nil) }
            return
        }
        let strip = projection.screenRect(hit.strip)
        if hitWindow.frame != strip { hitWindow.setFrame(strip, display: false) }
        if !hitWindow.isVisible { hitWindow.orderFrontRegardless() }
    }
    private func tap(at screenPoint: CGPoint) {
        guard let projection, let frame = canvas.state else { return }
        let point = projection.worldPoint(screenPoint)
        guard let hit = VirusArenaPixels.target(at: point, in: frame) else { return }
        switch hit.target {
        case .enemy(let id):
            if let onStrike { onStrike(id) } else { onTap?(point) }
        case .pickup(let id):
            if let onPickup { onPickup(id) } else { onTap?(point) }
        }
    }
    func hide() {
        if paintWindow.isVisible { paintWindow.orderOut(nil) }
        if hitWindow.isVisible { hitWindow.orderOut(nil) }
        projection = nil
        canvas.state = nil
    }
}

@MainActor
private final class ArcadeWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VirusArenaView: NSView {
    var state: VirusArcade.Frame?
    var mirrored = false
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        guard let state else { return }
        ctx.saveGState()
        ctx.scaleBy(x: bounds.width / VirusArenaPixels.size.width, y: bounds.height / VirusArenaPixels.size.height)
        VirusArenaPixels.draw(state, in: ctx, mirrored: mirrored)
        ctx.restoreGState()
    }
}

@MainActor
private final class VirusTargetView: NSView {
    var onMouseDown: ((CGPoint) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onMouseDown?(window.convertPoint(toScreen: event.locationInWindow))
    }
}
