import AppKit
import XCTest
@testable import ClawdCompanion

@MainActor private final class SilentVoice: CompanionSoundVoice {
    var isPlaying = false
    var volume: Float = 0
    var loops = false
    @discardableResult func play() -> Bool { isPlaying = true; return true }
    @discardableResult func stop() -> Bool { isPlaying = false; return true }
}

final class CompanionAudioTests: XCTestCase {
    func testArcadeScoresHaveDistinctLoopableFourBarPhrases() throws {
        var waves: Set<Data> = []
        for phase: ArcadeMusicPhase in [.wave, .boss] {
            let data = phase.waveData()
            XCTAssertTrue(waves.insert(data).inserted)
            let decoded = try XCTUnwrap(NSSound(data: data))
            XCTAssertEqual(decoded.duration, phase == .wave ? 7.84 : 6.656, accuracy: 0.001)
            XCTAssertEqual(data.count, 44 + Int((decoded.duration * 22_050).rounded()) * 2)
            let samples = stride(from: 44, to: data.count, by: 2).map { index in
                Int(Int16(bitPattern: UInt16(data[index]) | UInt16(data[index + 1]) << 8))
            }
            XCTAssertEqual(samples.first, 0)
            XCTAssertEqual(samples.last, 0)
            let peak = samples.map(abs).max()!
            XCTAssertGreaterThan(peak, 3_000)
            XCTAssertLessThan(peak, 12_000)
        }
    }

    @MainActor func testMusicOnlyPlaysInRequestedPhaseAndObeysLiveControls() async {
        var voices: [SilentVoice] = []
        var loads: [ArcadeMusicPhase] = []
        let audio = CompanionAudio(makeVoice: { _ in
            let voice = SilentVoice()
            voices.append(voice)
            return voice
        }, loadMusic: { phase, ready in
            loads.append(phase)
            ready(Data())
        })
        XCTAssertTrue(audio.enabled)
        XCTAssertTrue(audio.muted.isEmpty)
        XCTAssertEqual(audio.volume, 0.28)
        XCTAssertTrue(voices.isEmpty)
        audio.setArcadeMusic(.wave)
        audio.setArcadeMusic(.wave)
        XCTAssertEqual(voices.count, 1)
        XCTAssertTrue(voices[0].loops)
        XCTAssertTrue(voices[0].isPlaying)
        audio.volume = 0.5
        XCTAssertEqual(voices[0].volume, 0.5 * 0.62, accuracy: 0.001)
        audio.play(.arcadeHit)
        XCTAssertFalse(voices[1].loops)
        audio.setArcadeMusic(.boss)
        XCTAssertEqual(loads, [.wave, .boss])
        XCTAssertFalse(voices[0].isPlaying)
        XCTAssertTrue(voices[1].isPlaying)
        XCTAssertTrue(voices[2].isPlaying)
        audio.muted.insert(.arcadeMusic)
        XCTAssertFalse(voices[2].isPlaying)
        XCTAssertTrue(voices[1].isPlaying)
        audio.muted.remove(.arcadeMusic)
        XCTAssertTrue(voices[3].isPlaying)
        XCTAssertEqual(loads.count, 2)
        audio.enabled = false
        XCTAssertFalse(voices.contains(where: \.isPlaying))
        audio.enabled = true
        XCTAssertTrue(voices[4].loops)
        audio.volume = 0
        XCTAssertFalse(voices[4].isPlaying)
        audio.setArcadeMusic(nil)
        audio.volume = 0.3
        XCTAssertEqual(voices.count, 5)
        audio.setArcadeMusic(.wave)
        XCTAssertTrue(voices[5].isPlaying)
        audio.setArcadeMusic(nil)
        XCTAssertFalse(voices[5].isPlaying)
    }

    @MainActor func testPendingMusicCannotStartAfterPauseOrReplaceANewerPhase() async {
        var ready: [ArcadeMusicPhase: @MainActor (Data) -> Void] = [:]
        var voices: [SilentVoice] = []
        let audio = CompanionAudio(makeVoice: { _ in
            let voice = SilentVoice()
            voices.append(voice)
            return voice
        }, loadMusic: { ready[$0] = $1 })
        audio.setArcadeMusic(.wave)
        audio.setArcadeMusic(nil)
        audio.setArcadeMusic(.boss)
        ready[.wave]?(Data())
        XCTAssertTrue(voices.isEmpty)
        audio.setArcadeMusic(nil)
        ready[.boss]?(Data())
        XCTAssertTrue(voices.isEmpty)
        audio.setArcadeMusic(.boss)
        XCTAssertEqual(voices.count, 1)
        XCTAssertTrue(voices[0].isPlaying)
    }

