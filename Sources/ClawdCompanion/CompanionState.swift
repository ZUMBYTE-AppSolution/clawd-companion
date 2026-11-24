import AppKit
import SwiftUI

enum PanelPage: String, CaseIterable {
    case companion = "Begleiter", connections = "Verbindungen", overlay = "Overlay", highscores = "Highscores", info = "Info & Updates"
}

enum QuotaSource: String, CaseIterable {
    case browser = "Claude.ai"
    case code = "Claude Code"
}

struct LimitWindow: Codable, Equatable {
    var remaining: Double
    var reset: Date?
    var resetLabel: String?
    var resetApproximate: Bool?
    var resetPrefix: String {
        let relative = resetLabel?.range(of: #"\b(in|nach)\s+\d"#, options: [.regularExpression, .caseInsensitive]) != nil
        return (resetApproximate ?? relative) ? "Reset ca." : "Reset"
    }
}

struct LimitReport: Codable, Equatable {
    var seen: Date
    var session: LimitWindow?
    var week: LimitWindow?

    func current(weekly: Bool, at now: Date) -> LimitWindow? {
        guard seen <= now.addingTimeInterval(60),
              let window = weekly ? week : session else { return nil }
        if let reset = window.reset { return reset > now ? window : nil }
        return now.timeIntervalSince(seen) < 900 ? window : nil
    }
}

struct ActivitySignal {
    let pose: MascotPose
    let label: String
    let source: String
    let seen: Date
    let lifetime: TimeInterval
    let busy: Bool
}

struct PlayScore: Equatable {
    var hits = 0
    var dodges = 0

    init(saved: [String: Int] = [:]) {
        hits = max(0, saved["hits"] ?? 0)
        dodges = max(0, saved["dodges"] ?? 0)
    }

    mutating func add(hit: Bool) {
        if hit {
            if hits < Int.max { hits += 1 }
        } else if dodges < Int.max { dodges += 1 }
    }
}

@MainActor
final class CompanionState: ObservableObject {
    @Published var page: PanelPage = .companion
    @Published var safariSetup = false
    @Published private(set) var now = Date()
    @Published private(set) var pose: MascotPose = .idle
    @Published private(set) var desktopPose: MascotPose = .idle
    @Published private(set) var pinned = false
    @Published private(set) var activeAgentCount = 0
    @Published private(set) var isAwaitingApproval = false
    @Published private(set) var previewingApproval = false
    @Published private(set) var playScore: PlayScore
    @Published private(set) var arcadeStatus: ArcadeStatus = .ready
    @Published private(set) var arenaTotals: ArenaTotals
    let arenaAccount = ArenaAccountModel()
    @Published private(set) var hooksNeedUpgrade = false
    @Published private(set) var activityLabel = "Startklar"
    @Published private(set) var activitySource = "Claw’d"
    @Published private(set) var webReport: LimitReport?
    @Published private(set) var codeReport: LimitReport?
    @Published private(set) var browserSeen: Date?
    @Published private(set) var browserRunning = false
    @Published private(set) var bridgeIssue: String?
    @Published private(set) var hooksInstalled = false
    @Published private(set) var quotaInstalled = false
    @Published private(set) var accessibility = false
    @Published var feedback: String?
    @Published var language: String {
        didSet {
            save(language, "language")
            L10n.select(language)
            updateReadout()
            syncMenu()
        }
    }
    @Published var voiceEnabled: Bool { didSet { save(voiceEnabled, "voiceEnabled"); voice.enabled = voiceEnabled } }
    private let voice = ClawdVoice()
    @Published var soundEnabled: Bool { didSet { save(soundEnabled, "soundEnabled"); audio.enabled = soundEnabled } }
    @Published var soundVolume: Double { didSet { save(soundVolume, "soundVolume"); audio.volume = soundVolume } }
    @Published private var mutedSounds: Set<PetSound> {
        didSet {
            save(mutedSounds.map(\.rawValue).sorted(), "mutedSounds")
            audio.muted = mutedSounds
        }
    }
    @Published var speechEnabled: Bool {
        didSet {
            save(speechEnabled, "speechEnabled")
            if !speechEnabled { overlay?.clearSpeech() }
        }
    }
    @Published var roam: Bool { didSet { save(roam, "roam"); configurePlay() } }
    @Published var chase: Bool { didSet { save(chase, "chase"); configurePlay() } }
    @Published var bow: Bool { didSet { save(bow, "bow"); configurePlay() } }
    @Published var arcadeEnabled: Bool { didSet { save(arcadeEnabled, "arcadeEnabled"); configureArcade() } }
    @Published var arcadeWhileActive: Bool { didSet { save(arcadeWhileActive, "arcadeWhileActive"); configureArcade() } }
    @Published var showOverlay: Bool { didSet { save(showOverlay, "showOverlay"); configureOverlay() } }
    @Published var follow: Bool { didSet { save(follow, "follow"); configureOverlay() } }
    @Published var quiet: Bool { didSet { save(quiet, "quiet"); configureOverlay() } }
    @Published var scale: Double { didSet { save(scale, "scale"); configureOverlay() } }
    @Published var webEnabled: Bool { didSet { save(webEnabled, "webEnabled"); updateBridge() } }
    @Published var quotaSource: QuotaSource { didSet { save(quotaSource.rawValue, "quotaSource") } }

