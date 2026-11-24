import AVFoundation
import Foundation

@MainActor
final class ClawdVoice: NSObject, AVSpeechSynthesizerDelegate {
    var enabled = false {
        didSet { if !enabled { stop() } }
    }

    private struct Phrase: Equatable {
        let text: String
        let language: String
        let voice: AVSpeechSynthesisVoice

        static func == (a: Self, b: Self) -> Bool { a.text == b.text && a.language == b.language }
    }

    private static var voices: [AVSpeechSynthesisVoice] = []
    private static var refreshAfter: TimeInterval = -.infinity
    private var synth: AVSpeechSynthesizer?
    private var current: (phrase: Phrase, utterance: AVSpeechUtterance)?
    private var pending: [Phrase] = []

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .clawdLanguageChanged, object: nil)
    }

    @objc private func languageChanged() { stop() }

    static func hasVoice(for language: String) -> Bool { availableVoice(language) != nil }

    /// Keep the requested language and writing system. In particular a Cantonese
    /// voice or a different-script fallback must not take over a Mandarin message.
    static func match(_ candidate: String, to requested: String) -> Int? {
        let first = Locale.Language(identifier: requested)
        let second = Locale.Language(identifier: candidate)
        guard let language = first.languageCode, language == second.languageCode else { return nil }
        if first.languageCode?.identifier == "zh" {
            let cantoneseRegions = ["HK", "MO"]
            let a = first.region.map { cantoneseRegions.contains($0.identifier) } ?? false
            let b = second.region.map { cantoneseRegions.contains($0.identifier) } ?? false
            if a != b { return nil }
        }
        guard first.script == second.script else { return nil }
        if requested.replacingOccurrences(of: "_", with: "-").caseInsensitiveCompare(
            candidate.replacingOccurrences(of: "_", with: "-")) == .orderedSame { return 3 }
        return first.maximalIdentifier == second.maximalIdentifier ? 2 : 1
    }

    private static func availableVoice(_ language: String) -> AVSpeechSynthesisVoice? {
        let now = ProcessInfo.processInfo.systemUptime
        if now >= refreshAfter {
            voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
                guard voice.identifier.hasPrefix("com.apple.") else { return false }
                if #available(macOS 14.0, *), voice.voiceTraits.contains(.isNoveltyVoice) { return false }
                return true
            }
            refreshAfter = now + 15
        }
        return voices.compactMap { voice -> (voice: AVSpeechSynthesisVoice, rank: Int)? in
            guard let match = match(voice.language, to: language) else { return nil }
            return (voice, match * 10 + voice.quality.rawValue)
        }.max { $0.rank < $1.rank }?.voice
    }

    func speak(_ text: String, language: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !text.isEmpty, let voice = Self.availableVoice(language) else { return }
        let phrase = Phrase(text: String(text.prefix(320)), language: language, voice: voice)
        if let current, current.phrase.language != language { stop() }
        guard phrase != current?.phrase, !pending.contains(phrase) else { return }
        if pending.count >= 2 { pending.removeFirst() }
        pending.append(phrase)
        startNext()
    }

    private func startNext() {
        guard enabled, current == nil, !pending.isEmpty else { return }
        if synth == nil {
            synth = AVSpeechSynthesizer()
            synth?.delegate = self
        }
        let phrase = pending.removeFirst()
        let utterance = AVSpeechUtterance(string: phrase.text)
        utterance.voice = phrase.voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        current = (phrase, utterance)
        synth?.speak(utterance)
    }

    func stop() {
        pending.removeAll()
        current = nil
        synth?.stopSpeaking(at: .immediate)
    }

    private nonisolated func ended(_ utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, current?.utterance === utterance else { return }
            current = nil
            startNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(utterance)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(utterance)
    }
}
