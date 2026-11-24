import AppKit

/// A separate sprite sheet for the 18-point menubar. All geometry lands on whole points,
/// including the transparent facial features macOS uses in both menu bar appearances.
enum MenuMascotPixels {
    static let size = CGSize(width: 24, height: 18)

    // Long idle frames and short blinks keep the character alive without a polling timer.
    static func durations(for pose: MascotPose) -> [TimeInterval] {
        switch pose {
        case .idle: return [4.0, 0.14, 0.7, 1.5]
        case .sleeping: return [1.35, 0.75, 1.2, 0.75]
        case .thinking: return [0.6, 0.45, 0.47, 0.67]
        case .typing: return [0.28, 0.25, 0.27, 0.32]
        case .walking, .climbing, .rappelling: return [0.21, 0.22, 0.21, 0.26]
        case .jumping, .falling, .landing: return [0.13, 0.17]
        case .happy: return [0.38, 0.22, 0.35, 0.45]
        case .worried: return [0.65, 0.3, 0.4, 0.55]
        case .archery: return [0.4, 0.25, 0.18, 0.42]
        case .letterBlaster: return [0.34, 0.16, 0.20, 0.26]
        case .peek: return [0.3, 0.48]
        case .dancing: return [0.16, 0.14, 0.16, 0.14]
        case .juggling: return Array(repeating: 0.16, count: 8)
        case .approvalOpening, .approvalClosing: return Array(repeating: 0.125, count: 5)
        case .awaitingApproval: return [3.0, 0.125, 1.0, 0.7]
        case .perched: return [2.4, 0.14, 1.0, 1.2]
        case .perchThinking: return [1.4, 0.32, 1.1, 0.4]
        case .planning, .researching, .reading, .executing, .drawing: return [0.48, 0.42, 0.48, 0.72]
        case .virusFight: return [0.28, 0.17, 0.22, 0.32]
        case .grave: return [0.9, 0.65, 0.95, 0.7]
        case .reviving: return Array(repeating: 0.125, count: MascotPose.revivalFrames)
        case .virusVictory: return [0.38, 0.22, 0.42, 0.24]
        }
    }

    /// The caller supplies a transparent, top-left-origin 24 × 18 coordinate system.
    static func draw(in ctx: CGContext, pose: MascotPose, frame: Int, agentCount: Int = 0) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(false)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        let f = max(0, frame) % 4
        let lift = [0, 1, 0, 1][f]
        func box(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
            ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        }
        func cut(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
            ctx.clear(CGRect(x: x, y: y, width: w, height: h))
        }
        func pet(x: Int, y: Int, compact: Bool = false, walk: Bool = false, look: Int = 0) {
            let w = compact ? 12 : 14, h = compact ? 6 : 8
            box(x + 1, y, w - 2, h); box(x, y + 1, w, h - 2)
            let base = y + h - 1
            if walk {
                // Each of the four legs changes its footing independently.
                let stride = [1, 0, -1, 0][f]
                box(x + 1, base, 2, 3); box(x + 1 + stride, base + 2, 2, 1)
                box(x + 4, base, 2, 2); box(x + 6, base, 2, 1 + lift)
                box(x + w - 4, base, 2, 3); box(x + w - 4 - stride, base + 2, 2, 1)
            } else {
                box(x + 1, base, 2, 3); box(x + 4, base, 2, 2)
                box(x + w - 6, base, 2, 2); box(x + w - 3, base, 2, 3)
            }
            let ey = y + (compact ? 2 : 3)
            for ex in [x + 3 + look, x + w - 5 + look] {
                switch pose {
                case .sleeping:
                    cut(ex, ey + 1, 3)
                case .happy, .dancing, .virusVictory:
                    cut(ex, ey, 2); cut(ex - 1, ey + 1); cut(ex + 2, ey + 1)
                case .peek:
                    cut(ex, ey + 1, 2, 2)
                case .worried:
                    cut(ex, ey + 1, 2, 2)
                    cut(ex + (ex < x + w / 2 ? -1 : 2), ey)
                default:
                    let blink = (pose == .idle || pose == .awaitingApproval || pose == .perched) && f == 1
                    cut(ex, ey, 2, blink ? 1 : 2 + (compact ? 0 : 1))
                }
            }
        }
        func claws(x: Int, y: Int, w: Int = 14) {
            box(x - 2, y + 1, 2, 2); box(x - 3, y, 1, 2)
            box(x + w, y + 1, 2, 2); box(x + w + 2, y, 1, 2)
        }
        func stone(flame: Int) {
            box(8, 1, 8, 1)
            box(5, 2, 14, 2)
            box(3, 4, 18, 10)
            box(2, 14, 20, 2)
            cut(5, 14, 14)
            GraveInscription.draw { x, y in cut(4 + x, 6 + y) }
            box(0, 13, 1, 3)
            box(flame % 2, 10 - flame / 2, 1, 2)
        }

