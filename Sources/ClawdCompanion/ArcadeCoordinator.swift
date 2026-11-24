import Foundation

enum ArcadeStatus: Equatable {
    case disabled, ready, waitingForIdle, waitingForCompanion
    case paused(hp: Int), wave(Int, hp: Int), boss(hp: Int)
    case grave(until: Date), reviving, victory
}

/// Uses wall time only for the gravestone. Combat advances on the monotonic
/// clock, and a suspended fight gets a new time origin when play resumes.
final class ArcadeCoordinator {
    static let idleThreshold: TimeInterval = 90
    static let graveDuration: TimeInterval = 5 * 60

    var onStatus: ((ArcadeStatus) -> Void)?
    var onGraveChanged: ((Date?) -> Void)?
    var onRoundFinished: ((UUID, VirusArcade.RunStats) -> Void)?
    private var roundID = UUID()
    private(set) var status = ArcadeStatus.disabled {
        didSet { if status != oldValue { onStatus?(status) } }
    }
    private(set) var enabled = false
    private(set) var allowWhileActive = false
    private(set) var running = false
    private(set) var revivalStart: TimeInterval?
    private(set) var graveUntil: Date?
    private(set) var requested = false
    private var victoryStart: TimeInterval?
    private var game: VirusArcade?
    private var firstBout = true
    private var nextAutomaticStart: TimeInterval?
    private let delay: () -> TimeInterval
    private let makeGame: () -> VirusArcade

    init(delay: @escaping () -> TimeInterval = { .random(in: 60...180) },
         makeGame: @escaping () -> VirusArcade = { VirusArcade() }) {
        self.delay = delay
        self.makeGame = makeGame
    }

    var recovering: Bool { graveUntil != nil || revivalStart != nil }

    func configure(enabled: Bool, allowWhileActive: Bool) {
        let changed = self.enabled != enabled
        self.enabled = enabled
        self.allowWhileActive = allowWhileActive
        guard changed else { return }
        requested = false
        nextAutomaticStart = nil
        if !enabled {
            firstBout = !recovering
            running = false
            game = nil
            victoryStart = nil
        }
        if !recovering { status = enabled ? .ready : .disabled }
    }

    @discardableResult
    func request() -> Bool {
        guard enabled, game == nil, !recovering, victoryStart == nil else { return false }
        requested = true
        return true
    }

    func strike(_ enemy: Int) {
        guard running, allowWhileActive else { return }
        game?.hit(enemyID: enemy)
    }

    func collect(_ pickup: Int) {
        guard running, allowWhileActive else { return }
        game?.collect(pickupID: pickup)
    }

    func pause() {
        if victoryStart != nil {
            victoryStart = nil
            status = .ready
        }
        guard running, let hp = game?.frame.playerHP else { return }
        game?.pause()
        running = false
        status = .paused(hp: hp)
    }

    func restoreGrave(until deadline: Date?) {
        guard let deadline else { return }
        game = nil
        running = false
        requested = false
        nextAutomaticStart = nil
        victoryStart = nil
        firstBout = false
        revivalStart = nil
        graveUntil = deadline
        status = .grave(until: deadline)
    }

    func registerDeath(at date: Date) {
        let until = date.addingTimeInterval(Self.graveDuration)
        restoreGrave(until: until)
        onGraveChanged?(until)
    }

    func tick(now: TimeInterval, date: Date, available: Bool, idleSeconds: TimeInterval) -> VirusArcade.Frame? {
        if let until = graveUntil {
            if date < until { return nil }
            graveUntil = nil
            revivalStart = now
            status = .reviving
            onGraveChanged?(nil)
        }
        if let started = revivalStart {
            guard now - started >= MascotPose.revivalDuration else { return nil }
            revivalStart = nil
            status = enabled ? .ready : .disabled
        }
        guard enabled else { return nil }
        let canPlay = allowWhileActive || (idleSeconds.isFinite && idleSeconds >= Self.idleThreshold)
        if let started = victoryStart {
            if available && canPlay && now - started < 2.4 { return nil }
            victoryStart = nil
            status = .ready
        }
        if available && !canPlay { nextAutomaticStart = nil }
        guard available && canPlay else {
            pause()
            if game == nil {
                if requested { status = !available && allowWhileActive ? .waitingForCompanion : .waitingForIdle }
                else { status = .ready }
            }
            return nil
        }
        if game == nil {
            let due = nextAutomaticStart ?? (firstBout && !allowWhileActive ? now : now + delay())
            nextAutomaticStart = due
            guard requested || now >= due else {
                status = .ready
                return nil
            }
            game = makeGame()
            roundID = UUID()
            firstBout = false
            requested = false
            nextAutomaticStart = nil
        }
        if !running {
            game?.resume(now: now)
            running = true
        }
        guard let frame = game?.tick(now: now) else { return nil }
        switch frame.phase {
        case .dead:
            if frame.stats.engaged { onRoundFinished?(roundID, frame.stats) }
            registerDeath(at: date)
        case .victory:
            if frame.stats.engaged { onRoundFinished?(roundID, frame.stats) }
            game = nil
            running = false
            victoryStart = now
            status = .victory
        case .wave: status = .wave(frame.wave, hp: frame.playerHP)
        case .boss: status = .boss(hp: frame.playerHP)
        }
        return frame
    }
}
