import AppKit
import CoreText

enum SpeechKind: String {
    case info, success, warning, error, attention

    // Seven-cell glyphs use the same hard-edged treatment as the sprite.
    var pixels: [UInt8] {
        switch self {
        case .info: return [0x3e, 0x41, 0x55, 0x41, 0x3e, 0x18, 0x10]
        case .success: return [0, 1, 3, 0x46, 0x6c, 0x38, 0x10]
        case .warning: return [8, 0x1c, 0x36, 0x36, 0x7f, 0x77, 0x7f]
        case .error: return [0x41, 0x63, 0x36, 0x1c, 0x36, 0x63, 0x41]
        case .attention: return [8, 0x1c, 0x22, 0x22, 0x22, 0x7f, 8]
        }
    }

    var accent: NSColor {
        switch self {
        case .success: return NSColor(srgbRed: 0.62, green: 0.82, blue: 0.73, alpha: 1)
        case .warning, .attention: return NSColor(srgbRed: 0.99, green: 0.80, blue: 0.52, alpha: 1)
        case .error: return NSColor(srgbRed: 1.0, green: 0.64, blue: 0.62, alpha: 1)
        case .info: return NSColor(srgbRed: 1.0, green: 0.67, blue: 0.53, alpha: 1)
        }
    }
}

struct SpeechNotice: Equatable {
    let title: String
    let message: String
    let kind: SpeechKind

    init?(title: String, message: String, kind: String) {
        // Retain visible plain text only. Also bound scalar length for combining characters.
        func clean(_ value: String, limit: Int) -> String {
            let scalars = value.unicodeScalars.prefix(limit * 4).filter { scalar in
                // Join controls are part of Indic/Arabic shaping and emoji.
                // Keep directional isolates and marks used by mixed-language text.
                switch scalar.value {
                case 0x061C, 0x200C...0x200F, 0x2066...0x2069, 0xE0020...0xE007F: return true
                default: return !CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
                }
            }
            let compact = String(String.UnicodeScalarView(scalars)).split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            guard compact.count > limit else { return compact }
            return String(compact.prefix(limit - 1)) + "…"
        }
        let heading = clean(title, limit: 66)
        self.message = clean(message, limit: 240)
        guard !heading.isEmpty || !self.message.isEmpty else { return nil }
        self.title = heading.isEmpty ? "Claude" : heading
        self.kind = SpeechKind(rawValue: kind) ?? .info
    }
}

/// All rectangles use native global screen coordinates. The view converts the attachment
/// point to its own flipped drawing coordinates only when drawing the speech tail.
struct SpeechPlacement {
    enum Side { case above, below, left, right }
    static let tail: CGFloat = 10
    let frame: CGRect
    let side: Side
    let attachment: CGPoint

    init(body: CGSize, anchor: CGRect, visibleScreen: CGRect) {
        let screen = visibleScreen.insetBy(dx: 5, dy: 5)
        let vertical = CGSize(width: body.width, height: body.height + Self.tail)
        let horizontal = CGSize(width: body.width + Self.tail, height: body.height)
        // Aim near the actual sprite instead of the outer edge of its transparent panel.
        let xMid = anchor.midX, yMid = anchor.minY + anchor.height * 0.48
        let top = anchor.maxY - anchor.height * 0.17, bottom = anchor.minY + anchor.height * 0.09
        let left = anchor.minX + anchor.width * 0.09, right = anchor.maxX - anchor.width * 0.09
        let above = screen.maxY - top, below = bottom - screen.minY
        let roomLeft = left - screen.minX, roomRight = screen.maxX - right
        let inMiddle = above > screen.height * 0.24 && below > screen.height * 0.24
        let sidePreferred = inMiddle && min(roomLeft, roomRight) < anchor.width
        let horizontalFits = max(roomLeft, roomRight) >= horizontal.width
        if horizontalFits && (sidePreferred || max(above, below) < vertical.height) {
            side = roomLeft > roomRight ? .left : .right
        } else {
            side = above >= vertical.height || above >= below ? .above : .below
        }

        let size: CGSize
        let start: CGPoint
        switch side {
        case .above:
            size = vertical
            attachment = CGPoint(x: xMid, y: top)
            start = CGPoint(x: xMid - size.width * 0.5, y: top)
        case .below:
            size = vertical
            attachment = CGPoint(x: xMid, y: bottom)
            start = CGPoint(x: xMid - size.width * 0.5, y: bottom - size.height)
        case .left:
            size = horizontal
            attachment = CGPoint(x: left, y: yMid)
            start = CGPoint(x: left - size.width, y: yMid - size.height * 0.5)
        case .right:
            size = horizontal
            attachment = CGPoint(x: right, y: yMid)
            start = CGPoint(x: right, y: yMid - size.height * 0.5)
        }
        frame = CGRect(x: max(screen.minX, min(screen.maxX - size.width, start.x)).rounded(),
                       y: max(screen.minY, min(screen.maxY - size.height, start.y)).rounded(),
                       width: size.width, height: size.height)
    }
}