        switch pose {
        case .virusFight:
            pet(x: 3, y: 5 + lift, compact: true, look: 1)
            box(1, 7 + lift, 4); box(1, 10 + lift, 2, 2)
            box(14, 10 + lift, 3, 2)
            let x = 15 + lift, y = 5 + lift
            box(x, y, 7, 6); box(x + 1, y + 6, 5); box(x + 2, y + 7, 3)
            cut(x + 2, y + 1); cut(x + 3, y + 2); cut(x + 2, y + 3)
            cut(x + 4, y + 4, 2)
        case .grave:
            stone(flame: f)
        case .reviving:
            let step = min(MascotPose.revivalFrames - 1, max(0, frame))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: 24, height: 16))
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat([0, 1, 2, 4, 7, 10, 13, 16, 16, 16, 16, 16][step]))
            stone(flame: 0)
            ctx.restoreGState()
            let y = [17, 16, 15, 13, 11, 9, 7, 5, 3, 2, 3, 4][step]
            pet(x: 5, y: y)
            claws(x: 5, y: y + 2)
            ctx.restoreGState()
            if step >= 2 {
                let height = [0, 2, 3, 5, 5, 4, 3, 2, 1, 0][step - 2]
                box(1, 15 - height, 2); box(21, 15 - height, 2)
            }
        case .virusVictory:
            pet(x: 3, y: 7 - lift, compact: true)
            box(1, 8 - lift, 2, 2); box(0, 7 - lift, 1, 2)
            box(15, 8 - lift, 4, 2)
            box(15, 1, 7, 4); box(14, 2, 1, 2); box(22, 2, 1, 2)
            box(16, 5, 5); box(18, 6, 1, 2); box(16, 8, 5)
            cut(16, 2, 1, 2)
            box(4 + f, 3 - lift); box(3 + f, 4 - lift, 3); box(4 + f, 5 - lift)
        case .idle, .walking:
            let x = pose == .walking ? [4, 5, 6, 5][f] : 5
            let y = 4 + (pose == .walking ? lift : 0)
            pet(x: x, y: y, walk: pose == .walking, look: pose == .walking || f == 3 ? 1 : 0)
            claws(x: x, y: y + 3)
        case .thinking:
            pet(x: 4, y: 6, look: 1)
            box(2, 10, 2, 2); box(17, 10, 3, 2); box(18, 8, 2, 2)
            box(18, 5, 1, 1)
            if f > 0 { box(20, 3, 2, 2) }
            if f > 1 { box(22, 0, 2, 2) }
        case .typing:
            pet(x: 2, y: 3, compact: true)
            box(10, 2, 13, 8); cut(11, 3, 11, 6)
            box(12, 4, 3); box(12, 6, 5 + f)
            box(7, 12, 15, 2); box(5, 14, 18, 2)
            box(5, 10 + lift, 2, 3); box(12, 11 - lift, 2, 3)
        case .perched, .perchThinking:
            pet(x: 4, y: 5, compact: true, look: f > 1 ? 1 : 0)
            box(2, 11, 3, 2); box(16, 11, 3, 2)
            box(1, 13, 21); cut(7, 13); cut(13, 13)
            box(7 + lift, 14, 2, 2); box(13 - lift, 14, 2, 2)
            if pose == .perchThinking {
                box(13, 9, 3); box(17, 5, 2); box(20, 2, 2 + lift, 2)
            }
        case .planning, .drawing:
            pet(x: 1, y: 8, compact: true, look: 1)
            box(13, 1, 10, 11); cut(14, 3, 8, 8)
            box(15, 12, 2, 3); box(20, 12, 2, 3)
            if pose == .planning {
                box(15, 4, 4); if f >= 1 { box(16, 5, 1, 3); box(17, 7, 3) }
                if f >= 2 { box(15, 9, 3) }
                box(12, 9 - lift, 4)
            } else {
                box(15, 8, 2); box(16, 6, 2, 2); box(18, 8, 2)
                box(19, 4, 1 + lift); box(12, 10 - f, 5)
            }
        case .researching:
            pet(x: 1, y: 5, compact: true, look: 1)
            box(8, 13, 13, 3); cut(10, 14, 8)
            let x = 13 + lift, y = 3 + lift
            box(x+1, y, 5, 7); box(x, y+1, 7, 5); cut(x+2, y+2, 3, 3)
            box(x-1, y+6, 3, 2); box(x-2, y+7, 2, 2)
        case .reading:
            pet(x: 3, y: 3, compact: true, look: 1)
            box(4, 11, 14, 5); box(8, 9, 8, 3)
            box(11+lift, 7, 9, 7); cut(13+lift, 9, 5); cut(13+lift, 11, 3 + lift)
            box(5, 13, 11, 2)
        case .executing:
            pet(x: 1, y: 7, compact: true); box(11, 5, 12, 9); cut(12, 7, 10, 6)
            box(13, 8); box(14, 9); box(13, 10); box(16, 11, 2 + f)
            box(15, 14, 3, 2); box(13, 16, 8)
        case .climbing:
            box(21, 1, 1, 16)
            for y in [2, 7, 12] { box(19, y, 2, 1) }
            let y = 4 + [0, 1, 0, -1][f]
            pet(x: 4, y: y, compact: true, walk: true, look: 1)
            box(16, y + 1, 3, 2); box(18, y - 1 - lift, 2, 3 + lift)
            box(14, y + 6, 4, 2); box(17, y + 4 + lift, 2, 2)
            box(2, y + 2, 2, 3)
        case .rappelling:
            let y = 3 + [0, 1, 2, 1][f]
            box(17, 0, 1, y + 8); box(16, 0, 3)
            pet(x: 3, y: y, compact: true)
            box(14, y + 1, 4, 2); box(14, y + 5, 4, 2)
            box(1, y + 2, 2, 2); box(17, y + 7, 2, 3)
            // The harness stays readable against the filled shell.
            for i in 0..<5 { cut(5 + i * 2, y + i + 1, 2, 1) }
        case .jumping:
            pet(x: 5, y: 3 - lift, compact: true, look: 1)
            box(2, 8 - lift, 3, 2); box(1, 10 - lift, 2)
            box(17, 5 - lift, 3, 2); box(19, 2 - lift, 2, 4)
            box(4, 10 - lift, 3, 2); box(2, 12 - lift, 3)
        case .falling:
            let y = 5 + lift
            pet(x: 5, y: y)
            box(2, y + 1, 3, 2); box(1, y - 2, 2, 4)
            box(19, y + 1, 3, 2); box(21, y - 2, 2, 4)
            box(5, y + 10, 3); box(16, y + 10, 3)
        case .landing:
            pet(x: 6, y: 8 + lift, compact: true)
            box(3, 12 + lift, 3, 2); box(18, 12 + lift, 3, 2)
            box(4, 16, 4); box(16, 16, 4)
            box(1 - lift, 15, 2); box(21 + lift, 15, 2)
        case .peek:
            let x = 7 + lift
            pet(x: x, y: 7 + lift, compact: true, look: 1)
            // Rear foot counterbalances the inquisitive lean and the front claw grips the lip.
            box(5, 13, 4, 2); box(3, 15, 4)
            box(18, 11, 3, 3); box(20, 13, 2, 3); box(19, 15, 4)
        case .dancing:
            let x = [4, 5, 7, 6][f], y = 5 - lift
            pet(x: x, y: y, compact: true)
            let kicksRight = f < 2
            let raised = kicksRight ? x - 2 : x + 12
            let lowered = kicksRight ? x + 12 : x - 2
            box(raised, y, 2, 4); box(lowered, y + 3, 2, 2)
            box(kicksRight ? x + 11 : x - 1, y + 6, 3)
            box(kicksRight ? x + 1 : x + 9, y + 8, 2, 2)
            let star = [4, 9, 14, 19][f]
            box(star, 0, 1, 3); box(star - 1, 1, 3)
        case .happy:
            let y = 4 - lift
            pet(x: 5, y: y)
            box(3, y + 3, 2, 2); box(1, y + 1 - lift, 2, 4)
            box(19, y + 3, 2, 2); box(21, y + 1 - lift, 2, 4)
            cut(11, y + 6, 2)
        case .worried:
            let x = 3 + [0, 1, 0, -1][f]
            pet(x: x, y: 5); box(x - 1, 10, 2, 3); box(x + 13, 10, 2, 3)
            box(20, 1 + lift, 2, 4); box(20, 7 + lift, 2)
        case .sleeping:
            pet(x: 4, y: 6 + lift, compact: true); claws(x: 4, y: 9 + lift, w: 12)
            let x = 17 + (f > 1 ? 1 : 0), y = 2 - lift
            box(x, y, 4); box(x + 2, y + 1); box(x + 1, y + 2); box(x, y + 3, 4)
        case .archery:
            pet(x: 1, y: 6, compact: true, look: 1)
            box(12, 9, 3, 2); box(0, 9, 2, 2)
            // Bow, drawstring, and a little flying code chevron.
            box(16, 3, 2); box(18, 4, 1, 2); box(19, 6, 1, 6)
            box(18, 12, 1, 2); box(16, 14, 2)
            let stringX = f == 1 ? 14 : 16
            box(16, 4, 1, 2); box(stringX, 6, 1, 6); box(16, 12, 1, 2)
            if f == 1 { box(15, 5); box(15, 12) }
            let arrow = [15, 14, 19, 21][f]
            box(arrow, 7); box(arrow + 1, 8); box(arrow + 2, 9); box(arrow + 1, 10); box(arrow, 11)
        case .letterBlaster:
            pet(x: 2, y: 5, compact: true, look: 1)
            box(0, 9, 2, 2)
            box(8, 10, 4, 2); box(11, 9, 8, 5)
            box(18, 10, 4, 2); box(21, 9, 2, 4)
            box(12, 14, 2, 2); box(17, 14, 2)
            // Punch the letter A through the template so it follows the system appearance.
            cut(14, 10, 2); cut(13, 11, 1, 2); cut(16, 11, 1, 2); cut(14, 12, 2)
            let keyY = [7, 5, 4, 6][f]
            box(18, keyY, 3, 2); cut(19, keyY)
        case .juggling:
            pet(x: 6, y: 9, compact: true)
            box(4, 11, 2, 2); box(2, 9 + lift, 2, 3)
            box(18, 11, 2, 2); box(20, 10 - lift, 2, 3)
            let path = [(2, 6), (4, 3), (8, 1), (13, 0), (17, 2), (20, 5), (15, 5), (9, 5)]
            let count = min(3, max(1, agentCount))
            for index in 0..<count {
                let (x, y) = path[(max(0, frame) % path.count + path.count * index / count) % path.count]
                box(x, y, 3, 2); box(x, y + 2); box(x + 2, y + 2); cut(x + 1, y)
            }
        case .approvalOpening, .awaitingApproval, .approvalClosing:
            let step = pose.approvalUnrollStep(frame: frame)
            let top = [7, 3, 0, 0, 0][step]
            let height = [1, 2, 4, 6, 8][step]
            pet(x: 2, y: 9, compact: true, look: pose == .awaitingApproval && f == 3 ? 1 : 0)
            box(0, 12, 2, 2)
            box(14, 11, 4, 2); box(17, 9, 3, 3); box(18, top, 1, 11 - top)
            // Cut the same letters out of the monochrome paper as its lower edge descends.
            box(9, top, 13, height)
            box(8, top, 15); box(8, top + height - 1, 15)
            ApprovalLettering.draw { x, y in
                if y + 1 < height - 1 { cut(10 + x, top + 1 + y) }
            }
        }
    }

    static func raster(pose: MascotPose, frame: Int, agentCount: Int = 0, scale: Int = 2) -> CGImage? {
        let scale = min(3, max(1, scale))
        let w = Int(size.width) * scale, h = Int(size.height) * scale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        draw(in: ctx, pose: pose, frame: frame, agentCount: agentCount)
        return ctx.makeImage()
    }
}