    let updates: ReleaseUpdateCenter
    private let defaults: UserDefaults
    private let uptime: () -> TimeInterval
    private let audio = CompanionAudio()
    private let sessionStatus = ClaudeSessionStatus()
    private lazy var bridge = BrowserBridge()
    private lazy var quota = QuotaStatusLine()
    private var overlay: OverlayController?
    private var menuMascot: MenuMascot?
    private var pollTimer: Timer?
    private var tick = 0
    private var webSignal: ActivitySignal?
    private var codeSignal: ActivitySignal?
    private var playSignal: ActivitySignal?
    private var noticeSignal: ActivitySignal?
    private var codeApprovals = 0
    private var browserApprovalExpires: [String: TimeInterval] = [:]
    private var previewApprovalUntil: TimeInterval?
    private var lastAction = Date()
    private var lastAppliedPose: MascotPose?

    init(defaults: UserDefaults = .standard, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        arenaTotals = defaults.data(forKey: "arena.totals.v1").flatMap { try? JSONDecoder().decode(ArenaTotals.self, from: $0) } ?? ArenaTotals()
        self.updates = ReleaseUpdateCenter(defaults: defaults)
        self.uptime = uptime
        let existing = defaults.object(forKey: "ClawdBrowserPairingTokenV1") != nil || defaults.object(forKey: "playScore") != nil
        language = defaults.string(forKey: "language") ?? (existing ? "de" : "system")
        voiceEnabled = defaults.bool(forKey: "voiceEnabled")
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        let storedVolume = defaults.object(forKey: "soundVolume") as? Double ?? 0.28
        soundVolume = storedVolume.isFinite ? min(1, max(0, storedVolume)) : 0.28
        mutedSounds = Set((defaults.stringArray(forKey: "mutedSounds") ?? []).compactMap(PetSound.init(rawValue:)))
        playScore = PlayScore(saved: defaults.dictionary(forKey: "playScore") as? [String: Int] ?? [:])
        roam = defaults.object(forKey: "roam") as? Bool ?? true
        chase = defaults.object(forKey: "chase") as? Bool ?? true
        bow = defaults.object(forKey: "bow") as? Bool ?? true
        arcadeEnabled = defaults.object(forKey: "arcadeEnabled") as? Bool ?? true
        arcadeWhileActive = defaults.bool(forKey: "arcadeWhileActive")
        speechEnabled = defaults.object(forKey: "speechEnabled") as? Bool ?? true
        showOverlay = defaults.object(forKey: "showOverlay") as? Bool ?? true
        follow = defaults.object(forKey: "follow") as? Bool ?? true
        quiet = defaults.bool(forKey: "quiet")
        let storedScale = defaults.double(forKey: "scale")
        scale = storedScale == 0 ? 1 : min(1.65, max(0.7, storedScale))
        webEnabled = defaults.bool(forKey: "webEnabled")
        quotaSource = QuotaSource(rawValue: defaults.string(forKey: "quotaSource") ?? "") ?? .browser
        if let until = defaults.object(forKey: "arcadeGraveUntil") as? Date {
            arcadeStatus = .grave(until: until)
        } else {
            arcadeStatus = arcadeEnabled ? .ready : .disabled
        }
        if let url = URL(string: "https://claude.ai"),
           let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: url) {
            safariSetup = Bundle(url: defaultBrowser)?.bundleIdentifier == "com.apple.Safari"
        }
        if let data = defaults.data(forKey: "webReport") {
            webReport = try? JSONDecoder().decode(LimitReport.self, from: data)
        }
        audio.enabled = soundEnabled
        audio.volume = soundVolume
        audio.muted = mutedSounds
        voice.enabled = voiceEnabled
        if defaults.string(forKey: "language") == nil { defaults.set(language, forKey: "language") }
        L10n.select(language)
    }