@MainActor
final class PetSpeechBubble {
    var onVisibilityChanged: ((Bool) -> Void)?
    var onPresent: (() -> Void)?
    var reducedMotion = false

    private let panel = SpeechPanel()
    private let canvas = SpeechCanvas()
    private var anchor = CGRect.zero
    private var active: SpeechNotice?
    private var pending: [SpeechNotice] = []
    private var recent: [(notice: SpeechNotice, time: TimeInterval)] = []
    private var timer: Timer?
    private var secondsLeft: TimeInterval = 0
    private var lastTick: TimeInterval = 0

    init() {
        panel.contentView = canvas
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .clawdLanguageChanged, object: nil)
    }

    @objc private func languageChanged() {
        guard let notice = active else { return }
        canvas.setNotice(notice)
        position()
    }

    func speak(title: String, message: String, kind: String, anchor: CGRect) {
        updateAnchor(anchor)
        guard let notice = SpeechNotice(title: title, message: message, kind: kind) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        recent.removeAll { now - $0.time >= 18 }
        guard active != notice, !pending.contains(notice), !recent.contains(where: { $0.notice == notice })
        else { return }
        if pending.count == 4 {
            let ordinary = pending.firstIndex { $0.kind == .info || $0.kind == .success }
            if let ordinary { pending.remove(at: ordinary) }
            else if notice.kind == .info || notice.kind == .success { return }
            else { pending.removeFirst() }
        }
        pending.append(notice)
        if active == nil { showNext() }
    }

    func updateAnchor(_ newAnchor: CGRect) {
        anchor = newAnchor
        guard !anchor.isEmpty else { return }
        if active != nil { position() }
        else if !pending.isEmpty { showNext() }
    }

    func dismissAll() {
        pending.removeAll()
        recent.removeAll()
        finish()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        let wasVisible = active != nil
        active = nil
        panel.orderOut(nil)
        canvas.clear()
        if wasVisible { onVisibilityChanged?(false) }
    }

    private func showNext() {
        guard !pending.isEmpty, !anchor.isEmpty, !NSScreen.screens.isEmpty else { finish(); return }
        let wasVisible = active != nil
        let notice = pending.removeFirst()
        active = notice
        let now = ProcessInfo.processInfo.systemUptime
        recent.append((notice, now))
        if recent.count > 12 { recent.removeFirst() }
        lastTick = now
        secondsLeft = min(22, max(5.5, 3 + Double(notice.title.count + notice.message.count) / 15))
        canvas.setNotice(notice)
        position()
        if !wasVisible {
            let animate = !reducedMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.alphaValue = animate ? 0 : 1
            panel.orderFrontRegardless()
            if animate {
                NSAnimationContext.runAnimationGroup { animation in
                    animation.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
            onVisibilityChanged?(true)
        }
        onPresent?()
        let spoken = [notice.title, notice.message].filter { !$0.isEmpty }.joined(separator: ". ")
        NSAccessibility.post(element: canvas, notification: .announcementRequested,
                             userInfo: [.announcement: spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        if timer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                MainActor.assumeIsolated { self.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if !panel.frame.contains(NSEvent.mouseLocation) { secondsLeft -= now - lastTick }
        lastTick = now
        if secondsLeft <= 0 { showNext() }
    }

    private func position() {
        let center = CGPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
                ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = canvas.bodySize(for: area.size)
        let placement = SpeechPlacement(body: size, anchor: anchor, visibleScreen: area)
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: false) }
        canvas.place(placement)
    }
}

private final class SpeechPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum PixelDialogue {
    static let font: NSFont = {
        if let url = Bundle.main.url(forResource: "ClawdDialogue", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "ClawdDialogue-Regular", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    }()

    static func paragraph(_ text: String, language: String, rightToLeft: Bool, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        style.baseWritingDirection = .natural
        style.alignment = rightToLeft ? .right : .natural
        let face: NSFont
        if text.unicodeScalars.allSatisfy({ font.coveredCharacterSet.contains($0) || $0.properties.isWhitespace }) {
            face = font
        } else {
            // Keep shaping clusters and joining scripts together in one Core Text
            // run. Its language-aware cascade supplies Indic, Han and Arabic fonts.
            face = (CTFontCreateUIFontForLanguage(.system, 15, language as CFString) as NSFont?) ?? .systemFont(ofSize: 15)
        }
        return NSAttributedString(string: text, attributes: [
            .font: face, .foregroundColor: color, .paragraphStyle: style,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language
        ])
    }

    static func drawShell(in cg: CGContext, body: CGRect, side: SpeechPlacement.Side? = nil, tip: CGFloat = 0) {
        cg.saveGState()
        cg.setShouldAntialias(false)
        let outline = CGColor(srgbRed: 0.21, green: 0.14, blue: 0.15, alpha: 1)
        let trim = CGColor(srgbRed: 0.91, green: 0.57, blue: 0.44, alpha: 1)
        let fill = CGColor(srgbRed: 0.17, green: 0.13, blue: 0.15, alpha: 1)
        let tail = SpeechPlacement.tail
        let horizontalTail = side == .left || side == .right
        let center = horizontalTail
            ? max(body.minY + 14, min(body.maxY - 14, tip))
            : max(body.minX + 14, min(body.maxX - 14, tip))
        func shell(inset: CGFloat, color: CGColor) {
            let r = body.insetBy(dx: inset, dy: inset)
            guard r.width > 12, r.height > 12 else { return }
            cg.setFillColor(color)
            cg.fill([r.insetBy(dx: 6, dy: 0), r.insetBy(dx: 2, dy: 2), r.insetBy(dx: 0, dy: 6)])
            guard let side else { return }
            // The rows overlap the card face so the tail shares one unbroken keyline.
            for row in -2..<5 {
                let d = CGFloat(row) * 2
                let halfWidth = max(0, 10 - max(0, d) - inset)
                guard halfWidth > 0, d < tail - inset else { continue }
                let strip: CGRect
                switch side {
                case .above: strip = CGRect(x: center - halfWidth, y: body.maxY + d, width: 2*halfWidth, height: 2)
                case .below: strip = CGRect(x: center - halfWidth, y: body.minY - d - 2, width: 2*halfWidth, height: 2)
                case .left: strip = CGRect(x: body.maxX + d, y: center - halfWidth, width: 2, height: 2*halfWidth)
                case .right: strip = CGRect(x: body.minX - d - 2, y: center - halfWidth, width: 2, height: 2*halfWidth)
                }
                cg.fill(strip)
            }
        }
        shell(inset: 0, color: outline)
        shell(inset: 2, color: trim)
        shell(inset: 4, color: fill)
        cg.restoreGState()
    }
}

final class SpeechCanvas: NSView {
    override var isFlipped: Bool { true }
    private var heading = NSAttributedString()
    private var detail = NSAttributedString()
    private var kind: SpeechKind = .info
    private var cachedSize: (screen: CGSize, body: CGSize)?
    private var side = SpeechPlacement.Side.above
    private var tip = CGFloat.zero
    private let padding: CGFloat = 14
    private let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
    func setNotice(_ notice: SpeechNotice) {
        kind = notice.kind
        let language = L10n.code, rtl = L10n.isRTL
        heading = PixelDialogue.paragraph(notice.title, language: language, rightToLeft: rtl, color: kind.accent)
        let cream = NSColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 1)
        detail = PixelDialogue.paragraph(notice.message, language: language, rightToLeft: rtl, color: cream)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel([notice.title, notice.message].filter { !$0.isEmpty }.joined(separator: ". "))
        cachedSize = nil
        needsDisplay = true
    }

    func clear() {
        heading = NSAttributedString()
        detail = NSAttributedString()
        cachedSize = nil
        setAccessibilityLabel(nil)
    }

    private func textHeight(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        guard string.length > 0 else { return 0 }
        return ceil(string.boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                        options: options).height)
    }

    func bodySize(for screen: CGSize) -> CGSize {
        if cachedSize?.screen == screen, let body = cachedSize?.body { return body }
        let limit = min(330, screen.width - 10 - SpeechPlacement.tail)
        let ideal = max(heading.size().width + 22, detail.size().width) + 2 * padding
        let width = max(2, floor(min(limit, max(128, ceil(ideal / 2) * 2)) / 2) * 2)
        let textWidth = width - 2 * padding
        let titleHeight = max(16, textHeight(heading, width: textWidth - 22))
        let bodyHeight = textHeight(detail, width: textWidth)
        let idealHeight = 2 * padding + titleHeight + (bodyHeight > 0 ? 6 + bodyHeight : 0)
        let height = min(ceil(idealHeight / 2) * 2, screen.height - 10 - SpeechPlacement.tail)
        let body = CGSize(width: width, height: max(2, height))
        cachedSize = (screen, body)
        return body
    }

    func place(_ p: SpeechPlacement) {
        let position: CGFloat
        switch p.side {
        case .above, .below: position = p.attachment.x - p.frame.minX
        case .left, .right: position = p.frame.maxY - p.attachment.y
        }
        let snapped = (position / 2).rounded() * 2
        if side != p.side || tip != snapped {
            side = p.side
            tip = snapped
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        var body = bounds
        let tail = SpeechPlacement.tail
        switch side {
        case .above: body.size.height -= tail
        case .below: body.origin.y += tail; body.size.height -= tail
        case .left: body.size.width -= tail
        case .right: body.origin.x += tail; body.size.width -= tail
        }

        PixelDialogue.drawShell(in: cg, body: body, side: side, tip: tip)
        cg.saveGState()
        cg.setShouldAntialias(false)
        let x = body.minX + padding, y = body.minY + padding
        let rtl = L10n.isRTL
        let iconX = rtl ? body.maxX - padding - 14 : x
        cg.setFillColor(kind.accent.cgColor)
        for (row, bits) in kind.pixels.enumerated() {
            for col in 0..<7 where bits & (1 << (6 - col)) != 0 {
                cg.fill(CGRect(x: iconX + CGFloat(col)*2, y: y + CGFloat(row)*2 + 1, width: 2, height: 2))
            }
        }
        cg.restoreGState()

        let textWidth = body.width - 2 * padding
        let titleHeight = max(16, textHeight(heading, width: textWidth - 22))
        heading.draw(with: CGRect(x: rtl ? x : x + 22, y: y, width: max(1, textWidth - 22), height: titleHeight), options: options)
        if detail.length > 0 {
            let top = y + titleHeight + 6
            detail.draw(with: CGRect(x: x, y: top, width: max(1, textWidth),
                                     height: max(1, body.maxY - top - padding)), options: options)
        }
    }
}