@MainActor
final class MenuMascot: NSObject {
    private weak var button: NSStatusBarButton?
    private var pose = MascotPose.idle
    private var agentCount = 0
    private var quiet = false
    private var systemQuiet = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var asleep = false
    private var frame = 0
    private var frames: [NSImage] = []
    private var durations: [TimeInterval] = []
    private var timer: Timer?

    init(button: NSStatusBarButton) {
        self.button = button
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(describe), name: .clawdLanguageChanged, object: nil)
        refresh()
    }

    func update(pose: MascotPose, agentCount: Int, reducedMotion: Bool) {
        let count = max(0, agentCount)
        let next: MascotPose = count > 0 && [.idle, .thinking, .typing].contains(pose) ? .juggling : pose
        guard next != self.pose || count != self.agentCount || quiet != reducedMotion else { return }
        let needsNewFrames = next != self.pose || quiet != reducedMotion || (next == .juggling && min(count, 3) != min(self.agentCount, 3))
        self.pose = next
        self.agentCount = count
        quiet = reducedMotion
        if needsNewFrames { refresh() } else { describe() }
    }

    @objc private func describe() {
        var text = pose.accessibilityDescription
        if agentCount > 0 {
            text += " · " + (agentCount == 1 ? L("1 aktiver Subagent") : L("Aktive Subagents: {0}", agentCount.formatted(.number.locale(L10n.locale))))
        }
        button?.toolTip = text
        button?.setAccessibilityLabel(L("Claw’d Companion, {0}", text))
    }

    private func refresh() {
        timer?.invalidate()
        timer = nil
        frame = 0
        durations = MenuMascotPixels.durations(for: pose)
        let still = quiet || systemQuiet
        let count = still ? 1 : durations.count
        let drawnPose: MascotPose = still && pose.isApprovalTransition ? .awaitingApproval : pose
        frames = (0..<count).compactMap { index in
            let cel = still ? pose.stillFrame : index
            guard let cg = MenuMascotPixels.raster(pose: drawnPose, frame: cel, agentCount: agentCount) else { return nil }
            let image = NSImage(cgImage: cg, size: MenuMascotPixels.size)
            image.isTemplate = true
            return image
        }
        button?.image = frames.first
        describe()
        schedule()
    }

    private func schedule() {
        guard !asleep, button != nil, frames.count > 1,
              !pose.isOneShot || frame < frames.count - 1 else { return }
        let delay = durations[frame]
        let fresh = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.frames.isEmpty else { return }
                self.frame = (self.frame + 1) % self.frames.count
                self.button?.image = self.frames[self.frame]
                self.schedule()
            }
        }
        fresh.tolerance = min(delay * 0.15, 0.16)
        RunLoop.main.add(fresh, forMode: .common)
        timer = fresh
    }

    @objc private func accessibilityChanged() {
        let value = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard value != systemQuiet else { return }
        systemQuiet = value
        refresh()
    }

    @objc private func screenDidSleep() {
        asleep = true
        timer?.invalidate()
        timer = nil
    }

    @objc private func screenDidWake() {
        guard asleep else { return }
        asleep = false
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frames.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
