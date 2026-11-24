import Foundation

enum ArcadeMusicPhase: Hashable, Sendable {
    case wave, boss

    // A step is an eighth note. Four bars leave room for the in-game sound effects.
    private typealias Note = (step: Int, midi: Int, length: Double)
    private enum Instrument { case bass, pluck, kick, tick }

    private var melody: [Note] {
        switch self {
        case .wave:
            return [(0, 74, 1.65), (3, 77, 0.72), (4, 81, 1.6), (7, 79, 0.65),
                    (9, 76, 1.4), (12, 72, 1.8), (15, 76, 0.52),
                    (16, 77, 1.6), (19, 81, 0.7), (20, 84, 1.7), (23, 81, 0.63),
                    (25, 79, 1.5), (28, 76, 0.8), (30, 72, 1.2)]
        case .boss:
            return [(0, 62, 0.7), (2, 69, 0.7), (3, 68, 0.68), (5, 65, 1.6),
                    (8, 63, 0.7), (10, 70, 0.68), (11, 69, 0.7), (13, 66, 1.5),
                    (16, 62, 0.7), (18, 74, 0.7), (19, 73, 0.7), (21, 69, 1.4),
                    (24, 67, 0.8), (26, 65, 0.7), (28, 63, 0.75), (30, 61, 1.2)]
        }
    }

    func waveData() -> Data {
        let rate = Double(CompanionPCM.rate)
        let secondsPerStep = self == .boss ? 0.208 : 0.245
        let samplesPerStep = rate * secondsPerStep
        var mix = Array(repeating: 0.0, count: Int((32 * samplesPerStep).rounded()))

        func add(_ instrument: Instrument, _ note: Note, level: Double) {
            let start = Int((Double(note.step) * samplesPerStep).rounded())
            let count = min(mix.count - start, Int((note.length * samplesPerStep).rounded()))
            let frequency = 440 * pow(2, Double(note.midi - 69) / 12)
            var phase = 0.0
            var noise = UInt32(note.step + 89)
            var previousNoise = 0.0
            for index in 0..<count {
                let progress = Double(index) / Double(count - 1)
                let onset = min(1, Double(index) / (rate * 0.005))
                let release = min(1, Double(count - 1 - index) / (rate * 0.035))
                let tone: Double
                switch instrument {
                case .pluck:
                    let fundamental = sin(phase)
                    tone = (0.80 * fundamental + 0.14 * sin(3 * phase) + 0.06 * sin(5 * phase))
                        * exp(-2.1 * progress)
                case .bass:
                    tone = (0.82 * sin(phase) + 0.18 * sin(2 * phase)) * (1 - 0.7 * progress)
                case .kick:
                    tone = sin(phase) * exp(-4 * progress)
                case .tick:
                    noise = 1_664_525 &* noise &+ 1_013_904_223
                    let nextNoise = Double(noise) / Double(UInt32.max) - 0.5
                    tone = (nextNoise - previousNoise) * exp(-4 * progress)
                    previousNoise = nextNoise
                }
                mix[start + index] += level * onset * release * tone
                let pitch = instrument == .kick ? frequency * (1 + 2 * exp(-6 * progress)) : frequency
                phase += pitch * 2 * .pi / rate
            }
        }

        for note in melody {
            add(.pluck, note, level: self == .boss ? 3_500 : 3_800)
        }
        let roots = self == .boss ? [38, 39, 38, 33] : [50, 48, 46, 48]
        for (bar, root) in roots.enumerated() {
            let step = 8 * bar
            add(.bass, (step, root, 2.7), level: 3_900)
            add(.bass, (step + 4, root + 7, 1.7), level: 3_100)
            add(.kick, (step, 35, 0.48), level: 3_300)
            add(.tick, (step + 2, 0, 0.32), level: 1_350)
            add(.tick, (step + 6, 0, 0.34), level: 1_750)
            if self == .boss {
                add(.kick, (step + 3, 35, 0.45), level: 2_300)
                add(.kick, (step + 4, 35, 0.48), level: 3_000)
                add(.bass, (step + 7, root + 12, 0.66), level: 2_500)
            }
        }
        return CompanionPCM.wave(mix.map { Int16($0.rounded()).littleEndian })
    }
}
