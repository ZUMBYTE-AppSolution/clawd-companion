import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class OverlayController: NSObject {
    private typealias Side = ActiveWindowContact.Side
    private enum Move { case climb, rappel, stroll }
    private enum Stage { case approach, traverse, crest }

    private struct Trip {
        var move: Move
        var stage: Stage
        var start: CGPoint
        var began: TimeInterval
        var duration: TimeInterval
        var strollX: CGFloat = 0
        var entryFraction: CGFloat = 0
        var attachedRim: CGPoint?
    }

    private struct Pin {
        let target: WindowPinTarget
        var offset: WindowPinOffset
        var window: CGRect
        var hidden = false
    }

    private struct PinExcursion {
        let move: Move
        let began: TimeInterval
        let duration: TimeInterval
        let start: CGVector
        let delta: CGVector
    }

    private let arcade = ArcadeCoordinator()
    private let arena = VirusArenaPanel()
    private var arenaLayout: VirusArenaProjection?
    private var musicPhase: ArcadeMusicPhase?
    private var graveTimer: Timer?
    private var displaysAsleep = false
    private var sessionInactive = false
    private var panelArenaReserved = false
    var onArcadeStatus: ((ArcadeStatus) -> Void)? {
        didSet { onArcadeStatus?(arcade.status) }
    }
    var onArcadeGraveChanged: ((Date?) -> Void)?
    var onArenaEnvironmentPause: (() -> Void)?
    var onArcadeMusic: ((ArcadeMusicPhase?) -> Void)?
    var onArcadeRoundFinished: ((UUID, VirusArcade.RunStats) -> Void)?
    private let freePlay = PetPlayController()
    private var windowWander = WindowWander()
    private var scenery: [SceneryWindow] = []
    private var scenerySampledAt: TimeInterval = -.infinity
    private var nextSceneryScan: TimeInterval = 0
    private var pendingScenery = false
    private var sceneryGeneration: UInt = 0
    private var perchRequestDeadline: TimeInterval?
    private var explicitPerch = false
    var onPlayRound: ((Bool) -> Void)?
    var onSound: ((PetSound) -> Void)?
    private var nextFootstep: TimeInterval = 0
    private var nextGrip: TimeInterval = 0
    var hitCountForHUD: (() -> Int)? {
        didSet { freePlay.hitCountForHUD = hitCountForHUD }
    }
    var onDisplayPose: ((MascotPose) -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    private var ambientActive = false
    private var menuTracking = false
    private var pin: Pin?
    private var pinExcursion: PinExcursion?
    private var pinGeneration: UInt = 0
    private var selectingPin = false
    private var pendingPinProbe = false
    private var nextPinProbe: TimeInterval = 0
    private var pinMovingUntil: TimeInterval = 0
    private var menuPoint = CGPoint.zero
    private var agentCount = 0
    private var gaze = CGVector.zero
    private var explicitTrip = false

    private let pet = PetPanel()
    private let cord = PetPanel()
    private let bubble = PetPanel()
    private let speechBubble = PetSpeechBubble()
    private var speechVisible = false
    private let drawing = NSHostingView(rootView: MascotArt(pose: .idle))
    private let readout = NSHostingView(rootView: HoverReadout())
    private let hitMask = CGContext(data: nil, width: 56, height: 48, bitsPerComponent: 8, bytesPerRow: 56,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    private let input = PetInputView()
    private let onOpenPanel: () -> Void
    private let axQueue = DispatchQueue(label: "clawd.window-geometry", qos: .utility)
    private let defaults = UserDefaults.standard
    private static let positionKey = "ClawdCompanion.overlayOrigin"

    private var visible = false
    private var followsWindows = false
    private var prefersLessMotion = false
    private var reduced = false
    private var scale = 1.0
    private var establishedPosition = false
    private var activity = MascotPose.idle
    private var approval = ApprovalRoll()
    private var resumeAfterApproval = false
    private var drawn = MascotPose.idle
    private var facingLeft = false
    private var temporaryUntil: TimeInterval = 0
    private var timer: Timer?
    private var fastTimer = false
    private var trip: Trip?
    private var side = Side.right
    private var dockedAtTop: Bool?
    private var isDragging = false
    private var hoverSince: TimeInterval?

    private var pendingMove: Move?
    private var activeWindow: SceneryWindow?
    private var workWindowGeneration: UInt = 0
    private var workWindowMovingUntil: TimeInterval = 0
    private var pendingAX = false
    private var nextAXCheck: TimeInterval = 0

    init(onOpenPanel: @escaping () -> Void) {
        self.onOpenPanel = onOpenPanel
        super.init()
        arcade.onStatus = { [weak self] status in self?.onArcadeStatus?(status) }
        arcade.onRoundFinished = { [weak self] id, stats in self?.onArcadeRoundFinished?(id, stats) }
        arcade.onGraveChanged = { [weak self] date in
            self?.scheduleGraveTimer(until: date)
            self?.onArcadeGraveChanged?(date)
        }
        arena.onStrike = { [weak self] id in
            guard let self, canPresentBattle else { return }
            arcade.strike(id)
        }
        arena.onPickup = { [weak self] id in
            guard let self, canPresentBattle else { return }
            arcade.collect(id)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceCenter.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        freePlay.onRoundResolved = { [weak self] hit in self?.onPlayRound?(hit) }
        freePlay.onSound = { [weak self] sound in self?.onSound?(sound) }
        pet.setContentSize(NSSize(width: 105, height: 90))
        pet.contentView = input
        input.addSubview(drawing)
        drawing.frame = input.bounds
        drawing.autoresizingMask = [.width, .height]
        input.setAccessibilityElement(true)
        input.setAccessibilityRole(.button)
        refreshAccessibleLabels()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .clawdLanguageChanged, object: nil)
        input.onClick = onOpenPanel
        input.onDrag = { [weak self] point in
            guard let self else { return }
            guard !arcade.recovering else { return }
            if selectingPin { releasePin() }
            isDragging = true
            pauseArcade()
            cancelFreePlay()
            hideReadout()
            stopMotion()
            place(point)
            draw(activity)
        }
        input.onRelease = { [weak self] in
            guard let self else { return }
            isDragging = false
            if let pinned = pin { pin?.offset = WindowPinOffset(pet: pet.frame, window: pinned.window) }
            savePosition()
        }
        input.onMenu = { [weak self] event in self?.showMenu(event) }
        cord.contentView = CordView()
        cord.ignoresMouseEvents = true
        bubble.contentView = readout
        bubble.setContentSize(readout.fittingSize)
        bubble.ignoresMouseEvents = true
        bubble.hasShadow = true
        speechBubble.onPresent = { [weak self] in self?.onSound?(.notification) }
        speechBubble.onVisibilityChanged = { [weak self] showing in
            self?.speechVisible = showing
            if showing {
                self?.hideReadout()
                self?.pauseArcade()
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(motionPreferenceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func configure(visible: Bool, followsWindows: Bool, reducedMotion: Bool, scale: Double = 1) {
        let visibilityChanged = visible != self.visible
        if !visible {
            self.visible = false
            pauseArcade()
        }
        prefersLessMotion = reducedMotion
        motionPreferenceChanged()
        let followChanged = self.followsWindows != followsWindows
        if followChanged {
            self.followsWindows = followsWindows
            cancelWindowWander()
            activeWindow = nil
            nextAXCheck = 0
            stopMotion()
            draw(activity)
        }
        let newScale = scale.isFinite ? min(2.5, max(0.5, scale)) : 1
        if self.scale != newScale {
            pauseArcade()
            cancelFreePlay()
            self.scale = newScale
            pet.setContentSize(NSSize(width: 105 * newScale, height: 90 * newScale))
            if establishedPosition { place(pet.frame.origin) }
        }
        guard visibilityChanged else {
            if followChanged, visible, followsWindows, activityUsesLedge, approval.pose == nil { applyActivity() }
            return
        }
        self.visible = visible
        if visible {
            if !establishedPosition {
                if let raw = defaults.array(forKey: Self.positionKey) as? [Double],
                   raw.count == 2, raw.allSatisfy({ $0.isFinite }) {
                    place(CGPoint(x: raw[0], y: raw[1]))
                    establishedPosition = true
                } else { resetPosition() }
            }
            draw(activity)
            if pin?.hidden != true { pet.orderFrontRegardless() }
            nextPinProbe = 0
            updateTimer()
            if activityUsesLedge, followsWindows, approval.pose == nil { applyActivity() }
            tick()
        } else {
            if selectingPin { pinGeneration &+= 1; selectingPin = false }
            cancelFreePlay()
            stopMotion()
            hideReadout()
            speechBubble.dismissAll()
            timer?.invalidate()
            timer = nil
            pet.orderOut(nil)
            updateTimer()
        }
    }

    private func refreshAccessibleLabels() {
        input.setAccessibilityLabel(L("Claw’d, Status öffnen"))
        input.setAccessibilityHelp(L("Klicken für Status, ziehen zum Verschieben. Rechtsklick für Bewegungen."))
    }

    @objc private func languageChanged() {
        refreshAccessibleLabels()
        let old = readout.rootView
        setReadout(status: old.status, session: old.session, week: old.week, source: old.source)
        draw(drawn, force: true)
    }

    func setReadout(status: String, session: String, week: String, source: String) {
        let text = HoverReadout(status: status, session: session, week: week, source: source)
        guard readout.rootView != text else { return }
        readout.rootView = text
        bubble.setContentSize(readout.fittingSize)
        input.setAccessibilityValue([status, source, L("Sitzung {0}", session), L("Woche {0}", week)].joined(separator: ". "))
        if bubble.isVisible { showReadout() }
    }

    func speak(title: String, message: String, kind: String) {
        guard visible, pin?.hidden != true else { return }
        speechBubble.speak(title: title, message: message, kind: kind, anchor: pet.frame)
    }

    func clearSpeech() { speechBubble.dismissAll() }

    var hasAmbientArenaRound: Bool { arcade.hasRound }

    func takeArenaForPanel() -> (UUID, VirusArcade)? {
        let existing = arcade.takeForPanel()
        clearArena()
        return existing
    }

    func setPanelArenaReserved(_ reserved: Bool) {
        guard reserved != panelArenaReserved else { return }
        panelArenaReserved = reserved
        if reserved { pauseArcade() }
        tick()
    }

    func configureArcade(enabled: Bool, allowWhileActive: Bool) {
        guard enabled != arcade.enabled || allowWhileActive != arcade.allowWhileActive else { return }
        arcade.configure(enabled: enabled, allowWhileActive: allowWhileActive)
        tick()
    }

    func restoreArcadeGrave(until date: Date?) {
        guard let date else { return }
        pauseArcade()
        cancelFreePlay()
        stopMotion()
        arcade.restoreGrave(until: date)
        scheduleGraveTimer(until: date)
        tick()
    }

    @objc private func clockChanged() {
        guard arcade.graveUntil != nil else { return }
        scheduleGraveTimer(until: arcade.graveUntil)
        tick()
    }

    private func scheduleGraveTimer(until date: Date?) {
        graveTimer?.invalidate()
        graveTimer = nil
        guard let date else { return }
        // Absolute deadline also wakes the menu bar when the desktop pet is hidden.
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        graveTimer = timer
    }

    @discardableResult
    func requestArcade() -> Bool {
        guard !panelArenaReserved else { return false }
        guard visible, !reduced, arcade.request() else { return false }
        tick()
        return true
    }

    @objc private func sessionChanged(_ note: Notification) {
        switch note.name {
        case NSWorkspace.screensDidSleepNotification: displaysAsleep = true
        case NSWorkspace.screensDidWakeNotification: displaysAsleep = false
        case NSWorkspace.sessionDidResignActiveNotification: sessionInactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionInactive = false
        default: return
        }
        if displaysAsleep || sessionInactive { pauseArcade(); onArenaEnvironmentPause?() }
        tick()
    }

    private var canPresentBattle: Bool {
        !panelArenaReserved && visible && !reduced && !displaysAsleep && !sessionInactive && !isDragging && !input.hasPress &&
        pin == nil && !selectingPin && !menuTracking && !speechVisible && approval.pose == nil &&
        !resumeAfterApproval && agentCount == 0 && (activity == .idle || activity == .sleeping) &&
        !explicitTrip && !explicitPerch && !freePlay.bowInProgress && temporaryUntil == 0
    }

    private var arcadePose: MascotPose? {
        switch arcade.status {
        case .wave, .boss: return .virusFight
        case .grave: return .grave
        case .reviving: return .reviving
        case .victory: return .virusVictory
        default: return nil
        }
    }

    private func updateMusic(_ phase: ArcadeMusicPhase?) {
        guard phase != musicPhase else { return }
        musicPhase = phase
        onArcadeMusic?(phase)
    }

    private func pauseArcade() {
        let hadScene = arcadePose != nil
        arcade.pause()
        clearArena()
        if hadScene, arcadePose == nil { draw(activity) }
        updateTimer()
    }

    private func clearArena() {
        updateMusic(nil)
        guard arenaLayout != nil else { return }
        arena.hide()
        arenaLayout = nil
        let normalSize = CGSize(width: 105 * scale, height: 90 * scale)
        if pet.frame.size != normalSize {
            let center = CGPoint(x: pet.frame.midX, y: pet.frame.midY)
            pet.setContentSize(normalSize)
            place(CGPoint(x: center.x - normalSize.width / 2, y: center.y - normalSize.height / 2))
        }
    }

    private func updateArcade(now: TimeInterval) -> Bool {
        // CGEventTypes.h defines kCGAnyInputEventType as ((CGEventType)(~0)).
        // Read elapsed session input time without installing a keyboard monitor.
        let available = arcade.enabled && !arcade.recovering && canPresentBattle && !NSScreen.screens.isEmpty
        var idle: TimeInterval = 0
        if available, arcade.enabled, !arcade.allowWhileActive, !arcade.recovering,
           let anyInput = CGEventType(rawValue: UInt32.max) {
            idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }
        let previousPose = arcadePose
        let frame = arcade.tick(now: now, date: Date(), available: available, idleSeconds: idle)
        if let frame, available {
            if arcade.running { displayBattle(frame) }
            for cue in frame.cues { onSound?(cue.petSound) }
        }
        if !arcade.running { clearArena() }
        let pose = arcadePose
        if let pose {
            if pose == .reviving, previousPose != .reviving, visible, !reduced, !displaysAsleep, !sessionInactive {
                onSound?(.arcadeRevive)
            }
            draw(pose, lookingLeft: arenaLayout?.mirrored)
        } else if drawn == .virusFight || drawn == .grave || drawn == .reviving || drawn == .virusVictory {
            draw(activity)
            if previousPose == .reviving, approval.pose == nil { applyActivity() }
        }
        if pose != previousPose { updateTimer() }
        return pose != nil
    }

    private func displayBattle(_ frame: VirusArcade.Frame) {
        if arenaLayout == nil, let area = screen(for: pet.frame)?.visibleFrame {
            cancelFreePlay(restoreActivity: false)
            stopMotion()
            hideReadout()
            let layout = VirusArenaProjection(fitting: area, pet: pet.frame, hero: frame.hero)
            arenaLayout = layout
            let unit = layout.rect.width / VirusArcade.size.width
            let size = CGSize(width: 56 * unit, height: 48 * unit)
            if size != pet.frame.size { pet.setContentSize(size) }
        }
        guard let layout = arenaLayout else { return }
        let hero = layout.screenRect(CGRect(origin: frame.hero, size: .zero)).origin
        place(CGPoint(x: hero.x - pet.frame.width / 2, y: hero.y - pet.frame.height / 2), constrain: false)
        arena.display(frame, in: layout.rect, mirrored: layout.mirrored, acceptsInput: arcade.allowWhileActive)
        updateMusic(frame.phase == .boss ? .boss : .wave)
    }

    func configurePlay(roaming: Bool, chase: Bool, bow: Bool) {
        let changed = freePlay.roamingEnabled != roaming || freePlay.chaseEnabled != chase || freePlay.bowEnabled != bow
        if changed { cancelFreePlay() }
        freePlay.roamingEnabled = roaming
        freePlay.chaseEnabled = chase
        freePlay.bowEnabled = bow
        updateTimer()
    }

    @discardableResult
    func requestBow() -> Bool {
        requestShot { freePlay.requestBow() }
    }

    @discardableResult
    func requestLetterBlaster() -> Bool {
        requestShot { freePlay.requestLetters() }
    }

    private var canRequestPerch: Bool {
        visible && !arcade.recovering && !reduced && followsWindows && pin == nil && approval.pose == nil && !isDragging &&
        !speechVisible && agentCount == 0 && !freePlay.bowInProgress && (activity == .idle || activity == .sleeping)
    }

    @discardableResult
    func requestWindowPerch() -> Bool {
        guard canRequestPerch else { return false }
        pauseArcade()
        cancelFreePlay()
        stopMotion()
        explicitPerch = true
        perchRequestDeadline = ProcessInfo.processInfo.systemUptime + 2
        tick()
        return true
    }

    private func requestShot(_ startShot: () -> Void) -> Bool {
        guard visible, !arcade.recovering, !reduced, approval.pose == nil, freePlay.bowEnabled, !freePlay.bowInProgress, !isDragging,
              pin?.hidden != true, agentCount == 0, !speechVisible else { return false }
        pauseArcade()
        cancelWindowWander()
        stopMotion()
        startShot()
        tick()
        return true
    }

    func setAgentCount(_ count: Int) {
        let value = max(0, count)
        guard value != agentCount else { return }
        agentCount = value
        if value > 0 { pauseArcade(); cancelFreePlay() }
        if arcade.recovering { draw(activity); return }
        if !explicitTrip {
            stopMotion()
            if value == 0, activityUsesLedge, approval.pose == nil { applyActivity() }
            else { draw(activity, force: true) }
        }
    }

    func setPose(_ pose: MascotPose) {
        guard activity != pose else { return }
        activity = pose
        if pose != .idle && pose != .sleeping { pauseArcade() }
        guard approval.pose == nil, !resumeAfterApproval else { return }
        applyActivity()
    }

    func setApprovalWaiting(_ waiting: Bool) {
        guard approval.set(waiting: waiting, at: ProcessInfo.processInfo.systemUptime, reduced: reduced) else { return }
        if waiting {
            pauseArcade()
            cancelFreePlay(restoreActivity: false)
            let keepSeat = dockedAtTop == true
            stopMotion()
            if keepSeat { dockedAtTop = true }
        }
        resumeAfterApproval = approval.pose == nil
        draw(activity)
        updateTimer()
        tick()
    }

    private var activityUsesLedge: Bool {
        switch activity {
        case .typing, .planning, .researching, .reading, .executing, .drawing, .thinking: return true
        default: return false
        }
    }

    private var ledgePose: MascotPose {
        if let target = activeWindow, !ActiveWindowContact(window: target, size: pet.frame.size).canStand(side) {
            return activity == .idle || activity == .sleeping || activity == .climbing ? .climbing : activity
        }
        switch activity {
        case .idle, .sleeping, .climbing: return .perched
        case .thinking: return .perchThinking
        default: return activity
        }
    }

    private func applyActivity() {
        if arcade.recovering { draw(activity); return }
        let pose = activity
        temporaryUntil = 0
        // Only resolved Claude activity enters here. Games also draw a thinking
        // face after a dodge, so drawing that sprite must not trigger this cue.
        if visible, !reduced, !isDragging, pin?.hidden != true {
            switch pose {
            case .typing: onSound?(.typing)
            case .thinking: onSound?(.thinking)
            default: break
            }
        }
        if explicitTrip && (trip != nil || pendingMove != nil || pinExcursion != nil) { return }
        cancelFreePlay(restoreActivity: false)
        if agentCount > 0 { stopMotion(); draw(pose); return }
        guard visible, !isDragging, !reduced, pin?.hidden != true else { draw(pose); return }
        if activityUsesLedge, pin == nil {
            guard followsWindows else { stopMotion(); draw(pose); return }
            if trip?.move == .climb || pendingMove == .climb { return }
            if dockedAtTop == true, activeWindow != nil { draw(ledgePose); return }
            start(.climb)
            return
        }
        switch pose {
        case .typing, .climbing: start(.climb)
        case .happy, .rappelling: start(.rappel)
        case .walking: start(.stroll)
        default:
            if dockedAtTop == true, pin == nil {
                draw(ledgePose)
            } else {
                stopMotion()
                draw(pose)
            }
        }
    }

    func perform(_ pose: MascotPose) {
        guard visible, !arcade.recovering, approval.pose == nil, !isDragging, pin?.hidden != true else { return }
        pauseArcade()
        cancelFreePlay()
        if !reduced {
            switch pose {
            case .walking: start(.stroll, manual: true); return
            case .climbing: start(.climb, manual: true); return
            case .rappelling: start(.rappel, manual: true); return
            default: break
            }
        }
        stopMotion()
        draw(pose)
        temporaryUntil = ProcessInfo.processInfo.systemUptime + 2.5
    }

    func resetPosition() {
        pauseArcade()
        releasePin()
        cancelFreePlay()
        stopMotion()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        place(CGPoint(x: bounds.maxX - pet.frame.width - 42, y: bounds.minY + 12), on: screen)
        establishedPosition = true
        savePosition()
        draw(activity)
    }

    @objc private func motionPreferenceChanged() {
        let newValue = prefersLessMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard reduced != newValue else { return }
        reduced = newValue
        if reduced { pauseArcade() }
        if approval.advance(to: ProcessInfo.processInfo.systemUptime, reduced: reduced), approval.pose == nil {
            resumeAfterApproval = true
        }
        cancelFreePlay()
        speechBubble.reducedMotion = newValue
        stopMotion()
        draw(activity, force: true)
        updateTimer()
    }

    @objc private func screensChanged() {
        pauseArcade()
        cancelFreePlay()
        nextPinProbe = 0
        activeWindow = nil
        workWindowGeneration &+= 1
        if establishedPosition { place(pet.frame.origin) }
        else if visible { resetPosition() }
    }

    private func draw(_ requested: MascotPose, lookingLeft: Bool? = nil, force: Bool = false,
                      blasterGaze: CGVector? = nil) {
        let pose = arcadePose ?? approval.pose ?? (agentCount > 0 && !explicitTrip ? .juggling : requested)
        let changed = pose != drawn
        let direction = lookingLeft ?? facingLeft
        let aim = pose == .letterBlaster ? blasterGaze ?? BlasterAim(pet: pet.frame, cursor: NSEvent.mouseLocation, facingLeft: direction).gaze : gaze
        guard force || pose != drawn || facingLeft != direction || gaze != aim else { return }
        gaze = aim
        drawn = pose
        facingLeft = direction
        drawing.rootView = MascotArt(pose: pose, facingLeft: direction, reducedMotion: reduced, gaze: gaze,
                                     agentCount: agentCount, transitionStart: pose == .reviving ? arcade.revivalStart : approval.started)
        if changed {
            onDisplayPose?(pose)
            guard visible, !reduced, !isDragging, pin?.hidden != true else { return }
            switch pose {
            case .jumping: onSound?(.jump)
            case .landing: onSound?(.land)
            case .peek: onSound?(.peek)
            case .rappelling: onSound?(.rappel)
            case .juggling: onSound?(.juggle)
            case .dancing, .happy: onSound?(.celebrate)
            default: break
            }
        }
    }

    private func soundStride(from previous: CGPoint, now: TimeInterval) {
        guard !reduced, previous != pet.frame.origin,
              trip != nil || pinExcursion != nil || ambientActive else { return }
        switch drawn {
        case .walking where now >= nextFootstep:
            nextFootstep = now + 0.84
            onSound?(.steps)
        case .climbing where now >= nextGrip:
            nextGrip = now + 0.96
            onSound?(.climb)
        default: break
        }
    }

    private func updateGaze() {
        // The salvo supplies the same aim sample that positioned the current
        // muzzle and released this frame's letter.
        guard drawn != .letterBlaster else { return }
        let cursor = NSEvent.mouseLocation
        let center = CGPoint(x: pet.frame.midX, y: pet.frame.minY + pet.frame.height * 0.51)
        let dx = cursor.x - center.x, dy = cursor.y - center.y
        let length = max(45 * scale, hypot(dx, dy))
        let value = reduced ? CGVector.zero : CGVector(dx: (dx / length * 2).rounded() / 2,
                                                      dy: (dy / length * 2).rounded() / 2)
        guard value != gaze else { return }
        gaze = value
        draw(drawn, force: true)
    }

    private func start(_ move: Move, manual: Bool = false) {
        stopMotion()
        explicitTrip = manual
        let now = ProcessInfo.processInfo.systemUptime
        if let pin {
            guard !pin.hidden, let screen = screen(for: pet.frame) else { explicitTrip = false; return }
            let home = pin.offset.origin(in: pin.window, petSize: pet.frame.size)
            let room = screen.visibleFrame
            var delta = CGVector.zero
            if move == .stroll {
                let distance = home.x < room.midX ? room.maxX - pet.frame.width - home.x : room.minX - home.x
                delta.dx = max(-90 * scale, min(90 * scale, distance))
            } else {
                let up = max(0, room.maxY - home.y - pet.frame.height)
                let down = max(0, home.y - room.minY)
                let goUp = move == .climb ? (up > 24 || up >= down) : (down < 24 && up > down)
                delta.dy = goUp ? min(up, 150 * scale) : -min(down, 150 * scale)
            }
            let from = CGVector(dx: pet.frame.minX - home.x, dy: pet.frame.minY - home.y)
            let distance = max(hypot(delta.dx - from.dx, delta.dy - from.dy), hypot(delta.dx, delta.dy))
            pinExcursion = PinExcursion(move: move, began: now, duration: max(0.55, distance / (115 * scale)), start: from, delta: delta)
            updateTimer()
            tick()
            return
        }
        if move == .stroll { beginTrip(move, now: now); return }
        guard followsWindows || manual else { draw(activity); return }
        // Discover the actual window before choosing a side. An asynchronous
        // lookup must never send the pet towards a temporary display rectangle.
        activeWindow = nil
        pendingMove = move
        nextAXCheck = 0
        refreshWindow(now: now)
        updateTimer()
    }

    private func beginTrip(_ move: Move, now: TimeInterval) {
        guard let anchor = currentAnchor(for: move) else { return }
        pendingMove = nil
        let position = pet.frame.origin
        if let contact = anchor.contact { side = contact.side(near: pet.frame.midX) }
        let stage: Stage
        let destination: CGPoint
        var entryFraction: CGFloat = 0
        switch move {
        case .stroll:
            let room = anchor.screen.visibleFrame
            let direction: CGFloat = position.x + pet.frame.width / 2 > room.midX ? -1 : 1
            destination = bounded(CGPoint(x: position.x + direction * 160 * scale, y: position.y),
                                  within: (screen(for: pet.frame) ?? anchor.screen).visibleFrame)
            stage = .traverse
        case .climb, .rappel:
            let bottom = edgePoint(side, upper: false, anchor: anchor)
            let top = edgePoint(side, upper: true, anchor: anchor)
            let height = max(1, top.y - bottom.y)
            entryFraction = max(0, min(1, (position.y - bottom.y) / height))
            // Keep the current altitude when Claude finishes in the middle of a climb.
            // From a resting spot with little room, first move to the opposite end.
            let remaining = move == .climb ? 1 - entryFraction : entryFraction
            if remaining * height < min(70 * scale, height * 0.45) {
                entryFraction = move == .climb ? 0 : 1
            }
            destination = CGPoint(x: bottom.x, y: bottom.y + height * entryFraction)
            stage = .approach
        }
        let duration = travelTime(from: position, to: destination, speed: 490)
        trip = Trip(move: move, stage: stage, start: position, began: now,
                    duration: duration, strollX: destination.x, entryFraction: entryFraction)
        updateTimer()
        tick()
    }

    private func stopMotion() {
        explicitTrip = false
        workWindowGeneration &+= 1
        pendingMove = nil
        pinExcursion = nil
        trip = nil
        dockedAtTop = nil
        temporaryUntil = 0
        cord.orderOut(nil)
        updateTimer()
    }

    private func updateTimer() {
        // While the desktop is hidden the menu bar only needs the two short
        // roll transitions. Holding the sign then costs no extra overlay timer.
        guard visible || approval.started != nil || arcade.revivalStart != nil else {
            timer?.invalidate()
            timer = nil
            return
        }
        let followingPin = pin != nil && pinMovingUntil > ProcessInfo.processInfo.systemUptime
        let fast = arcade.running || trip != nil || pinExcursion != nil || freePlay.needsFastTicks || windowWander.isActive || followingPin
        guard timer == nil || fast != fastTimer else { return }
        timer?.invalidate()
        fastTimer = fast
        let interval = fast ? 1.0 / 30 : 0.09
        let fresh = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.tick() }
        }
        fresh.tolerance = interval * 0.15
        RunLoop.main.add(fresh, forMode: .common)
        timer = fresh
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if approval.advance(to: now, reduced: reduced) {
            resumeAfterApproval = approval.pose == nil
            draw(activity)
            updateTimer()
        }
        let showsArcade = updateArcade(now: now)
        guard visible else { return }
        guard !menuTracking, !selectingPin else { return }
        if pin != nil { refreshPin(now: now) }
        guard pin?.hidden != true else { return }
        updateHitRegion()
        if showsArcade {
            if let pin, !isDragging, !input.hasPress { followPin(pin, now: now) }
            return
        }
        guard !isDragging, !input.hasPress else { cancelFreePlay(); return }
        let previous = pet.frame.origin
        defer { soundStride(from: previous, now: now) }
        updateGaze()
        if approval.pose != nil {
            if let pin { followPin(pin, now: now) }
            else if dockedAtTop == true {
                refreshWindow(now: now)
                if let anchor = currentAnchor(), let contact = anchor.contact {
                    place(contact.rest(side, pose: .awaitingApproval), on: anchor.screen, constrain: false)
                }
            }
            return
        }
        if resumeAfterApproval {
            resumeAfterApproval = false
            applyActivity()
            return
        }
        if temporaryUntil > 0, now >= temporaryUntil {
            temporaryUntil = 0
            draw(activity)
        }
        if let pin {
            followPin(pin, now: now)
            if pinExcursion == nil { updateFreePlay(now: now) }
            updateTimer()
            return
        }
        if pendingMove != nil || (trip != nil && trip?.move != .stroll) || dockedAtTop != nil {
            refreshWindow(now: now)
        }
        if pendingMove != nil { return }
        guard let step = trip else {
            if updateFreePlay(now: now) { return }
            if let upper = dockedAtTop, !reduced, let anchor = currentAnchor() {
                let point = upper ? anchor.contact?.rest(side, pose: ledgePose) : nil
                place(point ?? edgePoint(side, upper: upper, anchor: anchor), on: anchor.screen, constrain: false)
            }
            return
        }
        guard let anchor = currentAnchor(for: step.move) else { stopMotion(); draw(activity); return }
        let destination: CGPoint
        if step.move == .stroll {
            destination = CGPoint(x: step.strollX, y: step.start.y)
        } else if step.stage == .crest, let contact = anchor.contact {
            destination = contact.rest(side, pose: ledgePose)
        } else if step.stage == .approach {
            let bottom = edgePoint(side, upper: false, anchor: anchor)
            let top = edgePoint(side, upper: true, anchor: anchor)
            destination = CGPoint(x: bottom.x, y: bottom.y + (top.y - bottom.y) * step.entryFraction)
        } else {
            destination = edgePoint(side, upper: step.move == .climb, anchor: anchor)
        }
        let progress = max(0, min(1, (now - step.began) / step.duration))
        let ease = progress * progress * (3 - 2 * progress)
        var start = step.start
        if let attached = step.attachedRim {
            let edge = side == .left ? anchor.rect.minX : anchor.rect.maxX
            start.x += edge - attached.x
            start.y += anchor.rect.maxY - attached.y
        }
        let point = CGPoint(x: start.x + (destination.x - start.x) * ease,
                            y: start.y + (destination.y - start.y) * ease)
        // The measured grip may use a few transparent top rows at the menu bar.
        // The approach still needs normal clamping while it crosses displays.
        let nearWall = anchor.contact != nil && anchor.screen.visibleFrame.insetBy(dx: -pet.frame.width / 2,
                                                                                  dy: -pet.frame.height / 2).contains(point)
        if nearWall { place(point, on: anchor.screen, constrain: false) }
        else { place(point) }
        let gripLeft = looksLeft(at: side, anchor: anchor)
        if step.stage == .approach, abs(destination.x - step.start.x) < pet.frame.width / 2,
           abs(destination.y - step.start.y) > 20 {
            let upward = destination.y > step.start.y
            draw(upward ? .climbing : .rappelling, lookingLeft: gripLeft)
            if !upward { showCord(top: step.start.y + pet.frame.height, anchor: anchor) }
        } else if step.stage == .approach || step.move == .stroll {
            draw(.walking, lookingLeft: destination.x < step.start.x)
        } else {
            draw(step.move == .climb ? .climbing : .rappelling, lookingLeft: gripLeft)
            if step.move == .rappel { showCord(top: anchor.rect.maxY, anchor: anchor) }
        }
        guard progress >= 1 else { return }
        if step.stage == .approach {
            cord.orderOut(nil)
            let endpoint = edgePoint(side, upper: step.move == .climb, anchor: anchor)
            trip = Trip(move: step.move, stage: .traverse, start: pet.frame.origin, began: now,
                        duration: travelTime(from: pet.frame.origin, to: endpoint,
                                             speed: step.move == .climb ? 235 : 350),
                        attachedRim: CGPoint(x: side == .left ? anchor.rect.minX : anchor.rect.maxX, y: anchor.rect.maxY))
        } else if step.move == .climb, step.stage == .traverse, let contact = anchor.contact, contact.canStand(side) {
            let end = contact.rest(side, pose: ledgePose)
            trip = Trip(move: .climb, stage: .crest, start: pet.frame.origin, began: now,
                        duration: travelTime(from: pet.frame.origin, to: end, speed: 220),
                        attachedRim: CGPoint(x: side == .left ? anchor.rect.minX : anchor.rect.maxX, y: anchor.rect.maxY))
        } else {
            trip = nil
            explicitTrip = false
            dockedAtTop = step.move == .stroll ? nil : step.move == .climb
            cord.orderOut(nil)
            draw(step.move == .climb ? ledgePose : activity)
            savePosition()
            updateTimer()
        }
    }

    private func cancelFreePlay(restoreActivity: Bool = true) {
        freePlay.cancel()
        cancelWindowWander()
        if ambientActive {
            ambientActive = false
            if restoreActivity { draw(activity) }
        }
        updateTimer()
    }

    private func cancelWindowWander() {
        windowWander.cancel()
        perchRequestDeadline = nil
        explicitPerch = false
        sceneryGeneration &+= 1
        scenery.removeAll()
        scenerySampledAt = -.infinity
        nextSceneryScan = 0
    }

    @discardableResult
    private func updateFreePlay(now: TimeInterval) -> Bool {
        let idle = activity == .idle || activity == .sleeping
        let hovered = bubble.isVisible || hoverSince != nil
        guard !reduced, !speechVisible, !hovered || freePlay.bowInProgress || explicitPerch, !isDragging, !input.hasPress,
              agentCount == 0, idle || freePlay.bowInProgress, temporaryUntil == 0 else {
            if ambientActive || freePlay.needsFastTicks { cancelFreePlay() }
            return false
        }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let result = nextPlayFrame(now: now, screens: screens)
        if let frame = result {
            ambientActive = true
            if let origin = frame.origin, pin == nil { dockedAtTop = nil; place(origin, constrain: false) }
            draw(frame.pose, lookingLeft: frame.facingLeft, blasterGaze: frame.blasterGaze)
        } else if ambientActive {
            ambientActive = false
            draw(activity)
        }
        updateTimer()
        return result != nil
    }

    private func nextPlayFrame(now: TimeInterval, screens: [CGRect]) -> PetPlayFrame? {
        let mayClimb = pin == nil && followsWindows && (freePlay.roamingEnabled || explicitPerch) && !freePlay.bowInProgress
        let wasTraversing = windowWander.isActive
        if perchRequestDeadline != nil { return wanderFrame(now: now, screens: screens) }
        if wasTraversing, mayClimb, let frame = wanderFrame(now: now, screens: screens) {
            return frame
        }
        if !windowWander.isActive { explicitPerch = false }
        let ordinary = freePlay.tick(now: now, pet: pet.frame, cursor: NSEvent.mouseLocation,
                                     screens: screens, mayRoam: pin == nil)
        if !wasTraversing, mayClimb, let frame = wanderFrame(now: now, screens: screens) {
            freePlay.yieldWalk()
            nextSceneryScan = 0
            return frame
        }
        return ordinary
    }

    private func wanderFrame(now: TimeInterval, screens: [CGRect]) -> PetPlayFrame? {
        let petFrame = pet.frame
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) else {
            windowWander.cancel()
            return nil
        }
        let requested = perchRequestDeadline != nil
        if freePlay.isWalking || windowWander.isActive || requested { refreshScenery(now: now, screens: screens) }
        // A delayed WindowServer read must not keep a vanished ledge alive.
        let fresh = now - scenerySampledAt <= 0.8
        guard let frame = windowWander.tick(now: now, pet: petFrame, screen: screen,
                                            windows: fresh ? scenery : [], mayStart: fresh && freePlay.isWalking,
                                            requestSeat: requested && fresh)
        else {
            if requested, fresh || now >= (perchRequestDeadline ?? .infinity) {
                perchRequestDeadline = nil
                explicitPerch = false
                speak(title: "Claw’d", message: L("Dieses Fenster hat auf diesem Bildschirm gerade keine freie Sitzkante."), kind: "info")
            }
            return nil
        }
        perchRequestDeadline = nil
        return PetPlayFrame(origin: frame.origin, pose: frame.pose, facingLeft: frame.facingLeft)
    }

    private func refreshScenery(now: TimeInterval, screens: [CGRect]) {
        guard !pendingScenery, now >= nextSceneryScan, let primary = NSScreen.screens.first else { return }
        nextSceneryScan = now + (windowWander.isActive ? 0.14 : 1.25)
        pendingScenery = true
        let generation = sceneryGeneration, top = primary.frame.maxY, size = pet.frame.size
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let localWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let localFrame = localWindow.flatMap { $0.isVisible && !($0 is PetPanel) ? $0.frame : nil }
        let own = ProcessInfo.processInfo.processIdentifier
        let useAX = front != nil && front != own && Self.hasAccessibilityPermission
        let displays = NSScreen.screens.map(\.frame)
        axQueue.async { [weak self] in
            let focus: CGRect?
            if front == own { focus = localFrame }
            else if useAX, let front { focus = Self.readWindow(pid: front).map { WindowPinTarget.quartzFlip($0, primaryTop: top) } }
            else { focus = nil }
            let windows = WindowScenery.snapshot(primaryTop: top, screens: screens, petSize: size,
                activePID: front, focusedFrame: focus, displayFrames: displays)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingScenery = false
                guard self.sceneryGeneration == generation else { return }
                self.scenery = windows
                self.scenerySampledAt = now
            }
        }
    }

    private func followPin(_ pin: Pin, now: TimeInterval) {
        let home = pin.offset.origin(in: pin.window, petSize: pet.frame.size)
        guard let motion = pinExcursion else { place(home, constrain: false); return }
        let elapsed = (now - motion.began) / motion.duration
        if elapsed >= 2 {
            pinExcursion = nil
            explicitTrip = false
            cord.orderOut(nil)
            place(home, constrain: false)
            draw(activity)
            updateTimer()
            return
        }
        let outbound = elapsed < 1
        let t = max(0, min(1, outbound ? elapsed : 2 - elapsed))
        let eased = t * t * (3 - 2 * t)
        let start = outbound ? motion.start : .zero
        place(CGPoint(x: home.x + start.dx + (motion.delta.dx - start.dx) * eased,
                      y: home.y + start.dy + (motion.delta.dy - start.dy) * eased), constrain: false)
        if motion.move == .stroll {
            draw(.walking, lookingLeft: outbound ? motion.delta.dx < start.dx : motion.delta.dx > 0)
        } else {
            let climbing = outbound ? motion.delta.dy > start.dy : motion.delta.dy < 0
            draw(climbing ? .climbing : .rappelling)
            let hand = facingLeft ? 15.0 / 56 : 41.0 / 56
            let peg = CGPoint(x: home.x + pet.frame.width * hand,
                              y: home.y + max(0, motion.delta.dy, motion.start.dy) + pet.frame.height)
            showCord(top: peg.y, pegX: peg.x)
        }
    }

    private func travelTime(from: CGPoint, to: CGPoint, speed: Double) -> Double {
        min(3.6, max(0.10, hypot(from.x - to.x, from.y - to.y) / (speed * scale)))
    }

    private typealias Anchor = (rect: CGRect, screen: NSScreen, contact: ActiveWindowContact?)

    private func currentAnchor(for move: Move? = nil) -> Anchor? {
        if move == .stroll, let display = screen(for: pet.frame) { return (display.visibleFrame, display, nil) }
        guard let target = activeWindow, let display = NSScreen.screens.first(where: { $0.visibleFrame == target.screen }) else { return nil }
        return (target.frame, display, ActiveWindowContact(window: target, size: pet.frame.size))
    }

    private func edgePoint(_ side: Side, upper: Bool, anchor: Anchor) -> CGPoint {
        guard let contact = anchor.contact else { return pet.frame.origin }
        return contact.wall(side, upper: upper)
    }

    private func looksLeft(at side: Side, anchor: Anchor) -> Bool { anchor.contact?.looksLeft(on: side) ?? false }

    private func screen(for rect: CGRect) -> NSScreen? {
        // Prefer the nearest display even when a saved display was removed.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.min { a, b in
            func score(_ screen: NSScreen) -> (Double, Double) {
                let box = screen.frame, intersection = box.intersection(rect)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                let distance = hypot(max(0, box.minX - center.x, center.x - box.maxX),
                                     max(0, box.minY - center.y, center.y - box.maxY))
                return (-area, distance)
            }
            return score(a) < score(b)
        }
    }

    private func bounded(_ origin: CGPoint, within area: CGRect) -> CGPoint {
        let clearMargin = pet.frame.width * 5 / 56
        return CGPoint(x: max(area.minX - clearMargin, min(origin.x, area.maxX - pet.frame.width + clearMargin)),
                y: max(area.minY, min(origin.y, area.maxY - pet.frame.height)))
    }

    private func place(_ origin: CGPoint, on screen: NSScreen? = nil, constrain: Bool = true) {
        guard let screen = screen ?? self.screen(for: CGRect(origin: origin, size: pet.frame.size)) else { return }
        let point = constrain ? bounded(origin, within: screen.visibleFrame) : origin
        let backing = max(1, screen.backingScaleFactor)
        let aligned = CGPoint(x: (point.x * backing).rounded() / backing,
                              y: (point.y * backing).rounded() / backing)
        if pet.frame.origin != aligned { pet.setFrameOrigin(aligned) }
        if speechVisible { speechBubble.updateAnchor(pet.frame) }
    }

    private func savePosition() {
        defaults.set([pet.frame.minX, pet.frame.minY], forKey: Self.positionKey)
    }

    private func showCord(top: CGFloat, anchor: Anchor) {
        showCord(top: top, pegX: side == .left ? anchor.rect.minX : anchor.rect.maxX)
    }

    private func showCord(top: CGFloat, pegX edge: CGFloat) {
        let height = top - pet.frame.maxY
        guard height > 1 else { cord.orderOut(nil); return }
        let hand = facingLeft ? 15.0 / 56 : 41.0 / 56
        let x = pet.frame.minX + pet.frame.width * hand
        let left = min(x, edge) - 4
        if let rope = cord.contentView as? CordView {
            rope.handX = x - left
            rope.pegX = edge - left
            rope.needsDisplay = true
        }
        cord.setFrame(CGRect(x: left, y: pet.frame.maxY, width: abs(x-edge) + 8, height: height), display: true)
        if !cord.isVisible { cord.order(.below, relativeTo: pet.windowNumber) }
    }

    private func updateHitRegion() {
        guard !isDragging, !input.hasPress else { hideReadout(); return }
        let hit = hitsSprite(NSEvent.mouseLocation)
        let shouldIgnore = !hit
        if pet.ignoresMouseEvents != shouldIgnore { pet.ignoresMouseEvents = shouldIgnore }
        if hit && !arcade.running && !speechVisible && !freePlay.bowInProgress {
            let now = ProcessInfo.processInfo.systemUptime
            if hoverSince == nil { hoverSince = now }
            if let hoverSince, now - hoverSince >= 0.25 { showReadout() }
        } else { hideReadout() }
    }

    private func hitsSprite(_ mouse: CGPoint) -> Bool {
        let area = pet.frame
        guard area.contains(mouse), area.width > 0, area.height > 0 else { return false }
        guard let mask = hitMask, let bytes = mask.data?.assumingMemoryBound(to: UInt8.self) else {
            return area.insetBy(dx: area.width * 0.10, dy: area.height * 0.12).contains(mouse)
        }
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: 56, height: 48))
        let start = drawn == .reviving ? arcade.revivalStart : approval.started
        let transition = drawn.isOneShot ? start : nil
        let frame = reduced ? drawn.stillFrame : transition.map {
            MascotArt.transitionFrame(since: $0, now: ProcessInfo.processInfo.systemUptime, pose: drawn)
        } ?? Int(Date().timeIntervalSinceReferenceDate * 8) % 960
        MascotPixels.draw(in: mask, size: CGSize(width: 56, height: 48),
                         pose: drawn, facingLeft: facingLeft, frame: frame, gaze: gaze, agentCount: agentCount)
        // Core Graphics stores scanlines in the opposite direction to the drawing coordinates.
        let x = max(0, min(55, Int((mouse.x - area.minX) / area.width * 56)))
        let y = max(0, min(47, Int((mouse.y - area.minY) / area.height * 48)))
        for row in max(0, y - 1)...min(47, y + 1) {
            for col in max(0, x - 1)...min(55, x + 1) where bytes[row * mask.bytesPerRow + col] != 0 { return true }
        }
        return false
    }

    private func showReadout() {
        guard let area = screen(for: pet.frame)?.visibleFrame else { return }
        let size = bubble.frame.size
        let x = min(max(pet.frame.midX - size.width / 2, area.minX + 5), area.maxX - size.width - 5)
        let above = pet.frame.maxY + 3
        let y = above + size.height <= area.maxY - 5 ? above : max(area.minY + 5, pet.frame.minY - size.height - 3)
        let origin = CGPoint(x: x.rounded(), y: y.rounded())
        if bubble.frame.origin != origin { bubble.setFrameOrigin(origin) }
        if !bubble.isVisible { bubble.order(.above, relativeTo: pet.windowNumber) }
    }

    private func hideReadout() {
        hoverSince = nil
        if bubble.isVisible { bubble.orderOut(nil) }
    }

    private func refreshWindow(now: TimeInterval) {
        guard now >= nextAXCheck, !pendingAX, let primary = NSScreen.screens.first else { return }
        nextAXCheck = now + (trip != nil || now < workWindowMovingUntil ? 0.14 : 0.35)
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        let control = NSApp.keyWindow ?? NSApp.mainWindow
        let ownFrame = pid == own && control?.isVisible == true && !(control is PetPanel) ? control?.frame : nil
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame), frames = screens.map(\.frame)
        let primaryTop = primary.frame.maxY, size = pet.frame.size, generation = workWindowGeneration
        let mayReadFocus = pid != own && Self.hasAccessibilityPermission
        pendingAX = true
        axQueue.async { [weak self] in
            let focus = ownFrame ?? (mayReadFocus ? pid.flatMap { Self.readWindow(pid: $0) }.map {
                WindowPinTarget.quartzFlip($0, primaryTop: primaryTop)
            } : nil)
            let candidates = WindowScenery.snapshot(primaryTop: primaryTop, screens: visibleFrames, petSize: size,
                                                    activePID: pid, focusedFrame: focus, displayFrames: frames)
            let selected = candidates.first(where: \.isActive)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingAX = false
                guard generation == self.workWindowGeneration, self.visible, self.pin == nil,
                      (self.approval.pose == nil || self.dockedAtTop == true),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.applyWindowSample(selected)
            }
        }
    }

    private func applyWindowSample(_ selected: SceneryWindow?) {
        let previous = activeWindow
        activeWindow = selected
        if let move = pendingMove {
            if selected != nil { beginTrip(move, now: ProcessInfo.processInfo.systemUptime) }
            else {
                explicitTrip = false
                if move != .climb || !activityUsesLedge || !followsWindows { pendingMove = nil }
                nextAXCheck = ProcessInfo.processInfo.systemUptime + 1.2
                draw(activity)
            }
            return
        }
        guard let previous else { return }
        let same = selected?.id == previous.id && selected?.pid == previous.pid
        if let selected, same, selected.frame != previous.frame {
            workWindowMovingUntil = ProcessInfo.processInfo.systemUptime + 0.6
        }
        if !same || selected.map({ !ActiveWindowContact(window: $0, size: pet.frame.size).clear(side) }) == true {
            stopMotion()
            draw(activity)
            if activityUsesLedge && followsWindows && approval.pose == nil {
                pendingMove = .climb
                if selected != nil { beginTrip(.climb, now: ProcessInfo.processInfo.systemUptime) }
            }
        } else if dockedAtTop == true {
            draw(ledgePose)
        }
    }

    // Geometry is the only data read from the focused application.
    private nonisolated static func readWindow(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.16)
        var object: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &object) == .success,
              let ref = object,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return WindowPinTarget.bounds(of: ref as! AXUIElement)
    }

    func releasePin() {
        pinGeneration &+= 1
        selectingPin = false
        pendingPinProbe = false
        guard pin != nil else { return }
        let wasHidden = pin?.hidden == true
        pin = nil
        pinMovingUntil = 0
        cancelFreePlay()
        stopMotion()
        if visible && wasHidden { pet.orderFrontRegardless() }
        place(pet.frame.origin)
        draw(activity)
        onPinChanged?(false)
    }

    @objc private func togglePin() {
        if pin != nil { releasePin(); return }
        guard let primary = NSScreen.screens.first else { return }
        cancelFreePlay()
        stopMotion()
        selectingPin = true
        pinGeneration &+= 1
        let generation = pinGeneration, point = menuPoint, frame = pet.frame, top = primary.frame.maxY
        axQueue.async { [weak self] in
            let selection = WindowPinTarget.capture(at: point, pet: frame, primaryTop: top)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pinGeneration == generation else { return }
                self.selectingPin = false
                guard let (target, window) = selection else {
                    self.speak(title: L("An Fenster heften"), message: L("Zieh mich auf das gewünschte Fenster oder an seine Kante und wähle den Pin erneut."), kind: "info")
                    return
                }
                self.pin = Pin(target: target, offset: WindowPinOffset(pet: frame, window: window), window: window)
                self.nextPinProbe = 0
                self.onPinChanged?(true)
                self.tick()
            }
        }
    }

    private func refreshPin(now: TimeInterval) {
        guard let pin, !pendingPinProbe, now >= nextPinProbe, let primary = NSScreen.screens.first else { return }
        nextPinProbe = now + (pin.hidden ? 0.35 : (now < pinMovingUntil ? 0.025 : 0.075))
        pendingPinProbe = true
        let target = pin.target, generation = pinGeneration, top = primary.frame.maxY
        axQueue.async { [weak self] in
            let state = target.read(primaryTop: top)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pinGeneration == generation else { return }
                self.pendingPinProbe = false
                switch state {
                case .visible(let window):
                    if self.pin?.window != window {
                        self.pinMovingUntil = ProcessInfo.processInfo.systemUptime + 0.35
                        self.nextPinProbe = 0
                        self.updateTimer()
                    }
                    self.pin?.window = window
                    self.setPinHidden(!NSScreen.screens.contains { $0.frame.intersects(window) })
                    if self.visible, let current = self.pin, !current.hidden, !self.isDragging, !self.menuTracking {
                        self.followPin(current, now: ProcessInfo.processInfo.systemUptime)
                    }
                case .hidden: self.setPinHidden(true)
                case .closed: self.releasePin()
                case .unavailable: break
                }
            }
        }
    }

    private func setPinHidden(_ hidden: Bool) {
        guard pin?.hidden != hidden else { return }
        pin?.hidden = hidden
        if hidden {
            cancelFreePlay()
            stopMotion()
            hideReadout()
            speechBubble.dismissAll()
            pet.orderOut(nil)
        } else if visible { pet.orderFrontRegardless() }
    }

    private func showMenu(_ event: NSEvent) {
        menuPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        menuTracking = true
        pauseArcade()
        cancelFreePlay()
        hideReadout()
        defer { menuTracking = false }
        let menu = NSMenu()
        let pinItem = menu.addItem(withTitle: pin == nil ? L("Pin to Window · An Fenster heften") : L("Fenster-Pin lösen"),
                                   action: #selector(togglePin), keyEquivalent: "")
        pinItem.target = self
        let seat = menu.addItem(withTitle: L("Auf Titelleiste setzen"), action: #selector(perchFromMenu), keyEquivalent: "")
        seat.target = self
        seat.isEnabled = canRequestPerch
        menu.addItem(.separator())
        for (label, action) in [
            (L("Status öffnen"), #selector(openStatus)), (L("Spazieren"), #selector(walk)),
            (L("Hochklettern"), #selector(climb)), (L("Abseilen"), #selector(rappel)),
            (L("Freuen"), #selector(cheer)), (L("Position zurücksetzen"), #selector(resetFromMenu))
        ] {
            let item = menu.addItem(withTitle: label, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = (!arcade.recovering && approval.pose == nil) || action == #selector(openStatus) || action == #selector(resetFromMenu)
        }
        let bow = menu.addItem(withTitle: L("Codebogen spannen"), action: #selector(bowFromMenu), keyEquivalent: "")
        bow.target = self
        bow.isEnabled = !arcade.recovering && approval.pose == nil && !reduced && agentCount == 0 && freePlay.bowEnabled && !freePlay.bowInProgress && !speechVisible
        let letters = menu.addItem(withTitle: L("Buchstabensalve testen"), action: #selector(lettersFromMenu), keyEquivalent: "")
        letters.target = self
        letters.isEnabled = bow.isEnabled
        menu.autoenablesItems = false
        NSMenu.popUpContextMenu(menu, with: event, for: input)
    }
    @objc private func bowFromMenu() { requestBow() }
    @objc private func lettersFromMenu() { requestLetterBlaster() }
    @objc private func perchFromMenu() { requestWindowPerch() }
    @objc private func openStatus() { onOpenPanel() }
    @objc private func walk() { perform(.walking) }
    @objc private func climb() { perform(.climbing) }
    @objc private func rappel() { perform(.rappelling) }
    @objc private func cheer() { perform(.happy) }
    @objc private func resetFromMenu() { resetPosition() }
}

extension VirusArenaProjection {
    init(fitting area: CGRect, pet: CGRect, hero: CGPoint) {
        let world = VirusArcade.size
        let unit = min(pet.width / 56, area.width / world.width, area.height / world.height)
        let size = CGSize(width: world.width * unit, height: world.height * unit)
        let mirror = pet.midX > area.midX
        let heroX = mirror ? world.width - hero.x : hero.x
        let x = min(max(area.minX, pet.midX - heroX * unit), area.maxX - size.width)
        let y = min(max(area.minY, pet.midY - hero.y * unit), area.maxY - size.height)
        self.init(rect: CGRect(origin: CGPoint(x: x, y: y), size: size), mirrored: mirror)
    }
}

private final class PetPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        animationBehavior = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PetInputView: NSView {
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: (() -> Void)?
    var hasPress: Bool { down != nil }
    private var down: CGPoint?
    private var origin = CGPoint.zero
    private var dragged = false

    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onMenu?(event); return }
        down = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - down.x, dy = mouse.y - down.y
        guard dragged || hypot(dx, dy) > 3 else { return }
        dragged = true
        onDrag?(CGPoint(x: origin.x + dx, y: origin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        if dragged { onRelease?() } else { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

private final class CordView: NSView {
    var handX: CGFloat = 5
    var pegX: CGFloat = 5
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.24, green: 0.17, blue: 0.14, alpha: 0.95).setFill()
        NSRect(x: handX - 1.5, y: 0, width: 3, height: bounds.height).fill()
        NSRect(x: min(handX, pegX) - 1.5, y: bounds.maxY - 3, width: abs(handX-pegX) + 3, height: 3).fill()
        NSColor(srgbRed: 0.99, green: 0.79, blue: 0.56, alpha: 1).setFill()
        NSRect(x: handX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: min(handX, pegX), y: bounds.maxY - 2, width: abs(handX-pegX), height: 1).fill()
        NSColor(srgbRed: 0.39, green: 0.27, blue: 0.21, alpha: 1).setFill()
        NSRect(x: pegX - 3, y: bounds.maxY - 4, width: 6, height: 4).fill()
    }
}

private struct HoverReadout: View, Equatable {
    var status = L("Startklar")
    var session = L("Kein aktueller Messwert")
    var week = L("Kein aktueller Messwert")
    var source = "Claude.ai"
    private(set) var language = L10n.locale.identifier

    private let cream = Color(red: 0.97, green: 0.934, blue: 0.878)
    private let muted = Color(red: 0.77, green: 0.72, blue: 0.69)
    private let accent = Color(red: 1, green: 0.663, blue: 0.515)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(status).font(Font(PixelDialogue.font)).foregroundStyle(cream)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(source).font(Font(PixelDialogue.font.withSize(13))).foregroundStyle(accent)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(muted.opacity(0.35)).frame(height: 2)
            line(L("Sitzung"), session)
            line(L("Woche"), week)
        }
        .padding(14)
        .frame(width: 318, alignment: .leading)
        .background(Canvas { context, size in
            context.withCGContext { cg in
                PixelDialogue.drawShell(in: cg, body: CGRect(origin: .zero, size: size))
            }
        })
        .fixedSize()
        .environment(\.locale, L10n.locale)
        .environment(\.layoutDirection, L10n.isRTL ? .rightToLeft : .leftToRight)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(muted).frame(width: 60, alignment: .leading)
            Text(value).foregroundStyle(cream).lineLimit(4).fixedSize(horizontal: false, vertical: true)
        }.font(Font(PixelDialogue.font.withSize(13)))
    }
}
