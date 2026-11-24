import SwiftUI

enum MascotPose: String, CaseIterable, Sendable {
    case idle, thinking, typing, walking, climbing, rappelling, jumping, falling, landing
    case happy, worried, sleeping, juggling, archery, letterBlaster, peek, dancing
    case approvalOpening, awaitingApproval, approvalClosing
    case perched, perchThinking, planning, researching, reading, executing, drawing
    case virusFight, grave, reviving, virusVictory

    static let approvalTransitionDuration: TimeInterval = 0.625
    static let revivalFrames = 12
    static let revivalDuration = TimeInterval(revivalFrames) / 8
    var isApprovalTransition: Bool { self == .approvalOpening || self == .approvalClosing }
    var isOneShot: Bool { isApprovalTransition || self == .reviving }
    var stillFrame: Int { self == .reviving ? Self.revivalFrames - 1 : 0 }

    /// Five hand-drawn cels, held at the endpoint until the activity changes.
    func approvalUnrollStep(frame: Int) -> Int {
        let step = min(4, max(0, frame))
        switch self {
        case .approvalOpening: return step
        case .approvalClosing: return 4 - step
        default: return 4
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .idle: return L("Claw’d schaut sich um")
        case .thinking: return L("Claw’d denkt nach")
        case .typing: return L("Claw’d tippt")
        case .walking: return L("Claw’d läuft")
        case .climbing: return L("Claw’d klettert")
        case .rappelling: return L("Claw’d seilt sich ab")
        case .jumping: return L("Claw’d springt ab")
        case .falling: return L("Claw’d springt hinunter")
        case .landing: return L("Claw’d landet")
        case .happy: return L("Claw’d freut sich")
        case .worried: return L("Claw’d ist besorgt")
        case .sleeping: return L("Claw’d schläft")
        case .juggling: return L("Claw’d jongliert mit Agents")
        case .archery: return L("Claw’d zielt mit dem Codebogen")
        case .letterBlaster: return L("Claw’d spielt mit dem Buchstabenblaster")
        case .peek: return L("Claw’d schaut über die Fensterkante")
        case .dancing: return L("Claw’d tanzt vor Freude")
        case .approvalOpening: return L("Claw’d rollt sein OK?-Schild aus")
        case .awaitingApproval: return L("Claw’d hält ein OK?-Schild und wartet auf deine Freigabe")
        case .approvalClosing: return L("Claw’d rollt sein OK?-Schild ein")
        case .perched: return L("Claw’d sitzt auf der Fensterkante")
        case .perchThinking: return L("Claw’d grübelt auf der Fensterkante")
        case .planning: return L("Claw’d erstellt einen Plan am Flipchart")
        case .researching: return L("Claw’d untersucht Quellen mit einer Lupe")
        case .reading: return L("Claw’d liest in einer Mappe")
        case .executing: return L("Claw’d arbeitet am Terminal")
        case .drawing: return L("Claw’d zeichnet an einer Staffelei")
        case .virusFight: return L("Claw’d wehrt Pixelviren ab")
        case .grave: return L("Claw’d ruht unter einem GIT-Grabstein")
        case .reviving: return L("Claw’d steigt aus seinem Grab")
        case .virusVictory: return L("Claw’d hebt den Siegerpokal")
        }
    }
}

struct MascotArt: View {
    let pose: MascotPose
    var facingLeft = false
    var reducedMotion = false
    var gaze: CGVector = .zero
    var agentCount = 0
    var transitionStart: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let still = reducedMotion || systemReduceMotion
        MascotCanvasView(pose: pose, facingLeft: facingLeft, still: still, gaze: gaze,
                         agentCount: agentCount, transitionStart: transitionStart).id(pose)
        .accessibilityLabel(pose == .juggling && agentCount > 0
                            ? (agentCount == 1 ? L("Claw’d jongliert mit einem aktiven Agenten")
                                               : L("Claw’d jongliert mit {0} aktiven Agents", agentCount.formatted(.number.locale(L10n.locale))))
                            : pose.accessibilityDescription)
    }

    init(pose: MascotPose, facingLeft: Bool = false, reducedMotion: Bool = false,
         gaze: CGVector = .zero, agentCount: Int = 0, transitionStart: TimeInterval? = nil) {
        self.pose = pose
        self.facingLeft = facingLeft
        self.reducedMotion = reducedMotion
        self.gaze = gaze
        self.agentCount = agentCount
        self.transitionStart = transitionStart
    }

    static func transitionFrame(since: TimeInterval, now: TimeInterval, pose: MascotPose = .approvalOpening) -> Int {
        let last = pose == .reviving ? MascotPose.revivalFrames - 1 : 4
        return Int(min(Double(last), max(0, (now - since) * 8)))
    }
}

private struct MascotCanvasView: View {
    let pose: MascotPose
    let facingLeft: Bool
    let still: Bool
    let gaze: CGVector
    let agentCount: Int
    let transitionStart: TimeInterval?
    private let appearance = State(initialValue: ProcessInfo.processInfo.systemUptime)

    var body: some View {
        TimelineView(.animation(minimumInterval: pose == .grave ? 0.5 : 0.125, paused: still)) { timeline in
            let drawnPose: MascotPose = still && pose.isApprovalTransition ? .awaitingApproval : pose
            let frame = still ? pose.stillFrame : (pose.isOneShot
                ? MascotArt.transitionFrame(since: transitionStart ?? appearance.wrappedValue, now: ProcessInfo.processInfo.systemUptime, pose: pose)
                : Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 960)
            Canvas { graphics, size in
                graphics.withCGContext { context in
                    MascotPixels.draw(in: context, size: size, pose: drawnPose, facingLeft: facingLeft, frame: frame,
                                      gaze: gaze, agentCount: agentCount)
                }
            }
        }
    }
}

/// Shared 3 × 5 ink pattern, drawn in display order in both sprites.
enum ApprovalLettering {
    static let rows = [
        "111 101 111",
        "101 110 001",
        "101 100 011",
        "101 110 000",
        "111 101 010"
    ]

    static func draw(_ pixel: (_ x: Int, _ y: Int) -> Void) {
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.utf8.enumerated() where cell == 49 { pixel(x, y) }
        }
    }
}

