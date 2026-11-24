import Foundation
import SwiftUI

/// A user-started local game. Only this object advances the simulation while it is in the panel.
@MainActor final class ManualArena: ObservableObject {
    @Published private(set) var frame: VirusArcade.Frame?
    @Published private(set) var paused = false
    private var game: VirusArcade?
    private var runID = UUID()
    private var lastTick: TimeInterval = 0
    private let makeGame: () -> VirusArcade
    var onFinish: ((UUID, VirusArcade.RunStats) -> Void)?
    var onOwnershipChange: (() -> Void)?
    var onSound: ((PetSound) -> Void)?
    var onMusic: ((ArcadeMusicPhase?) -> Void)?
    var playing: Bool { game != nil }

    init(makeGame: @escaping () -> VirusArcade = { VirusArcade() }) { self.makeGame = makeGame }

    func start(now: TimeInterval, existing: (UUID, VirusArcade)? = nil) {
        guard !playing else { return }
        let (id, simulation) = existing ?? (UUID(), makeGame())
        guard simulation.frame.phase == .wave || simulation.frame.phase == .boss else { return }
        runID = id
        game = simulation
        paused = false
        game?.resume(now: now)
        lastTick = now
        frame = simulation.frame
        onOwnershipChange?()
        onMusic?(simulation.frame.phase == .boss ? .boss : .wave)
    }

    func pause() {
        guard playing, !paused else { return }
        game?.pause()
        paused = true
        onMusic?(nil)
    }

    func resume(now: TimeInterval) {
        guard playing, paused else { return }
        game?.resume(now: now)
        lastTick = now
        paused = false
        onMusic?(frame?.phase == .boss ? .boss : .wave)
    }

    func end() {
        let owned = playing
        game = nil
        frame = nil
        paused = false
        if owned { onMusic?(nil); onOwnershipChange?() }
    }

    func tick(now: TimeInterval) {
        guard !paused, let updated = game?.tick(now: now) else { return }
        lastTick = now
        let previous = frame?.phase
        frame = updated
        for cue in updated.cues { onSound?(cue.petSound) }
        switch updated.phase {
        case .dead, .victory:
            game = nil
            onMusic?(nil)
            onFinish?(runID, updated.stats)
            onOwnershipChange?()
        case .boss where previous != .boss: onMusic?(.boss)
        default: break
        }
    }

    func tap(_ point: CGPoint) {
        guard playing, !paused else { return }
        game?.hit(at: point)
        // Deliver a finishing tap immediately, even if the panel closes before the next timer tick.
        tick(now: lastTick)
    }
}

extension VirusArcade.Cue {
    var petSound: PetSound {
        switch self {
        case .fire: return .arcadeFire
        case .enemyHit, .enemyDefeated, .heroHurt: return .arcadeHit
        case .powerup: return .arcadePickup
        case .boss: return .arcadeBoss
        case .victory: return .arcadeVictory
        case .death: return .arcadeDefeat
        }
    }
}