    @MainActor func testArcadeSoundsThrottleBurstsAndReserveBossEntrance() async {
        var now = 1.0
        var voices: [SilentVoice] = []
        let audio = CompanionAudio(clock: { now }, makeVoice: { _ in
            let voice = SilentVoice()
            voices.append(voice)
            return voice
        })
        audio.play(.arcadeFire)
        audio.play(.arcadeHit)
        now += 0.05
        audio.play(.arcadeFire)
        audio.play(.arcadeHit)
        XCTAssertEqual(voices.count, 2)
        audio.play(.arcadePickup)
        audio.play(.arcadeBoss)
        XCTAssertEqual(voices.count, 4)
        XCTAssertFalse(voices[0].isPlaying)
        XCTAssertTrue(voices[2].isPlaying)
        XCTAssertEqual(voices.filter(\.isPlaying).count, 3)
        audio.muted.insert(.arcadeBoss)
        XCTAssertFalse(voices[3].isPlaying)
        now += 0.3
        audio.play(.arcadeFire)
        XCTAssertEqual(voices.count, 5)
    }

    func testEveryCueDecodesAsDistinctShortMonoPCM() throws {
        var waves: Set<Data> = []
        for sound in PetSound.allCases {
            let data = sound.waveData()
            XCTAssertTrue(waves.insert(data).inserted, sound.rawValue)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
            func u16(_ offset: Int) -> UInt16 {
                UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            }
            func u32(_ offset: Int) -> UInt32 {
                UInt32(u16(offset)) | (UInt32(u16(offset + 2)) << 16)
            }
            XCTAssertEqual(u32(4), UInt32(data.count - 8))
            XCTAssertEqual(u32(40), UInt32(data.count - 44))
            XCTAssertEqual(u16(20), 1)  // PCM
            XCTAssertEqual(u16(22), 1)  // mono
            XCTAssertEqual(u32(24), 22_050)
            XCTAssertEqual(u16(34), 16)
            XCTAssertEqual(u16(44), 0)
            XCTAssertEqual(u16(data.count - 2), 0)
            let pcmPeak = stride(from: 44, to: data.count, by: 2)
                .map { abs(Int(Int16(bitPattern: u16($0)))) }.max()!
            XCTAssertGreaterThan(pcmPeak, 1900)
            XCTAssertLessThanOrEqual(pcmPeak, Int(Int16.max) / 3)
            let decoded = try XCTUnwrap(NSSound(data: data))
            let duration = Double(data.count - 44) / 44_100
            XCTAssertEqual(decoded.duration, duration, accuracy: 0.003)
            XCTAssertTrue((0.04...0.5).contains(duration))
        }
    }

    @MainActor func testMutePreviewLevelsAndMasterStopWithoutDevicePlayback() async {
        var voices: [SilentVoice] = []
        var now = 1.0
        let audio = CompanionAudio(clock: { now }, makeVoice: { _ in
            let voice = SilentVoice()
            voices.append(voice)
            return voice
        })
        audio.muted = [.rappel]
        audio.play(.rappel)
        XCTAssertTrue(voices.isEmpty)
        audio.play(.rappel, preview: true)
        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices[0].volume, 0.28, accuracy: 0.001)
        audio.volume = 4
        XCTAssertEqual(voices[0].volume, 1)
        audio.enabled = false
        XCTAssertFalse(voices[0].isPlaying)
        now += 1
        audio.play(.rappel, preview: true)
        XCTAssertEqual(voices.count, 1)
        audio.enabled = true
        audio.volume = 0
        audio.play(.rappel, preview: true)
        XCTAssertEqual(voices.count, 1)
        audio.volume = 0.19
        audio.play(.steps)
        XCTAssertEqual(voices.last?.volume, 0.19)
        audio.muted.insert(.steps)
        XCTAssertEqual(voices.last?.isPlaying, false)
    }

    @MainActor func testRepeatsVoicesAndPreviewStayBounded() async {
        var now = 0.0
        var voices: [SilentVoice] = []
        let audio = CompanionAudio(clock: { now }, makeVoice: { _ in
            let voice = SilentVoice()
            voices.append(voice)
            return voice
        })
        audio.play(.steps)
        audio.play(.steps)
        audio.play(.climb)
        audio.play(.jump)
        audio.play(.land)
        XCTAssertEqual(voices.count, 3)
        audio.play(.land, preview: true)
        XCTAssertEqual(voices.count, 4)
        XCTAssertFalse(voices[0].isPlaying)
        XCTAssertEqual(voices.filter(\.isPlaying).count, 3)
        audio.play(.peek, preview: true)
        XCTAssertEqual(voices.count, 4)
        now += 0.11
        audio.play(.peek, preview: true)
        XCTAssertFalse(voices[3].isPlaying)
        XCTAssertEqual(voices.filter(\.isPlaying).count, 3)
        voices[1].stop()
        audio.play(.steps)
        XCTAssertEqual(voices.count, 5)
        now += 1.0
        audio.play(.steps)
        XCTAssertEqual(voices.count, 6)
        XCTAssertEqual(voices.filter(\.isPlaying).count, 3)
    }
}