/// Identical chiseled letterforms at 2× on the desktop and 1× in the menu bar.
enum GraveInscription {
    static let rows = [
        "01111 111 11111",
        "10000 010 00100",
        "10111 010 00100",
        "10001 010 00100",
        "01111 111 00100"
    ]

    static func draw(_ pixel: (_ x: Int, _ y: Int) -> Void) {
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.utf8.enumerated() where cell == 49 { pixel(x, y) }
        }
    }
}

/// The release point and the two-handed sprite use one pivot in the letterboxed 56 × 48 grid.
struct BlasterAim {
    static let pivot = CGPoint(x: 35, y: 29)
    let gaze: CGVector
    let muzzle: CGPoint

    init(pet: CGRect, cursor: CGPoint, facingLeft: Bool) {
        let scale = max(0, min(pet.width / 56, pet.height / 48))
        let pivotWorld = CGPoint(x: pet.midX + (facingLeft ? -1 : 1) * (Self.pivot.x - 28) * scale,
                                 y: pet.midY + (24 - Self.pivot.y) * scale)
        let dx = cursor.x - pivotWorld.x, dy = cursor.y - pivotWorld.y
        let distance = hypot(dx, dy)
        gaze = distance.isFinite && distance > 0.001
            ? CGVector(dx: dx / distance, dy: dy / distance)
            : CGVector(dx: facingLeft ? -1 : 1, dy: 0)
        let reach = (53 - Self.pivot.x) * scale
        muzzle = CGPoint(x: pivotWorld.x + gaze.dx * reach, y: pivotWorld.y + gaze.dy * reach)
    }

    /// The renderer has already mirrored x into sprite space; grid y increases downward.
    static func angle(localGaze: CGVector) -> CGFloat {
        localGaze == .zero ? 0 : atan2(-localGaze.dy, localGaze.dx)
    }

    static func joint(_ x: Int, _ y: Int, angle: CGFloat) -> (Int, Int) {
        let dx = CGFloat(x) - pivot.x, dy = CGFloat(y) - pivot.y
        return (Int((pivot.x + dx * cos(angle) - dy * sin(angle)).rounded()),
                Int((pivot.y + dx * sin(angle) + dy * cos(angle)).rounded()))
    }
}

/// Hand-drawn sprite on a 56 × 48 cell grid. Coordinates use a top-left origin.
enum MascotPixels {
    // Dark, warm edges keep the silhouette visible on both light and dark windows.
    private enum Paint: Int, CaseIterable {
        case ink = 0x483030, shade = 0xA65040, coral = 0xE78664
        case sun = 0xFFB990, glow = 0xFFD8AE, blush = 0xD86954
        case eye = 0x382B2C, rope = 0xBB906C, metal = 0xC6DBD6
        case teal = 0x76A9A1, slate = 0x416166, key = 0xA6C9BF
        case lavender = 0xBCA4CA, honey = 0xEDBB77, blue = 0x9DBED5

        // Sprites reuse these immutable colors on every animation frame.
        private static let palette = Dictionary(uniqueKeysWithValues: allCases.map { paint in
            let hex = paint.rawValue
            let color = CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                                green: CGFloat((hex >> 8) & 255) / 255,
                                blue: CGFloat(hex & 255) / 255, alpha: 1)
            return (paint, color)
        })