    func isSoundEnabled(_ sound: PetSound) -> Bool { !mutedSounds.contains(sound) }

    func setSound(_ sound: PetSound, enabled: Bool) {
        if enabled { mutedSounds.remove(sound) } else { mutedSounds.insert(sound) }
    }

    func previewSound(_ sound: PetSound) { audio.play(sound, preview: true) }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    func start(overlay: OverlayController, menuMascot: MenuMascot? = nil) {
        self.overlay = overlay
        self.menuMascot = menuMascot
        arenaAccount.onRankedDeath = { [weak self] id in self?.recordRankedDeath(id: id) }
        updates.onAvailable = { [weak self] version in
            guard let self, self.showOverlay, self.speechEnabled else { return }
            self.overlay?.speak(title: "Claw’d Companion", message: L("Version {0} ist verfügbar.", version), kind: "info")
        }
        updates.start()
        overlay.onSound = { [weak self] sound in self?.audio.play(sound) }
        overlay.onArcadeRoundFinished = { [weak self] id, stats in self?.recordArenaRound(id: id, stats: stats) }
        overlay.onArcadeMusic = { [weak self] phase in self?.audio.setArcadeMusic(phase) }
        overlay.onArcadeGraveChanged = { [weak self] deadline in
            if let deadline { self?.save(deadline, "arcadeGraveUntil") }
            else { self?.defaults.removeObject(forKey: "arcadeGraveUntil") }
        }
        overlay.onArcadeStatus = { [weak self] status in
            guard let self, status != arcadeStatus else { return }
            arcadeStatus = status
            syncMenu()
        }
        overlay.restoreArcadeGrave(until: defaults.object(forKey: "arcadeGraveUntil") as? Date)
        configureArcade()
        overlay.onDisplayPose = { [weak self] value in
            guard let self else { return }
            desktopPose = value
            syncMenu()
        }
        overlay.onPlayRound = { [weak self] hit in self?.recordRound(hit: hit) }
        overlay.hitCountForHUD = { [weak self] in self?.playScore.hits ?? 0 }
        overlay.onPinChanged = { [weak self] pinned in self?.pinned = pinned }
        configurePlay()
        configureOverlay()
        updateBridge()
        refreshIntegrations()
        poll()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        updates.stop()
        voice.stop()
        audio.setArcadeMusic(nil)
        pollTimer?.invalidate()
        sessionStatus.stop()
        menuMascot?.stop()
        if webEnabled { bridge.stop() }
        overlay?.configure(visible: false, followsWindows: false, reducedMotion: true)
    }

    func refreshIntegrations() {
        hooksInstalled = ClaudeHooks.isInstalled
        hooksNeedUpgrade = hooksInstalled && ClaudeHooks.needsUpgrade
        quotaInstalled = quota.isInstalled
        accessibility = OverlayController.hasAccessibilityPermission
    }

    private func poll() {
        now = Date()
        tick += 1
        if tick % 5 == 0 { refreshIntegrations() }
        let codeInfo = hooksInstalled ? ClaudeHooks.poll() : nil
        codeApprovals = codeInfo?.approvalCount ?? 0
        sessionStatus.update(pending: codeInfo?.pendingApprovals ?? [:]) { resolved in
            ClaudeHooks.resolveApprovals(through: resolved)
        }
        let count = codeInfo?.agentCount ?? 0
        if activeAgentCount != count {
            activeAgentCount = count
            overlay?.setAgentCount(count)
        }
        if let info = codeInfo {
            codeSignal = ActivitySignal(pose: info.pose, label: info.label, source: "Claude Code",
                                        seen: info.date, lifetime: info.lifetime, busy: info.busy)
        } else { codeSignal = nil }
        if quotaInstalled && (tick == 1 || tick.isMultiple(of: 3)) {
            let report = quota.latest().map { data in
                func convert(_ window: CodeQuotaWindow?) -> LimitWindow? {
                    window.map { LimitWindow(remaining: $0.remainingPercent, reset: $0.resetsAt) }
                }
                return LimitReport(seen: data.observedAt, session: convert(data.fiveHour), week: convert(data.sevenDay))
            }
            if report != codeReport { codeReport = report }
        }
        resolveActivity()
    }

