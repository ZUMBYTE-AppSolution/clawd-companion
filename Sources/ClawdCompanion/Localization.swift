import Foundation
#if SWIFT_PACKAGE
import ClawdLanguageResources
#endif

extension Notification.Name {
    static let clawdLanguageChanged = Notification.Name("de.zumbyte.clawd.languageChanged")
}

enum L10n {
    // Use native names so the picker is recognizable even after a mistaken choice.
    static let choices = [("de", "Deutsch"), ("en", "English"), ("zh-Hans", "简体中文"),
                          ("hi", "हिन्दी"), ("es", "Español"), ("ar", "العربية"), ("fr", "Français"),
                          ("bn", "বাংলা"), ("pt", "Português"), ("id", "Bahasa Indonesia"), ("ur", "اردو")]
    private static let lock = NSLock()
    private static var active = "de"
    static var code: String { lock.lock(); defer { lock.unlock() }; return active }
    static var locale: Locale { Locale(identifier: code) }
    static var isRTL: Bool { ["ar", "ur"].contains(code) }

    static func resolve(_ choice: String, preferred: [String] = Locale.preferredLanguages) -> String {
        for tag in choice == "system" ? preferred : [choice] {
            let language = tag.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first
            if language == "zh" || language == "cmn" { return "zh-Hans" }
            if language == "in" { return "id" }
            if let supported = choices.first(where: { $0.0 == language.map(String.init) }) { return supported.0 }
        }
        return "en"
    }

    static func select(_ choice: String) {
        let new = resolve(choice)
        lock.lock()
        let changed = new != active
        active = new
        lock.unlock()
        if changed { NotificationCenter.default.post(name: .clawdLanguageChanged, object: nil) }
    }

    static var directory: URL? {
        #if SWIFT_PACKAGE
        return LanguageResources.directory
        #else
        return Bundle.main.resourceURL?.appendingPathComponent("Languages")
        #endif
    }

    static let catalogue: [String: [String: String]] = {
        guard let directory, let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: [String: String]] = [:]
        for url in urls.sorted(by: { $0.path < $1.path }) where url.pathExtension == "tsv" {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = contents.split(whereSeparator: \.isNewline)
            guard let header = lines.first else { continue }
            let codes = header.components(separatedBy: "\t")
            for line in lines.dropFirst() {
                let cells = line.components(separatedBy: "\t")
                guard cells.count == codes.count, let key = cells.first, !key.isEmpty else { continue }
                for (lang, text) in zip(codes, cells) where !text.isEmpty {
                    result[key, default: [:]][lang] = text
                }
            }
        }
        return result
    }()

    static func text(_ key: String, in lang: String, values: [String] = []) -> String {
        let pattern = lang == "de" ? key : catalogue[key]?[lang] ?? key
        guard !values.isEmpty else { return pattern }
        // Replace only placeholders in the template, never placeholders in an inserted value.
        var result = "", rest = pattern[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            if let i = Int(rest[rest.index(after: open)..<close]), values.indices.contains(i) { result += values[i] }
            else { result += rest[open...close] }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }
}

func L(_ german: String, _ args: String...) -> String {
    L10n.text(german, in: L10n.code, values: args)
}
