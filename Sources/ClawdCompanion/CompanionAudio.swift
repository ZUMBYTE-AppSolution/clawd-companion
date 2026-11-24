import AppKit

enum PetSound: String, CaseIterable, Identifiable {
    case steps, climb, jump, land, rappel, bow, letters, juggle, celebrate, notification, peek, typing, thinking
    case arcadeMusic, arcadeFire, arcadeHit, arcadePickup, arcadeBoss, arcadeDefeat, arcadeVictory, arcadeRevive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Schritte"
        case .climb: return "Klettern"
        case .jump: return "Absprung"
        case .land: return "Landung"
        case .rappel: return "Abseilen"
        case .bow: return "Codebogen"
        case .letters: return "Buchstabensalve"
        case .juggle: return "Jonglieren"
        case .celebrate: return "Freudentanz"
        case .notification: return "Sprechblase"
        case .peek: return "Hervorlugen"
        case .typing: return "Tippen"
        case .thinking: return "Nachdenken"
        case .arcadeMusic: return "Arcade-Musik"
        case .arcadeFire: return "Arcade-Schüsse"
        case .arcadeHit: return "Arcade-Treffer"
        case .arcadePickup: return "Power-up einsammeln"
        case .arcadeBoss: return "Auftritt des Endbosses"
        case .arcadeDefeat: return "Arcade-Niederlage"
        case .arcadeVictory: return "Arcade-Sieg"
        case .arcadeRevive: return "Auferstehung"
        }
    }

    fileprivate var minimumInterval: TimeInterval {
        switch self {
        case .steps, .climb: return 0.48
        case .jump, .land, .bow: return 0.3
        case .rappel, .juggle: return 0.75
        case .letters: return 0.12
        case .celebrate, .peek, .typing, .thinking: return 1.3
        case .notification: return 0.65
        case .arcadeFire: return 0.20
        case .arcadeHit: return 0.18
        case .arcadePickup: return 0.4
        case .arcadeMusic, .arcadeBoss, .arcadeDefeat, .arcadeVictory, .arcadeRevive: return 1.0
        }
    }

    fileprivate var gain: Float {
        switch self {
        case .arcadeFire: return 0.55
        case .arcadeHit: return 0.72
        case .arcadeMusic: return 0.62
        default: return 1
        }
    }

    fileprivate var priority: Int {
        switch self {
        case .arcadeBoss, .arcadeDefeat, .arcadeVictory, .arcadeRevive: return 2
        case .arcadePickup: return 1
        default: return 0
        }
    }

    private enum Timbre { case knock, chip, bell, zip }

    private struct Note {
        let timbre: Timbre
        let startHz: Double
        let endHz: Double
        let seconds: Double
        let pause: Double

        init(_ timbre: Timbre, _ startHz: Double, _ endHz: Double, _ seconds: Double, pause: Double = 0) {
            self.timbre = timbre
            self.startHz = startHz
            self.endHz = endHz
            self.seconds = seconds
            self.pause = pause
        }
    }

    private var notes: [Note] {
        switch self {
        case .steps:
            return [Note(.knock, 175, 92, 0.052, pause: 0.075), Note(.knock, 145, 80, 0.045)]
        case .climb:
            return [Note(.knock, 285, 175, 0.047, pause: 0.065), Note(.knock, 370, 215, 0.052)]
        case .jump:
            return [Note(.chip, 235, 625, 0.16)]
        case .land:
            return [Note(.knock, 180, 62, 0.12)]
        case .rappel:
            return [Note(.zip, 660, 500, 0.055, pause: 0.014), Note(.zip, 530, 390, 0.06, pause: 0.012),
                    Note(.zip, 400, 240, 0.08)]
        case .bow:
            return [Note(.knock, 230, 365, 0.035), Note(.zip, 890, 290, 0.12)]
        case .letters:
            return [Note(.chip, 820, 500, 0.062)]
        case .juggle:
            return [Note(.bell, 392, 399, 0.063, pause: 0.024), Note(.bell, 494, 504, 0.065, pause: 0.022),
                    Note(.bell, 440, 432, 0.08)]
        case .celebrate:
            return [Note(.chip, 330, 330, 0.065, pause: 0.018), Note(.chip, 415, 415, 0.062, pause: 0.018),
                    Note(.chip, 494, 494, 0.07, pause: 0.015), Note(.bell, 660, 666, 0.16)]
        case .notification:
            return [Note(.bell, 659, 659, 0.10, pause: 0.035), Note(.bell, 523, 523, 0.17)]
        case .peek:
            return [Note(.bell, 300, 350, 0.08, pause: 0.09), Note(.bell, 370, 490, 0.105)]
        case .typing:
            return [Note(.knock, 310, 195, 0.034, pause: 0.041), Note(.knock, 270, 174, 0.037, pause: 0.065),
                    Note(.knock, 335, 200, 0.042)]
        case .thinking:
            return [Note(.bell, 277, 280, 0.125, pause: 0.052), Note(.bell, 349, 351, 0.155)]
        case .arcadeMusic:
            return [Note(.bell, 587, 587, 0.095, pause: 0.028), Note(.chip, 698, 698, 0.093),
                    Note(.bell, 880, 880, 0.17)]
        case .arcadeFire:
            return [Note(.zip, 710, 272, 0.062)]
        case .arcadeHit:
            return [Note(.knock, 370, 108, 0.066), Note(.chip, 158, 120, 0.055)]
        case .arcadePickup:
            return [Note(.bell, 554, 554, 0.064), Note(.bell, 831, 831, 0.07), Note(.bell, 1109, 1112, 0.14)]
        case .arcadeBoss:
            return [Note(.knock, 178, 58, 0.09, pause: 0.034), Note(.chip, 123, 123, 0.09),
                    Note(.zip, 175, 132, 0.21)]
        case .arcadeDefeat:
            return [Note(.chip, 349, 330, 0.075, pause: 0.03), Note(.chip, 277, 262, 0.088),
                    Note(.bell, 196, 131, 0.23)]
        case .arcadeVictory:
            return [Note(.chip, 392, 392, 0.07, pause: 0.015), Note(.chip, 524, 524, 0.07),
                    Note(.bell, 659, 659, 0.076), Note(.bell, 784, 790, 0.18)]
        case .arcadeRevive:
            return [Note(.bell, 262, 392, 0.12, pause: 0.02), Note(.bell, 523, 523, 0.08),
                    Note(.bell, 659, 659, 0.08), Note(.bell, 1047, 1047, 0.16)]
        }
    }

    /// Mono 16-bit PCM. Frequencies glide continuously within each note.
    func waveData() -> Data {
        let rate = CompanionPCM.rate
        var samples: [Int16] = []
        for note in notes {
            let count = Int((note.seconds * Double(rate)).rounded())
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / Double(rate)
                let progress = Double(i) / Double(count - 1)
                let tone: Double
                switch note.timbre {
                case .knock: tone = (0.75 * sin(phase) + 0.25 * sin(2.71 * phase)) * exp(-4.6 * progress)
                case .chip: tone = (0.76 * sin(phase) + 0.17 * sin(3 * phase) + 0.07 * sin(5 * phase)) * exp(-0.9 * progress)
                case .bell: tone = (0.78 * sin(phase) + 0.22 * sin(3.98 * phase)) * exp(-2.8 * progress)
                case .zip: tone = (0.74 * sin(phase) + 0.26 * sin(2 * phase)) * (0.76 + 0.24 * cos(2 * .pi * 53 * t))
                }
                // Ramp both ends to zero and leave headroom for three simultaneous cues.
                let envelope = min(1, t / 0.005, Double(count - 1 - i) / (Double(rate) * 0.018))
                samples.append(Int16((tone * envelope * 10_400).rounded()).littleEndian)
                let hz = note.startHz + (note.endHz - note.startHz) * progress
                phase += 2 * .pi * hz / Double(rate)
            }
            samples.append(contentsOf: repeatElement(0, count: Int(note.pause * Double(rate))))
        }
        return CompanionPCM.wave(samples)
    }
}