    private func updateBridge() {
        if !webEnabled { browserApprovalExpires.removeAll() }
        guard overlay != nil else {
            if !webEnabled { webSignal = nil; noticeSignal = nil; resolveActivity() }
            return
        }
        if webEnabled {
            bridge.start(onEvent: { [weak self] event in
                MainActor.assumeIsolated { self?.receive(event) }
            }, onStatus: { [weak self] issue in
                MainActor.assumeIsolated {
                    guard self?.webEnabled == true else { return }
                    self?.browserRunning = issue == nil
                    self?.bridgeIssue = issue
                }
            })
        } else {
            bridge.stop()
            browserSeen = nil
            webSignal = nil
            noticeSignal = nil
            overlay?.clearSpeech()
            browserRunning = false
            bridgeIssue = nil
            resolveActivity()
        }
    }

    func receive(_ event: BrowserBridge.Event) {
        guard webEnabled else { return }
        let seen = Date()
        browserSeen = seen
        switch event {
        case let .approval(sourceID, waiting):
            browserApprovalExpires[sourceID] = waiting ? uptime() + 150 : nil
        case let .activity(state):
            var next: (MascotPose, String, TimeInterval, Bool)?
            switch state {
            case "working": next = (.typing, "Schreibt eine Antwort", 100, true)
            case "thinking": next = (.thinking, "Denkt nach", 100, true)
            case "searching": next = (.researching, "Recherchiert", 100, true)
            case "planning": next = (.planning, "Plant die nächsten Schritte", 100, true)
            case "reading": next = (.reading, "Liest eine Datei", 100, true)
            case "executing": next = (.executing, "Führt Code aus", 100, true)
            case "drawing": next = (.drawing, "Erstellt ein Artefakt", 100, true)
            case "done": next = (.happy, "Antwort fertig", 9, false)
            case "idle": webSignal = nil
            default: break
            }
            if state == "done", speechEnabled, showOverlay, seen.timeIntervalSince(noticeSignal?.seen ?? .distantPast) > 5 {
                if webSignal?.pose != .happy { speakOwn(title: "Claude.ai", message: "Deine Antwort ist fertig.", kind: "success") }
            }
            if let next {
                webSignal = ActivitySignal(pose: next.0, label: next.1, source: "Claude.ai",
                                           seen: seen, lifetime: next.2, busy: next.3)
                lastAction = seen
            }
        case let .notice(title, message, kind):
            if speechEnabled, showOverlay {
                overlay?.speak(title: title, message: message, kind: kind)
            }
            if ["warning", "error", "attention"].contains(kind) {
                noticeSignal = ActivitySignal(pose: .worried, label: "Hat einen Hinweis", source: "Claude.ai",
                                              seen: seen, lifetime: 7, busy: false)
            }
        case let .usage(observed, windows):
            func limit(_ kind: String) -> LimitWindow? {
                windows.first(where: { $0.kind == kind }).map {
                    LimitWindow(remaining: Double($0.remainingPercent), reset: $0.resetAt,
                                resetLabel: $0.resetLabel, resetApproximate: $0.resetApproximate)
                }
            }
            if observed >= (webReport?.seen ?? .distantPast) {
                webReport = LimitReport(seen: observed, session: limit("session"), week: limit("weekly"))
                if let data = try? JSONEncoder().encode(webReport) { defaults.set(data, forKey: "webReport") }
            }
        }
        resolveActivity()
    }

    var webConnected: Bool {
        webEnabled && browserSeen.map { now.timeIntervalSince($0) < 100 } == true
    }
    var selectedReport: LimitReport? { quotaSource == .browser ? webReport : codeReport }

