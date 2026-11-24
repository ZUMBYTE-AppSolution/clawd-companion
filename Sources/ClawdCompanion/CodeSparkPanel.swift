import AppKit

/// Tiny, mouse-transparent FX window. The cursor and the app beneath it retain
/// their normal mouse events, including clicks directly through the code tag.
@MainActor
final class CodeSparkPanel: NSPanel {
    private let ink = CodeSparkView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = ink
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ink.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func display(_ effect: CodeSpark) {
        let label = (effect.style == .hit || effect.style == .dodge) ? CodeSparkView.resultBounds(for: effect.text) : .zero
        let size = CGSize(width: ceil(max(112, label.width + 4) * effect.scale),
                          height: ceil(max(96, label.height + 54) * effect.scale))
        let rect = CGRect(x: (effect.point.x - size.width / 2).rounded(),
                          y: (effect.point.y - size.height / 2).rounded(), width: size.width, height: size.height)
        if frame != rect { setFrame(rect, display: false) }
        ink.effect = effect
        // AppKit places windows on integral coordinates. Preserve the subpoint
        // projectile center so the ink and hit test use the same world position.
        ink.centerOffset = CGPoint(x: effect.point.x - rect.midX, y: effect.point.y - rect.midY)
        ink.flipLabel = NSScreen.screens.first { $0.frame.contains(effect.point) }
            .map { effect.point.y > $0.visibleFrame.maxY - 32 * effect.scale } ?? false
        ink.needsDisplay = true
        if !isVisible { orderFrontRegardless() }
    }
}

final class CodeSparkView: NSView {
    var effect: CodeSpark?
    var centerOffset: CGPoint = .zero
    var flipLabel = false
    private let coral = NSColor(srgbRed: 0.98, green: 0.63, blue: 0.48, alpha: 1)
    private let mint = NSColor(srgbRed: 0.71, green: 0.94, blue: 0.80, alpha: 1)
    private let charcoal = NSColor(srgbRed: 0.19, green: 0.16, blue: 0.18, alpha: 0.97)
    private static let tagFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)

    static func resultBounds(for text: String) -> CGRect {
        // Shaped glyphs and font fallback give these labels language-specific widths and ascenders.
        let size = (text as NSString).size(withAttributes: [.font: tagFont])
        let width = ceil(size.width) + 12, height = max(17, ceil(size.height) + 4)
        return CGRect(x: -width/2, y: -height/2, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let spark = effect, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: bounds.midX + centerOffset.x, y: bounds.midY + centerOffset.y)
        context.scaleBy(x: spark.scale, y: spark.scale)
        switch spark.style {
        case .letter:
            let d = max(1, hypot(spark.direction.dx, spark.direction.dy))
            let dx = spark.direction.dx / d, dy = spark.direction.dy / d
            context.setShouldAntialias(false)
            mint.withAlphaComponent(0.68).setFill()
            NSRect(x: (-dx * 10).rounded(), y: (-dy * 10).rounded(), width: 2, height: 2).fill()
            if let glyph = ProjectileGeometry.glyph(for: spark.text) {
                context.setFillColor(charcoal.cgColor)
                context.fill(glyph.outline)
                context.setFillColor(mint.cgColor)
                context.fill(glyph.fill)
            }
        case .flying:
            let d = max(1, hypot(spark.direction.dx, spark.direction.dy))
            let ux = spark.direction.dx / d, uy = spark.direction.dy / d
            let body = ProjectileGeometry.tagBounds(for: spark.text)
            let offset = abs(ux) * body.width / 2 + abs(uy) * body.height / 2
            for (extra, size, alpha) in [(3.0, 3.0, 0.85), (9.0, 2.0, 0.5)] {
                coral.withAlphaComponent(alpha).setFill()
                NSRect(x: (-ux * (offset+extra)).rounded()-1, y: (-uy * (offset+extra)).rounded()-1, width: size, height: size).fill()
            }
            tag(spark.text, bounds: body, y: 0, border: coral, textColor: mint)
        case .hit:
            context.setAlpha(min(1, (1-spark.progress) * 3))
            let r = 5 + 15 * spark.progress
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let color = i.isMultiple(of: 2) ? mint : coral
                color.setFill()
                NSRect(x: (cos(angle)*r).rounded()-1, y: (sin(angle)*r).rounded()-1, width: 3, height: 3).fill()
            }
            tag(spark.text, bounds: Self.resultBounds(for: spark.text),
                y: (flipLabel ? -1 : 1) * (15 + spark.progress * 10), border: mint, textColor: mint)
        case .dodge:
            context.setAlpha(0.67 * (1-spark.progress))
            tag(spark.text, bounds: Self.resultBounds(for: spark.text), y: -9 * spark.progress, border: coral, textColor: mint)
        }
    }

    private func tag(_ text: String, bounds: CGRect, y: CGFloat, border: NSColor, textColor: NSColor) {
        let rect = bounds.offsetBy(dx: 0, dy: y)
        let radius = ProjectileGeometry.tagRadius
        let text = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.tagFont, .foregroundColor: textColor
        ]
        let size = text.size(withAttributes: attributes)
        border.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        charcoal.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius-1, yRadius: radius-1).fill()
        text.draw(at: CGPoint(x: (-size.width/2).rounded(), y: (y-size.height/2).rounded()), withAttributes: attributes)
    }
}