enum CompanionPCM {
    static let rate = 22_050

    static func wave(_ samples: [Int16]) -> Data {
        let payloadSize = UInt32(samples.count * 2)
        var wav = Data(capacity: 44 + Int(payloadSize))
        func tag(_ name: String) { wav.append(contentsOf: name.utf8) }
        func integer<T: FixedWidthInteger>(_ number: T) {
            withUnsafeBytes(of: number.littleEndian) { wav.append(contentsOf: $0) }
        }
        tag("RIFF")
        integer(36 + payloadSize)
        tag("WAVE")
        tag("fmt ")
        integer(UInt32(16))
        integer(UInt16(1))
        integer(UInt16(1))
        integer(UInt32(rate))
        integer(UInt32(rate * 2))
        integer(UInt16(2))
        integer(UInt16(16))
        tag("data")
        integer(payloadSize)
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }
        return wav
    }
}

@MainActor protocol CompanionSoundVoice: AnyObject {
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var loops: Bool { get set }
    @discardableResult func play() -> Bool
    @discardableResult func stop() -> Bool
}

extension NSSound: CompanionSoundVoice {}

@MainActor final class CompanionAudio {
    private struct Playing {
        let kind: PetSound
        let voice: CompanionSoundVoice
        let preview: Bool
    }