    private func resolveActivity() {
        let date = Date()
        let time = uptime()
        browserApprovalExpires = browserApprovalExpires.filter { $0.value > time }
        let browserWaiting = !browserApprovalExpires.isEmpty
        let codeWaiting = codeApprovals > 0
        let realWaiting = browserWaiting || codeWaiting
        if realWaiting || (previewApprovalUntil ?? 0) <= time { previewApprovalUntil = nil }
        let testing = previewApprovalUntil != nil
        if previewingApproval != testing { previewingApproval = testing }
        let waiting = realWaiting || testing
        let signals = [webSignal, codeSignal].compactMap { $0 }.filter { date.timeIntervalSince($0.seen) < $0.lifetime }
        let newestBusy = signals.filter(\.busy).max { $0.seen < $1.seen }
        let preview = playSignal.flatMap { date.timeIntervalSince($0.seen) < $0.lifetime ? $0 : nil }
        let notice = noticeSignal.flatMap { date.timeIntervalSince($0.seen) < $0.lifetime ? $0 : nil }
        let juggling = signals.first { $0.pose == .juggling && activeAgentCount > 0 }
        let active = preview ?? notice ?? juggling ?? newestBusy ?? signals.max { $0.seen < $1.seen }
        if let active { lastAction = max(lastAction, active.seen) }
        let sleeping = date.timeIntervalSince(lastAction) > 180
        let underlying = active?.pose ?? (sleeping ? .sleeping : .idle)
        let next: MascotPose = waiting ? .awaitingApproval : underlying
        let label = waiting ? (testing ? "Zeigt das OK?-Schild zur Probe" : "Wartet auf deine Freigabe")
                            : active?.label ?? (sleeping ? "Hält ein Nickerchen" : "Startklar")
        let source: String
        if browserWaiting && codeWaiting { source = "Claude.ai und Claude Code" }
        else if browserWaiting { source = "Claude.ai" }
        else if codeWaiting { source = "Claude Code" }
        else if testing { source = "Vorschau" }
        else { source = active?.source ?? "Claw’d" }
        let changed = waiting != isAwaitingApproval
        if changed {
            isAwaitingApproval = waiting
            lastAction = date
            if waiting { overlay?.setApprovalWaiting(true) }
            if realWaiting { voice.speak(L("Wartet auf deine Freigabe"), language: L10n.code) }
        }
        if pose != next { pose = next }
        if activityLabel != label { activityLabel = label }
        if activitySource != source { activitySource = source }
        if underlying != lastAppliedPose {
            lastAppliedPose = underlying
            if preview == nil { overlay?.setPose(underlying) }
        }
        if changed && !waiting { overlay?.setApprovalWaiting(false) }
        syncMenu()
        updateReadout()
    }

    var presentedPose: MascotPose {
        if case .grave = arcadeStatus { return .grave }
        if arcadeStatus == .reviving { return .reviving }
        if desktopPose.isApprovalTransition || desktopPose == .awaitingApproval { return desktopPose }
        return showOverlay && overlay != nil ? desktopPose : pose
    }

    var presentedLabel: String {
        if arcadeOwnsMascot { return arcadeStatusLabel }
        if pose == .juggling, activeAgentCount > 1 { return L("Jongliert mit {0} Agenten", activeAgentCount.formatted(.number.locale(L10n.locale))) }
        if presentedPose == .approvalClosing { return "Rollt das OK?-Schild ein" }
        guard activitySource == "Claw’d" else { return activityLabel }
        switch presentedPose {
        case .archery: return "Spannt den Codebogen"
        case .letterBlaster: return "Zielt mit dem Buchstabenblaster"
        case .peek: return "Linst über die Fensterkante"
        case .dancing: return "Feiert deine Ausweichserie"
        case .walking: return "Ist unterwegs"
        case .jumping: return "Springt ab"
        case .falling: return "Ist in der Luft"
        case .landing: return "Landet"
        case .perched: return "Sitzt auf der Titelleiste"
        case .perchThinking: return "Grübelt auf der Titelleiste"
        case .rappelling: return "Seilt sich ab"
        case .climbing: return "Klettert"
        case .happy: return "Freut sich"
        default: return activityLabel
        }
    }

    private func syncMenu() {
        menuMascot?.update(pose: presentedPose, agentCount: activeAgentCount, reducedMotion: quiet)
    }