        var color: CGColor { Self.palette[self]! }
    }

    private struct Sprite {
        let ctx: CGContext

        func rect(_ p: Paint, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            ctx.setFillColor(p.color)
            ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        }

        /// A stepped three-cell limb with a dark edge. Endpoints are cell centres.
        func limb(from a: (Int, Int), to b: (Int, Int), dark: Bool = false) {
            let dx = b.0 - a.0, dy = b.1 - a.1
            let steps = max(1, abs(dx), abs(dy))
            func position(_ start: Int, _ delta: Int, _ step: Int) -> Int {
                start + Int((Double(delta * step) / Double(steps)).rounded())
            }
            for (color, radius) in [(Paint.ink, 2), (dark ? Paint.shade : .coral, 1)] {
                for i in 0...steps {
                    let x = position(a.0, dx, i), y = position(a.1, dy, i)
                    rect(color, x - radius, y - radius, radius * 2 + 1, radius * 2 + 1)
                }
            }
        }

        /// The two blocky pincer tips leave a one-cell notch between them.
        func claw(atX x: Int, y: Int, left: Bool = false, raised: Bool = false) {
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
            if left { ctx.scaleBy(x: -1, y: 1) }
            if raised { ctx.rotate(by: -.pi / 2) }
            rect(.ink, -2, -2, 5, 5)
            rect(.ink,  1, -3, 3, 2)
            rect(.ink,  2,  0, 2, 2)
            rect(.coral, -1, -1, 4, 2)
            rect(.sun, 0, -2, 3, 1)
            rect(.shade, 0, 1, 2, 1)
            ctx.restoreGState()
        }

        func leg(root: Int, toe: Int, bottom: Int, back: Bool = false) {
            limb(from: (root, 32), to: (toe, bottom - 2), dark: back)
            rect(.ink, toe - 2, bottom - 1, 5, 2)
            rect(back ? .shade : .coral, toe - 1, bottom - 2, 3, 2)
        }

        func body(offsetY y: Int, compressed: Bool) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(y))
            let top = compressed ? 17 : 13
            rect(.ink, 14, top, 28, 22 - (top - 13))
            rect(.ink, 12, top + 2, 32, 18 - (top - 13))
            rect(.shade, 14, top + 1, 28, 20 - (top - 13))
            rect(.coral, 13, top + 2, 30, 16 - (top - 13))
            rect(.coral, 15, top + 1, 25, 18 - (top - 13))
            rect(.sun, 15, top + 1, 23, 1)
            rect(.sun, 13, top + 3, 1, 5)
            rect(.glow, 16, top + 2, 5, 1)
            rect(.sun, 23, top + 2, 2, 1)
            rect(.shade, 41, top + 6, 2, 1)
            rect(.blush, 40, top + 7, 3, 1)
            rect(.blush, 16, 27, 3, 1)
            rect(.blush, 37, 27, 3, 1)
            ctx.restoreGState()
        }

        func eyes(_ pose: MascotPose, frame: Int, offsetY y: Int, gaze: CGVector) {
            let dx = Int((gaze.dx * 2).rounded())
            let dy = -Int((gaze.dy * 2).rounded())
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(y))
            switch pose {
            case .happy, .dancing, .virusVictory:
                for base in [20, 33] {
                    let x = base + dx
                    rect(.eye, x, 23 + dy, 2, 2)
                    rect(.eye, x + 2, 21 + dy, 3, 2)
                    rect(.eye, x + 5, 23 + dy, 1, 2)
                }
                rect(.eye, 27, 26, 1, 2)
                rect(.eye, 28, 28, 3, 1)
                rect(.eye, 31, 26, 1, 2)
                rect(.sun, 18, 27, 2, 1)
                rect(.sun, 37, 27, 2, 1)
            case .peek:
                // He keeps an eye on the cursor while his attention is on the ledge.
                let eyeY = 25 + min(1, max(-1, dy))
                for x in [23, 36] { rect(.eye, x + dx, eyeY, 3, 4) }
                rect(.shade, 38, 22, 3, 1)
                rect(.eye, 32, 31, 2, 1)
            case .sleeping:
                for x in [20, 33] {
                    rect(.eye, x, 25, 2, 1)
                    rect(.eye, x + 2, 26, 4, 1)
                }
                rect(.shade, 28, 29, 2, 1)
            case .worried:
                rect(.eye, 20, 21, 3, 1)
                rect(.eye, 23, 20, 2, 1)
                rect(.eye, 33, 20, 2, 1)
                rect(.eye, 35, 21, 3, 1)
                for x in [22, 34] { rect(.eye, x + dx, 23 + max(-1, dy), 3, 4) }
                rect(.eye, 27, 30, 1, 1)
                rect(.eye, 28, 29, 3, 1)
                rect(.eye, 31, 30, 1, 1)
            default:
                let lookup = pose == .thinking || pose == .perchThinking || pose == .climbing || pose == .juggling || pose == .jumping
                let restingLook = pose == .perched ? [0, -2, -1, 0, 2, 1][(frame / 13) % 6] : (pose == .idle && frame % 80 > 60 ? -1 : 0)
                let xShift = gaze == .zero ? (lookup ? 2 : restingLook) : dx
                let neutralY = pose == .typing || pose == .falling ? 23 : (lookup ? 20 : 21)
                // Leave enough clearance above the letter keys for a full downward glance.
                let eyeY = (gaze == .zero ? neutralY : 21 + dy) - (pose == .letterBlaster ? 2 : 0)
                let blinking = frame % 57 == 53 || frame % 57 == 54
                for x in [21, 34] {
                    let height = blinking ? 1 : 5
                    rect(.eye, x + xShift, eyeY + (blinking ? 3 : 0), 3, height)
                }
                if pose == .thinking || pose == .perchThinking {
                    rect(.shade, 36, 18, 4, 1)
                    rect(.eye, 29, 28, 3, 1)
                } else if pose == .rappelling || pose == .falling {
                    rect(.eye, 28, 28, 3, 2)
                } else if pose == .juggling {
                    rect(.eye, 27, 27, 1, 1)
                    rect(.eye, 28, 28, 3, 1)
                    rect(.eye, 31, 27, 1, 1)
                } else if pose == .archery || pose == .virusFight {
                    rect(.shade, 33 + dx, 19 + dy, 4, 1)
                    rect(.eye, 28, 28, 3, 1)
                } else if pose == .letterBlaster {
                    rect(.eye, 26, 27, 1, 1)
                    rect(.eye, 27, 28, 2, 1)
                }
            }
            ctx.restoreGState()
        }

        func laptop(beat: Int) {
            rect(.ink, 35, 16, 19, 17)
            rect(.slate, 36, 17, 17, 15)
            rect(.teal, 37, 18, 15, 12)
            rect(.metal, 38, 19, 13, 1)
            rect(.slate, 38, 22, 4, 1)
            rect(.glow, 38, 24, 9, 1)
            rect(.key, 38, 26, 3 + beat * 2, 1)
            rect(.ink, 22, 32, 32, 7)
            rect(.ink, 18, 37, 36, 5)
            rect(.slate, 23, 33, 29, 4)
            rect(.teal, 20, 38, 32, 2)
            for x in stride(from: 24, through: 48, by: 4) {
                rect(.key, x, 34, 2, 1)
                rect(.metal, x - 1, 36, 2, 1)
            }
            rect(.key, 31, 39, 9, 1)
        }

        func thoughtDots(frame: Int) {
            let count = 1 + (frame / 4) % 3
            for i in 0..<count {
                let x = 40 + i * 4, y = 12 - i * 3
                rect(.ink, x, y, 3 + i, 3)
                rect(.metal, x + 1, y + 1, 1 + i, 1)
            }
        }

        func easel(painting: Bool, beat: Int, hand: (Int, Int)) {
            pixelLine(.ink, from: (40, 27), to: (34, 42), width: 3)
            pixelLine(.rope, from: (40, 27), to: (34, 42))
            pixelLine(.ink, from: (48, 27), to: (53, 42), width: 3)
            pixelLine(.rope, from: (48, 27), to: (53, 42))
            rect(.ink, 32, 6, 22, 25)
            rect(.rope, 33, 7, 20, 23)
            rect(.glow, 34, 8, 18, 21)
            rect(.honey, 34, 28, 18, 1)
            if painting {
                rect(.honey, 48, 11, 3, 3)
                pixelLine(.teal, from: (35, 24), to: (40, 17), width: 2)
                pixelLine(.teal, from: (40, 17), to: (46, 24), width: 2)
                pixelLine(.slate, from: (43, 22), to: (46, 18))
                pixelLine(.slate, from: (46, 18), to: (50, 22))
                rect(.coral, 35, 26, 5 + beat * 3, 1)
                let end = (37 + beat * 3, 26)
                pixelLine(.ink, from: hand, to: end, width: 2)
                rect(.blush, end.0, end.1, 2, 2)
            } else {
                rect(.ink, 33, 4, 20, 4)
                rect(.teal, 34, 5, 18, 2)
                rect(.slate, 36, 10, 10, 1)
                for item in 0...min(2, beat) {
                    let y = 14 + item * 5
                    rect(.teal, 36, y, 3, 3)
                    rect(.glow, 37, y + 1, 1, 1)
                    rect(.slate, 41, y + 1, 6 + item, 1)
                    if item > 0 { rect(.rope, 37, y - 2, 1, 2) }
                }
                pixelLine(.ink, from: hand, to: (42, 15 + min(2, beat) * 5))
            }
        }

        func sourceLens(beat: Int) {
            rect(.ink, 25, 32, 25, 11)
            rect(.honey, 26, 33, 23, 9)
            rect(.ink, 29, 28, 24, 13)
            rect(.glow, 30, 29, 22, 11)
            for i in 0..<3 { rect(.rope, 32, 31 + 3*i, i == 1 ? 15 : 10, 1) }
            let x = [38, 40, 42, 40][beat], y = [20, 21, 22, 21][beat]
            pixelLine(.ink, from: (x + 2, y + 9), to: (x - 6, y + 17), width: 4)
            pixelLine(.rope, from: (x + 1, y + 10), to: (x - 6, y + 17), width: 2)
            rect(.ink, x+2, y, 7, 11); rect(.ink, x, y+2, 11, 7)
            rect(.teal, x+2, y+1, 7, 9); rect(.metal, x+1, y+3, 9, 5)
            rect(.blue, x+3, y+2, 5, 7); rect(.glow, x+3, y+3, 2, 2)
            rect(.slate, x+5, y+7, 3, 1)
        }

        func readingFolder(beat: Int) {
            rect(.ink, 12, 29, 27, 12); rect(.honey, 13, 30, 25, 10)
            rect(.ink, 14, 27, 9, 3); rect(.honey, 15, 28, 7, 2)
            let top = [28, 25, 23, 26][beat]
            rect(.ink, 27, top, 19, 40 - top); rect(.glow, 28, top+1, 17, 39 - top)
            rect(.rope, 30, top+3, 10, 1); rect(.rope, 30, top+5, 13, 1)
            rect(.ink, 16, 33, 30, 10); rect(.teal, 17, 34, 28, 8)
            rect(.key, 18, 35, 11, 1); rect(.slate, 19, 40, 24, 1)
            rect(.honey, 37, 35, 5, 2)
        }

        func terminal(beat: Int) {
            rect(.ink, 30, 21, 24, 17); rect(.slate, 31, 22, 22, 15)
            rect(.ink, 32, 23, 20, 12)
            rect(.teal, 32, 23, 20, 2); rect(.key, 33, 23, 2, 1)
            rect(.key, 34, 27, 1, 1); rect(.key, 35, 28, 1, 1); rect(.key, 34, 29, 1, 1)
            rect(.honey, 38, 29, 3 + beat * 2, 1); rect(.teal, 34, 32, 5 + beat, 1)
            rect(.metal, 49, 36, 2, 1)
            rect(.ink, 40, 38, 4, 5); rect(.ink, 36, 42, 13, 2)
            rect(.slate, 41, 38, 2, 4)
        }

        func sleepMark(frame: Int) {
            let dy = (frame / 5) % 3
            let x = 42 + dy, y = 12 - dy
            rect(.ink, x - 1, y - 1, 6, 2)
            rect(.ink, x + 1, y + 1, 3, 1)
            rect(.ink, x, y + 2, 3, 1)
            rect(.ink, x - 1, y + 3, 6, 2)
            rect(.metal, x, y, 4, 1)
            rect(.metal, x + 2, y + 1, 1, 1)
            rect(.metal, x + 1, y + 2, 1, 1)
            rect(.metal, x, y + 3, 4, 1)
        }

        func sparkle(x: Int, y: Int) {
            rect(.ink, x - 1, y - 3, 3, 7)
            rect(.ink, x - 3, y - 1, 7, 3)
            rect(.glow, x, y - 2, 1, 5)
            rect(.glow, x - 2, y, 5, 1)
        }

        /// Toss along a high arc, then pass back along a lower arc between the same two hands.
        func juggle(frame: Int, agentCount: Int) {
            let colors: [Paint] = [.key, .lavender, .honey, .blue, .sun]
            let count = min(max(0, agentCount), colors.count)
            for index in 0..<count {
                let cycle = (Double(frame % 24) / 24 + Double(index) / Double(count))
                    .truncatingRemainder(dividingBy: 1)
                let high = cycle < 0.67
                let t = high ? cycle / 0.67 : (cycle - 0.67) / 0.33
                let x = Int((8 + 40 * (high ? t : 1 - t)).rounded())
                let y = Int((21 - (high ? 17 : 8) * (4 * t * (1 - t))).rounded())
                let color = colors[index]
                // Tiny copies of Claw’d with a different shell and two little feet.
                rect(.ink, x - 3, y - 2, 7, 5)
                rect(color, x - 2, y - 1, 5, 3)
                rect(.glow, x - 2, y - 1, 2, 1)
                rect(.eye, x - 1, y, 1, 1)
                rect(.eye, x + 1, y, 1, 1)
                rect(.ink, x - 2, y + 3, 1, 1)
                rect(.ink, x + 2, y + 3, 1, 1)
            }
        }

        func pixelLine(_ color: Paint, from a: (Int, Int), to b: (Int, Int), width: Int = 1) {
            let length = max(1, max(abs(a.0 - b.0), abs(a.1 - b.1)))
            for i in 0...length {
                let t = Double(i) / Double(length)
                let x = a.0 + Int((Double(b.0 - a.0) * t).rounded())
                let y = a.1 + Int((Double(b.1 - a.1) * t).rounded())
                rect(color, x - width / 2, y - width / 2, width, width)
            }
        }

        func codeBow(frame: Int, gaze: CGVector) {
            let slope = -gaze.dy * 0.45
            let rotation = atan(slope)
            func point(_ x: Int, _ y: Int) -> (Int, Int) {
                let xx = Double(x), yy = Double(y)
                return (47 + Int((xx * cos(rotation) - yy * sin(rotation)).rounded()),
                        26 + Int((xx * sin(rotation) + yy * cos(rotation)).rounded()))
            }
            let tips = [(0, -10), (3, -8), (4, -5), (4, -2), (5, 0),
                        (4, 2), (4, 5), (3, 8), (0, 10)]
            let pull = -4 - min(5, frame % 10)
            let notch = point(pull, 0)
            // The glowing cursor-bracket glyph sits on the string while Claw’d aims.
            for side in [-10, 10] {
                pixelLine(.ink, from: point(0, side), to: notch, width: 2)
                pixelLine(.key, from: point(0, side), to: notch)
            }
            for (a, b) in zip(tips, tips.dropFirst()) {
                pixelLine(.ink, from: point(a.0, a.1), to: point(b.0, b.1), width: 3)
            }
            for (a, b) in zip(tips, tips.dropFirst()) {
                pixelLine(.honey, from: point(a.0, a.1), to: point(b.0, b.1))
            }
            pixelLine(.slate, from: point(4, -2), to: point(4, 2), width: 3)
            pixelLine(.teal, from: point(4, -2), to: point(4, 2))
            pixelLine(.ink, from: notch, to: point(6, 0), width: 2)
            pixelLine(.key, from: notch, to: point(6, 0))
            pixelLine(.metal, from: point(4, -2), to: point(6, 0))
            pixelLine(.metal, from: point(4, 2), to: point(6, 0))
        }

        /// Four original cels of the little typesetter, including its spring-loaded A key.
        private static let blasterCels: [[Paint?]] = (0..<4).map { beat in
            var cells = [Paint?](repeating: nil, count: 56 * 48)
            func rect(_ color: Paint, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
                for row in y..<(y + height) {
                    for col in x..<(x + width) { cells[row * 56 + col] = color }
                }
            }
            let keyLight: Paint = beat == 0 ? .glow : .key
            rect(.ink, 23, 29, 9, 5)
            rect(.slate, 24, 30, 6, 3)
            rect(.ink, 29, 26, 17, 9)
            rect(.slate, 30, 27, 15, 7)
            rect(.teal, 31, 27, 13, 5)
            rect(.metal, 31, 27, 2, 1)
            rect(.ink, 44, 27, 9, 5)
            rect(.teal, 45, 28, 7, 3)
            rect(.ink, 51, 26, 3, 7)
            rect(keyLight, 52, 28, 2, 3)
            rect(.ink, 34, 26, 7, 7)
            rect(keyLight, 36, 27, 3, 1)
            rect(keyLight, 35, 28, 1, 4)
            rect(keyLight, 39, 28, 1, 4)
            rect(keyLight, 36, 29, 3, 1)

            // A letter key springs out of the top and settles between bursts.
            let keyY = 24 - [0, 2, 3, 1][beat]
            rect(.ink, 44, keyY, 5, 4)
            rect(.honey, 45, keyY + 1, 3, 2)
            rect(.ink, 46, keyY + 1, 1, 1)
            return cells
        }

        func letterBlaster(frame: Int, angle: CGFloat) {
            let cells = Self.blasterCels[(frame / 2) % 4]
            let c = cos(angle), s = sin(angle)
            let pivot = BlasterAim.pivot
            // Sample the tilted cel back onto the original grid. It stays pixelated at every zoom.
            for y in 7..<48 {
                let dy = CGFloat(y) + 0.5 - pivot.y
                var last: Paint?, start = 0
                for x in 12...56 {
                    let dx = CGFloat(x) + 0.5 - pivot.x
                    let u = Int(floor(pivot.x + c * dx + s * dy))
                    let v = Int(floor(pivot.y - s * dx + c * dy))
                    let color = x < 56 && (0..<56).contains(u) && (0..<48).contains(v) ? cells[v * 56 + u] : nil
                    if color != last {
                        if let last { rect(last, start, y, x - start, 1) }
                        last = color
                        start = x
                    }
                }
            }
        }

        func approvalScroll(step: Int, gripY: Int, mirrored: Bool) {
            // A brass tube lifts out of the claw, then the parchment drops from its roller.
            let top = [17, 9, 2, 2, 2][step]
            let length = [0, 0, 3, 7, 10][step]
            rect(.ink, 48, top + 1, 3, gripY - top + 3)
            rect(.rope, 49, top + 2, 1, gripY - top + 1)
            if length > 0 {
                rect(.ink, 33, top + 2, 21, length)
                rect(.glow, 34, top + 2, 19, length)
                rect(.honey, 34, top + 2, 1, length)
                rect(.honey, 52, top + 2, 1, length)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 34, y: top + 2, width: 19, height: length))
                if mirrored {
                    ctx.translateBy(x: 87, y: 0)
                    ctx.scaleBy(x: -1, y: 1)
                }
                ApprovalLettering.draw { x, y in rect(.ink, 38 + x, top + 4 + y, 1, 1) }
                ctx.restoreGState()
                // The darker curled hem follows the lower edge as the words appear.
                rect(.ink, 32, top + length + 2, 23, 2)
                rect(.honey, 33, top + length + 2, 21, 1)
                if step == 4 { rect(.shade, 50, top + length + 4, 2, 2) }
            }
            rect(.ink, 31, top, 24, 3)
            rect(.teal, 32, top + 1, 22, 1)
            rect(.ink, 31, top - 1, 3, 5)
            rect(.ink, 52, top - 1, 3, 5)
            rect(.honey, 32, top, 1, 3)
            rect(.honey, 53, top, 1, 3)
        }

        func gravestone(flame: Int) {
            // The top of the arch, beveled face and plinth make three distinct silhouettes.
            rect(.ink, 22, 5, 12, 2)
            rect(.ink, 17, 7, 22, 3)
            rect(.ink, 13, 10, 30, 3)
            rect(.ink, 10, 13, 36, 25)
            rect(.slate, 12, 14, 32, 24)
            rect(.teal, 15, 11, 26, 25)
            rect(.metal, 18, 9, 20, 25)
            rect(.metal, 23, 7, 10, 2)
            rect(.metal, 14, 13, 28, 20)
            rect(.metal, 12, 16, 32, 17)
            rect(.key, 15, 33, 24, 2)
            // A small branch-and-merge glyph, engraved above the epitaph.
            rect(.slate, 25, 11, 2, 2)
            rect(.slate, 26, 13, 1, 4)
            rect(.slate, 27, 14, 3, 1)
            rect(.slate, 29, 12, 1, 2)
            rect(.slate, 29, 10, 2, 2)
            GraveInscription.draw { x, y in rect(.ink, 13 + x * 2, 20 + y * 2, 2, 2) }
            rect(.ink, 8, 37, 40, 4)
            rect(.key, 10, 38, 36, 1)
            rect(.slate, 9, 39, 38, 1)
            rect(.ink, 5, 41, 46, 2)
            rect(.rope, 7, 41, 11, 1)
            rect(.shade, 35, 42, 12, 1)

            rect(.ink, 4, 35, 4, 6)
            rect(.glow, 5, 36, 2, 4)
            rect(.shade, 5, 33, 2, 2)
            rect(.honey, 5, 31, 2, 3)
            rect(.sun, [5, 6, 6, 4][flame], [29, 30, 28, 30][flame], 1, 3)
            rect(.glow, 5, 32, 1, 2)
            rect(.teal, 48, 36, 2, 5)
            rect(.key, 50, 34, 2, 3)
            rect(.lavender, 47, 32, 3, 2)
            rect(.lavender, 46, 33, 5, 2)
            rect(.honey, 48, 33, 1, 1)
        }

        func resurrection(frame: Int, gaze: CGVector, mirrored: Bool) {
            let sink = [0, 1, 4, 9, 15, 22, 29, 36, 40, 43, 43, 43][frame]
            let rise = [38, 36, 32, 25, 18, 12, 6, 1, -4, -5, -2, 0][frame]
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: 56, height: 43))
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(sink))
            gravestone(flame: 0)
            ctx.restoreGState()
            ctx.saveGState()
            if mirrored {
                ctx.translateBy(x: 56, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            ctx.translateBy(x: 0, y: CGFloat(rise))
            draw(pose: .happy, frame: 0, gaze: gaze, agentCount: 0, mirrored: mirrored)
            ctx.restoreGState()
            ctx.restoreGState()

            guard frame >= 2 else { return }
            let spread = min(7, frame - 2)
            let height = [0, 2, 6, 10, 12, 10, 7, 3, 0, 0][frame - 2]
            rect(.ink, 10 - spread, 40 - height, 3, 2)
            rect(.rope, 10 - spread, 40 - height, 2, 1)
            rect(.shade, 43 + spread, 41 - height / 2, 3, 2)
            rect(.rope, 42 + spread, 39 - height, 2, 1)
            if (4...9).contains(frame) {
                sparkle(x: 9 - spread, y: 25 - height)
                sparkle(x: 43 + spread, y: 22 - height / 2)
            }
        }

        func shield(atX x: Int, y: Int, pulse: Bool) {
            rect(.ink, x - 6, y - 7, 12, 12)
            rect(.ink, x - 4, y + 5, 8, 2)
            rect(.ink, x - 2, y + 7, 4, 2)
            rect(.metal, x - 5, y - 6, 10, 9)
            rect(.slate, x - 4, y - 4, 8, 8)
            rect(.teal, x - 4, y + 4, 8, 1)
            rect(.teal, x - 2, y + 5, 4, 2)
            // A luminous terminal prompt in the face of the shield.
            let light: Paint = pulse ? .glow : .key
            rect(light, x - 3, y - 3, 2, 1)
            rect(light, x - 2, y - 2, 2, 1)
            rect(light, x - 3, y - 1, 2, 1)
            rect(light, x + 1, y, 2, 1)
        }

        func trophy(x: Int, base: Int) {
            let y = base - 14
            rect(.ink, x - 8, y + 1, 3, 5)
            rect(.ink, x + 5, y + 1, 3, 5)
            rect(.honey, x - 7, y + 2, 2, 2)
            rect(.honey, x + 5, y + 2, 2, 2)
            rect(.ink, x - 6, y, 12, 7)
            rect(.ink, x - 4, y + 7, 8, 2)
            rect(.ink, x - 2, y + 9, 4, 3)
            rect(.ink, x - 5, y + 12, 10, 2)
            rect(.honey, x - 5, y + 1, 10, 5)
            rect(.glow, x - 4, y + 1, 8, 1)
            rect(.glow, x - 4, y + 2, 2, 3)
            rect(.honey, x - 3, y + 6, 6, 2)
            rect(.honey, x - 1, y + 8, 2, 4)
            rect(.honey, x - 4, y + 12, 8, 1)
        }

        func draw(pose: MascotPose, frame: Int, gaze: CGVector, agentCount: Int, mirrored: Bool) {
            if pose == .grave {
                gravestone(flame: (frame / 4) % 4)
                return
            }
            if pose == .reviving {
                resurrection(frame: frame, gaze: gaze, mirrored: mirrored)
                return
            }
            let beat = (frame / 2) % 4
            let stepA = [0, 2, 0, -2][beat]
            let stepB = -stepA
            var bodyY = 0, bodyX = 0
            switch pose {
            case .walking, .climbing: bodyY = beat % 2 - 1
            case .perched, .perchThinking: bodyY = 3
            case .planning, .drawing, .researching, .executing: bodyX = -6
            case .typing, .reading: bodyX = -3; bodyY = -1
            case .jumping: bodyY = -2
            case .falling: bodyY = beat % 2
            case .landing: bodyY = 3 + beat % 2
            case .peek:
                bodyX = 4 + beat % 2
                bodyY = 3 + beat % 2
            case .dancing:
                bodyX = [-2, -1, 2, 1][beat]
                bodyY = [0, -2, 0, -2][beat]
            case .juggling: bodyY = [0, 1, 0, -1][beat]
            case .happy: bodyY = [0, -2, -3, -1][beat]
            case .virusFight: bodyY = [1, 0, -1, 0][frame % 4]
            case .virusVictory: bodyY = [0, -1, -2, -1][frame % 4]
            case .sleeping: bodyY = (frame / 10) % 2 + 1
            case .idle, .thinking: bodyY = (frame / 9) % 2
            default: break
            }

            var leftHand = (9, 26 + bodyY)
            var rightHand = (47, 26 + bodyY)
            var leftRaised = false, rightRaised = false

            switch pose {
            case .perched, .perchThinking:
                // The bottom row of the heels and resting claw is 37. Only the toes dangle below it.
                leg(root: 19, toe: 16, bottom: 37, back: true)
                leg(root: 34, toe: 38, bottom: 37, back: true)
                leftHand = pose == .perched ? (11, 35) : (20, 31 - beat % 2)
                rightHand = (44, 35)
            case .walking:
                leg(root: 22, toe: 22 + stepB, bottom: 39 - max(0, stepA), back: true)
                leg(root: 33, toe: 33 + stepA, bottom: 39 - max(0, stepB), back: true)
                leg(root: 16, toe: 16 + stepA, bottom: 42 - max(0, stepB))
                leg(root: 39, toe: 39 + stepB, bottom: 42 - max(0, stepA))
                leftHand.1 += stepA
                rightHand.1 += stepB
            case .virusFight:
                leg(root: 22, toe: 21, bottom: 39, back: true)
                leg(root: 33, toe: 35, bottom: 39, back: true)
                leg(root: 16, toe: 11, bottom: 42)
                leg(root: 39, toe: 43, bottom: 42)
                leftHand = (8, 22 + bodyY)
                rightHand = (46 + [0, 1, 2, 1][frame % 4], 26 + bodyY)
                leftRaised = true
            case .jumping:
                // Push off with the rear feet and reach forward with one claw.
                leg(root: 23, toe: 17, bottom: 35, back: true)
                leg(root: 34, toe: 34, bottom: 36, back: true)
                leg(root: 16, toe: 9, bottom: 38 - beat % 2)
                leg(root: 39, toe: 43, bottom: 34 + beat % 2)
                leftHand = (8, 28 + beat % 2)
                rightHand = (48, 15 - beat % 2)
                rightRaised = true
            case .falling:
                // Feet reach down first. Raised, wide claws steady the fall.
                leg(root: 23, toe: 21, bottom: 39 + beat % 2, back: true)
                leg(root: 32, toe: 34, bottom: 40, back: true)
                leg(root: 16, toe: 13, bottom: 43)
                leg(root: 39, toe: 43, bottom: 42 + beat % 2)
                leftHand = (7, 17 + beat % 2)
                rightHand = (49, 16 - beat % 2)
                leftRaised = true
                rightRaised = true
            case .landing:
                leg(root: 22, toe: 20, bottom: 40, back: true)
                leg(root: 34, toe: 36, bottom: 40, back: true)
                leg(root: 16, toe: 11, bottom: 42)
                leg(root: 39, toe: 45, bottom: 42)
                leftHand = (8, 35 - beat % 2)
                rightHand = (48, 35 - beat % 2)
            case .peek:
                // He scoots his head out while both claws stay planted on the ledge.
                leg(root: 22, toe: 17, bottom: 40, back: true)
                leg(root: 32, toe: 30, bottom: 39, back: true)
                leg(root: 16, toe: 10, bottom: 42)
                leg(root: 39, toe: 31, bottom: 42)
                leftHand = (20, 40)
                rightHand = (35, 40)
            case .dancing:
                let kicksRight = beat < 2
                leg(root: 22, toe: 22 + bodyX, bottom: 38, back: true)
                leg(root: 34, toe: 34 + bodyX, bottom: 38, back: true)
                leg(root: 16, toe: kicksRight ? 15 : 9 - beat % 2, bottom: kicksRight ? 42 : 35)
                leg(root: 39, toe: kicksRight ? 46 + beat % 2 : 40, bottom: kicksRight ? 35 : 42)
                leftHand = (8, kicksRight ? 15 + bodyY : 28)
                rightHand = (48, kicksRight ? 28 : 15 + bodyY)
                leftRaised = kicksRight
                rightRaised = !kicksRight
            case .climbing:
                leg(root: 22, toe: 25, bottom: 37 + stepA, back: true)
                leg(root: 32, toe: 39, bottom: 36 + stepB, back: true)
                limb(from: (16, 31), to: (22, 38 + stepA))
                limb(from: (39, 32), to: (47, 38 + stepB))
                rect(.ink, 46, 35 + stepB, 4, 5)
                rect(.coral, 47, 36 + stepB, 2, 3)
                leftHand = (44, 14 + stepB)
                rightHand = (49, 24 + stepA)
                leftRaised = true
                rightRaised = true
            case .rappelling:
                rect(.ink, 40, 0, 3, 33)
                rect(.rope, 41, 0, 1, 33)
                leg(root: 22, toe: 20, bottom: 38, back: true)
                leg(root: 32, toe: 36, bottom: 38, back: true)
                leg(root: 16, toe: 12, bottom: 39 + stepA)
                leg(root: 39, toe: 44, bottom: 37 + stepB)
                leftHand = (10, 28 + stepA)
                rightHand = (42, 14)
                rightRaised = true
            default:
                leg(root: 22, toe: 22, bottom: 39 + min(bodyY, 0), back: true)
                leg(root: 33, toe: 33, bottom: 39 + min(bodyY, 0), back: true)
                leg(root: 16, toe: 15, bottom: 42 + min(bodyY, 0))
                leg(root: 39, toe: 40, bottom: 42 + min(bodyY, 0))
                switch pose {
                case .thinking:
                    rightHand = (36, 29 + bodyY)
                    rightRaised = true
                case .typing:
                    leftHand = (22, 34 + stepA)
                    rightHand = (35, 34 + stepB)
                case .planning, .drawing:
                    leftHand = (6, 30)
                    rightHand = (32 + beat % 2, 30 - beat)
                case .researching:
                    leftHand = (8, 30)
                    rightHand = (32 + [0, 2, 4, 2][beat], 37)
                case .reading:
                    leftHand = (12, 32 + beat % 2)
                    rightHand = (44, 31 - beat % 2)
                case .executing:
                    leftHand = (12, 32)
                    rightHand = (29, 36 - beat % 2)
                case .happy:
                    leftHand = (8, 19 + bodyY + beat % 2)
                    rightHand = (48, 19 + bodyY - beat % 2)
                    leftRaised = true
                    rightRaised = true
                case .virusVictory:
                    leftHand = (8, 18 + bodyY)
                    rightHand = (46, 19 + bodyY)
                    leftRaised = true
                    rightRaised = true
                case .worried:
                    leftHand = (20, 32)
                    rightHand = (35, 32)
                case .archery:
                    leftHand = (39 - min(5, frame % 10), 27)
                    rightHand = (46, 28)
                case .letterBlaster:
                    let angle = BlasterAim.angle(localGaze: gaze)
                    leftHand = BlasterAim.joint(29, 34, angle: angle)
                    rightHand = BlasterAim.joint(44, 34, angle: angle)
                case .approvalOpening, .awaitingApproval, .approvalClosing:
                    let step = pose.approvalUnrollStep(frame: frame)
                    leftHand = (10, 29)
                    rightHand = (48, [30, 26, 23, 22, 22][step])
                    rightRaised = true
                case .juggling:
                    leftHand = (8, 23 + stepA)
                    rightHand = (48, 23 + stepB)
                    leftRaised = true
                    rightRaised = true
                case .sleeping:
                    leftHand = (10, 30 + bodyY)
                    rightHand = (46, 30 + bodyY)
                default: break
                }
            }

            if pose != .climbing {
                limb(from: (14 + bodyX, 25 + bodyY), to: leftHand)
            }
            limb(from: (41 + bodyX, 25 + bodyY), to: rightHand)
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(bodyX), y: 0)
            body(offsetY: bodyY, compressed: [.sleeping, .landing, .peek, .perched, .perchThinking].contains(pose))
            eyes(pose, frame: frame, offsetY: bodyY, gaze: gaze)
            ctx.restoreGState()

            if pose == .rappelling {
                // A dark climbing sling, an aqua buckle, and a short rope to the hand.
                for n in 0..<7 {
                    rect(.ink, 14 + n * 4, 24 + n, 5, 2)
                    rect(.slate, 15 + n * 4, 24 + n, 4, 1)
                }
                rect(.ink, 39, 14, 4, 19)
                rect(.rope, 41, 14, 1, 18)
                rect(.metal, 39, 29, 4, 3)
                rect(.slate, 40, 30, 2, 1)
            }
            switch pose {
            case .perched, .perchThinking:
                let sway = (frame / 5) % 4 == 2 ? 1 : 0
                for (x, offset) in [(21, sway), (32, -sway)] {
                    rect(.ink, x, 35, 3, 6); rect(.shade, x+1, 35, 1, 5)
                    rect(.ink, x-1+offset, 40, 4, 2); rect(.sun, x+offset, 40, 2, 1)
                }
                if pose == .perchThinking { thoughtDots(frame: frame) }
            case .thinking: thoughtDots(frame: frame)
            case .typing: laptop(beat: beat)
            case .planning, .drawing: easel(painting: pose == .drawing, beat: beat, hand: rightHand)
            case .researching: sourceLens(beat: beat)
            case .reading: readingFolder(beat: beat)
            case .executing: terminal(beat: beat)
            default: break
            }
            if pose.isApprovalTransition || pose == .awaitingApproval {
                approvalScroll(step: pose.approvalUnrollStep(frame: frame), gripY: rightHand.1, mirrored: mirrored)
            }
            if pose == .archery {
                limb(from: (20, 31), to: leftHand)
                codeBow(frame: frame, gaze: gaze)
            }
            if pose == .letterBlaster {
                limb(from: (15, 27), to: (17, 33))
                limb(from: (17, 33), to: leftHand)
                limb(from: (42, 25), to: rightHand)
                letterBlaster(frame: frame, angle: BlasterAim.angle(localGaze: gaze))
            }
            if pose == .peek {
                limb(from: (45, 34 + bodyY), to: rightHand)
            }
            if pose == .thinking || pose == .perchThinking || pose == .typing || pose == .worried {
                if pose != .thinking { limb(from: (13, 28 + bodyY), to: leftHand) }
                if pose != .perchThinking { limb(from: (43 + bodyX, 28 + bodyY), to: rightHand) }
            }
            if pose == .climbing {
                limb(from: (34, 17 + bodyY), to: leftHand)
            }
            claw(atX: leftHand.0, y: leftHand.1, left: pose != .climbing, raised: leftRaised)
            claw(atX: rightHand.0, y: rightHand.1, raised: rightRaised)

            switch pose {
            case .virusFight:
                rect(.ink, 8, 14 + bodyY, 7, 3)
                rect(.teal, 9, 15 + bodyY, 6, 1)
                rect(.slate, 7, 17 + bodyY, 5, 2)
                rect(.slate, 13, 16 + bodyY, 30, 2)
                rect(.key, 17, 16 + bodyY, 15, 1)
                shield(atX: rightHand.0, y: rightHand.1, pulse: frame % 4 == 2)
            case .virusVictory:
                trophy(x: rightHand.0, base: rightHand.1)
                sparkle(x: [7, 6, 8, 10][frame % 4], y: [9, 7, 5, 6][frame % 4])
            case .juggling: juggle(frame: frame, agentCount: agentCount)
            case .sleeping: sleepMark(frame: frame)
            case .happy: sparkle(x: 45, y: 9 + beat % 2)
            case .dancing: sparkle(x: [11, 22, 36, 46][beat], y: [8, 5, 5, 8][beat])
            case .worried:
                let y = 14 + (frame / 5) % 3
                rect(.ink, 44, y, 1, 2)
                rect(.ink, 43, y + 2, 3, 4)
                rect(.metal, 44, y + 2, 1, 3)
            case .landing:
                let spread = beat % 2
                rect(.shade, 3 - spread, 41 - spread, 3, 2)
                rect(.sun, 6, 39, 2, 1)
                rect(.shade, 50 + spread, 41 - spread, 3, 2)
                rect(.sun, 48, 39, 2, 1)
            default: break
            }
        }
    }

    static func draw(in ctx: CGContext, size: CGSize, pose: MascotPose, facingLeft: Bool, frame: Int,
                     gaze: CGVector = .zero, agentCount: Int = 0) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / 56, size.height / 48)
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.translateBy(x: (size.width - 56 * scale) / 2, y: (size.height - 48 * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        if facingLeft && pose != .grave && pose != .reviving {
            ctx.translateBy(x: 56, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        func normalized(_ value: CGFloat) -> CGFloat { value.isFinite ? min(1, max(-1, value)) : 0 }
        let direction = CGVector(dx: normalized(gaze.dx) * (facingLeft ? -1 : 1), dy: normalized(gaze.dy))
        let spriteFrame: Int
        if pose.isOneShot {
            spriteFrame = min(pose == .reviving ? MascotPose.revivalFrames - 1 : 4, max(0, frame))
        } else {
            spriteFrame = ((frame % 960) + 960) % 960
        }
        Sprite(ctx: ctx).draw(pose: pose, frame: spriteFrame, gaze: direction,
                              agentCount: agentCount, mirrored: facingLeft)
        ctx.restoreGState()
    }
}