    var enabled = true {
        didSet {
            if !enabled {
                stop { _ in true }
                lastPlayed.removeAll()
                lastPreview = -.infinity
            }
            updateMusic()
        }
    }
    var muted: Set<PetSound> = [] {
        didSet {
            let newlyMuted = muted.subtracting(oldValue)
            stop { newlyMuted.contains($0.kind) }
            updateMusic()
        }
    }
    var volume = 0.28 {
        didSet {
            volume = volume.isFinite ? min(1, max(0, volume)) : 0.28
            if volume == 0 {
                stop { _ in true }
            } else {
                for cue in playing { cue.voice.volume = Float(volume) * cue.kind.gain }
            }
            updateMusic()
        }
    }

    private var waves: [PetSound: Data] = [:]
    private var playing: [Playing] = []
    private var lastPlayed: [PetSound: TimeInterval] = [:]
    private var lastPreview: TimeInterval = -.infinity
    private let clock: () -> TimeInterval
    private let makeVoice: (Data) -> CompanionSoundVoice?
    private let loadMusic: (ArcadeMusicPhase, @escaping @MainActor (Data) -> Void) -> Void
    private var requestedMusic: ArcadeMusicPhase?
    private var playingMusic: (phase: ArcadeMusicPhase, voice: CompanionSoundVoice)?
    private var musicWaves: [ArcadeMusicPhase: Data] = [:]
    private var loadingMusic: Set<ArcadeMusicPhase> = []

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeVoice: @escaping (Data) -> CompanionSoundVoice? = { NSSound(data: $0) },
         loadMusic: @escaping (ArcadeMusicPhase, @escaping @MainActor (Data) -> Void) -> Void = { phase, ready in
             Task { @MainActor in
                 let data = await Task.detached(priority: .utility) { phase.waveData() }.value
                 ready(data)
             }
         }) {
        self.clock = clock
        self.makeVoice = makeVoice
        self.loadMusic = loadMusic
    }

    func setArcadeMusic(_ phase: ArcadeMusicPhase?) {
        guard requestedMusic != phase else { return }
        requestedMusic = phase
        updateMusic()
    }

    private func updateMusic() {
        let active = enabled && volume > 0 && !muted.contains(.arcadeMusic) ? requestedMusic : nil
        if let current = playingMusic {
            if current.phase == active && current.voice.isPlaying {
                current.voice.volume = Float(volume) * PetSound.arcadeMusic.gain
                return
            }
            current.voice.stop()
            playingMusic = nil
        }
        guard let phase = active else { return }
        guard let data = musicWaves[phase] else {
            guard loadingMusic.insert(phase).inserted else { return }
            loadMusic(phase) { [weak self] data in
                guard let self else { return }
                self.loadingMusic.remove(phase)
                self.musicWaves[phase] = data
                if self.requestedMusic == phase { self.updateMusic() }
            }
            return
        }
        guard let voice = makeVoice(data) else { return }
        voice.volume = Float(volume) * PetSound.arcadeMusic.gain
        voice.loops = true
        if voice.play() { playingMusic = (phase, voice) }
    }

    func play(_ sound: PetSound, preview: Bool = false) {
        guard enabled, volume > 0, preview || !muted.contains(sound) else { return }
        let now = clock()
        if preview {
            guard now - lastPreview >= 0.09 else { return }
        } else if let last = lastPlayed[sound], now - last < sound.minimumInterval { return }

        playing.removeAll { !$0.voice.isPlaying }
        if preview {
            stop { $0.preview || $0.kind == sound }
            if playing.count >= 3 { playing.removeFirst().voice.stop() }
        } else if playing.count >= 3,
                  let index = playing.firstIndex(where: { !$0.preview && $0.kind.priority < sound.priority }) {
            playing.remove(at: index).voice.stop()
        }
        guard playing.count < 3 else { return }
        let data = waves[sound] ?? sound.waveData()
        waves[sound] = data
        guard let voice = makeVoice(data) else { return }
        voice.volume = Float(volume) * sound.gain
        guard voice.play() else { return }
        playing.append(Playing(kind: sound, voice: voice, preview: preview))
        lastPlayed[sound] = now
        if preview { lastPreview = now }
    }

    private func stop(where matches: (Playing) -> Bool) {
        playing.removeAll { cue in
            guard matches(cue) else { return false }
            cue.voice.stop()
            return true
        }
    }
}