    func recordRound(hit: Bool) {
        playScore.add(hit: hit)
        save(["hits": playScore.hits, "dodges": playScore.dodges], "playScore")
    }

    func recordArenaRound(id: UUID, stats: VirusArcade.RunStats) {
        var updated = arenaTotals
        guard updated.record(id: id, stats: stats), let data = try? JSONEncoder().encode(updated) else { return }
        save(data, "arena.totals.v1")
        arenaTotals = updated
    }

    func recordRankedDeath(id: String) {
        guard !id.isEmpty, defaults.string(forKey: "lastRankedGraveID") != id else { return }
        save(id, "lastRankedGraveID")
        if case .grave = arcadeStatus { return }
        let until = Date().addingTimeInterval(ArcadeCoordinator.graveDuration)
        save(until, "arcadeGraveUntil")
        arcadeStatus = .grave(until: until)
        overlay?.restoreArcadeGrave(until: until)
    }

    var lessMotion: Bool { quiet || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var arcadeOwnsMascot: Bool {
        switch arcadeStatus {
        case .wave, .boss, .grave, .reviving, .victory: return true
        default: return false
        }
    }

    var arcadeStatusLabel: String {
        func number(_ value: Int) -> String { value.formatted(.number.locale(L10n.locale)) }
        switch arcadeStatus {
        case .disabled: return L("Ausgeschaltet")
        case .ready: return L("Bereit für eine Runde")
        case .waitingForIdle: return L("Wartet auf den Leerlauf")
        case .waitingForCompanion: return L("Vorgemerkt, bis Claw’d frei ist")
        case .paused(let hp): return L("Runde pausiert · {0} LP", number(hp))
        case let .wave(wave, hp): return L("Welle {0} · {1} LP", number(wave), number(hp))
        case .boss(let hp): return L("Endboss · {0} LP", number(hp))
        case .grave(let until):
            let seconds = Int(ceil(min(ArcadeCoordinator.graveDuration, max(0, until.timeIntervalSince(now)))))
            let remainder = (seconds % 60).formatted(.number.precision(.integerLength(2)).locale(L10n.locale))
            return L("Auferstehung in {0}", number(seconds / 60) + ":" + remainder)
        case .reviving: return L("Claw’d steht wieder auf")
        case .victory: return L("Boss besiegt")
        }
    }

    var canRequestArcade: Bool {
        arcadeEnabled && arcadeStatus == .ready && showOverlay && !lessMotion && !isAwaitingApproval
    }

    func requestArcade() {
        guard canRequestArcade else { return }
        _ = overlay?.requestArcade()
    }

    private func configureArcade() {
        overlay?.configureArcade(enabled: arcadeEnabled, allowWhileActive: arcadeWhileActive)
    }

    var bowUnavailableReason: String? {
        if arcadeOwnsMascot { return "Die Virenarena hat gerade Vorrang." }
        if isAwaitingApproval { return "Claw’d hält gerade das OK?-Schild." }
        if lessMotion { return "„Bewegung reduzieren“ ist aktiv." }
        if !bow { return "Codebogen und Buchstabenblaster sind unter Overlay ausgeschaltet." }
        if activeAgentCount > 0 { return "Claw’d jongliert gerade mit Subagents." }
        return nil
    }
    func startBow(letters: Bool = false) {
        guard bowUnavailableReason == nil else { return }
        if !showOverlay { showOverlay = true }
        let started = letters ? overlay?.requestLetterBlaster() : overlay?.requestBow()
        if started == false {
            feedback = "Claw’d hat gerade alle Scheren voll. Probiere es nach der laufenden Aktion oder bei sichtbarem Fenster erneut."
        }
    }

    func releasePin() { overlay?.releasePin() }

    private func configurePlay() { overlay?.configurePlay(roaming: roam, chase: chase, bow: bow) }

    private func updateReadout() {
        let report = selectedReport
        let locale = L10n.locale
        func line(weekly: Bool) -> String {
            guard let value = report?.current(weekly: weekly, at: now) else { return L("Kein aktueller Messwert") }
            let percent = L("{0} % frei", value.remaining.formatted(.number.precision(.fractionLength(0...1)).locale(locale)))
            if let reset = value.reset {
                return percent + " · " + L(value.resetPrefix) + " " + reset.formatted(.dateTime.day().month().hour().minute().locale(locale))
            }
            if let label = value.resetLabel { return percent + " · " + label }
            return percent + " · " + L("Reset unbekannt")
        }
        let source = quotaSource.rawValue + (report.map { " · " + L("Stand {0}", $0.seen.formatted(.dateTime.day().month().hour().minute().locale(locale))) } ?? "")
        overlay?.setReadout(status: L(presentedLabel), session: line(weekly: false), week: line(weekly: true), source: source)
    }

    func testSpeech() {
        if !showOverlay { showOverlay = true }
        speakOwn(title: L("Claw’d · Vorschau"), message: "Hier melde ich mich, wenn Claude deine Antwort fertig hat.", kind: "info")
    }

    private func speakOwn(title: String, message: String, kind: String) {
        let line = L(message)
        overlay?.speak(title: title, message: line, kind: kind)
        voice.speak(line, language: L10n.code)
    }

    func previewVoice() { voice.speak(L("Hallo! Ich bin Claw’d."), language: L10n.code) }

    func toggleApprovalPreview() {
        guard !arcadeOwnsMascot, previewingApproval || !isAwaitingApproval else { return }
        if !showOverlay { showOverlay = true }
        previewApprovalUntil = previewingApproval ? nil : uptime() + 8
        resolveActivity()
    }

    func play(_ action: MascotPose) {
        guard !isAwaitingApproval, !arcadeOwnsMascot else { return }
        let label: String
        switch action {
        case .climbing: label = "Klettert"
        case .rappelling: label = "Seilt sich ab"
        case .typing: label = "Schreibt eine Antwort"
        case .planning: label = "Plant die nächsten Schritte"
        case .researching: label = "Recherchiert"
        case .reading: label = "Liest eine Datei"
        case .executing: label = "Führt Code aus"
        case .drawing: label = "Erstellt ein Artefakt"
        default: label = "Freut sich"
        }
        if !showOverlay { showOverlay = true }
        playSignal = ActivitySignal(pose: action, label: label, source: "Zum Ausprobieren",
                                    seen: Date(), lifetime: 6, busy: false)
        overlay?.perform(action)
        resolveActivity()
    }

    private func configureOverlay() {
        overlay?.configure(visible: showOverlay, followsWindows: follow, reducedMotion: quiet, scale: scale)
        syncMenu()
    }
    func resetPosition() { overlay?.resetPosition() }
    func askAccessibility() {
        OverlayController.requestAccessibilityPermission()
        refreshIntegrations()
    }

    func upgradeHooks() {
        do {
            try ClaudeHooks.install()
            feedback = "Aktivität, Freigaben und Subagents sind eingerichtet. Starte eine neue Claude-Code-Sitzung."
        } catch { feedback = error.localizedDescription }
        refreshIntegrations()
    }

    func toggleIntegration(hooks: Bool) {
        do {
            if hooks {
                if ClaudeHooks.isInstalled { try ClaudeHooks.uninstall() } else { try ClaudeHooks.install() }
            } else {
                if quota.isInstalled { try quota.uninstall(); codeReport = nil }
                else { try quota.install(); quotaSource = .code }
            }
            feedback = "Änderung gespeichert. Öffne eine neue Claude-Code-Sitzung, damit sie wirksam wird."
        } catch { feedback = error.localizedDescription }
        refreshIntegrations()
    }

    func copyPairingToken() {
        guard webEnabled else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bridge.token, forType: .string)
        feedback = "Kopplungscode kopiert. Füge ihn im Browser in die Claw’d-Erweiterung ein."
    }

    func revealExtension() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else {
            feedback = "Der Erweiterungsordner liegt im Quellprojekt unter BrowserExtension. In der gebauten App ist er mitgeliefert."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        NSWorkspace.shared.open(url)
        feedback = "Ordnerpfad kopiert. Drücke bei „Entpackte Erweiterung laden“ ⌘⇧G und füge den Pfad ein."
    }

    func openUsage(in bundleID: String? = nil) {
        guard let url = URL(string: "https://claude.ai/settings/usage") else { return }
        if let bundleID, let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        } else { NSWorkspace.shared.open(url) }
    }
}
