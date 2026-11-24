import Foundation

struct CodeQuotaWindow: Codable, Equatable {
    let remainingPercent: Double
    let resetsAt: Date
}

struct CodeQuotaSnapshot: Codable, Equatable {
    let observedAt: Date
    let fiveHour: CodeQuotaWindow?
    let sevenDay: CodeQuotaWindow?

    /// Elapsed windows disappear until Claude reports a fresh measurement.
    func valid(at date: Date) -> Self? {
        let session = fiveHour.flatMap { $0.resetsAt > date ? $0 : nil }
        let week = sevenDay.flatMap { $0.resetsAt > date ? $0 : nil }
        guard session != nil || week != nil else { return nil }
        return Self(observedAt: observedAt, fiveHour: session, sevenDay: week)
    }
}

struct QuotaStatusLine {
    private let cacheDirectory: URL
    private var cacheURL: URL { cacheDirectory.appendingPathComponent("last-reading.json") }
    private var ownCommand: String { "\(ClaudeSettings.quotedHelperPath) --clawd-quota" }
    private var pipePrefix: String {
        // The original command still gets its input if the companion was deleted manually.
        let helper = ClaudeSettings.quotedHelperPath
        return "{ if [ -x \(helper) ]; then \(helper) --clawd-quota-pipe; else /bin/cat; fi; } | (\n"
    }
    private let pipeSuffix = "\n)"

    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? ClaudeSettings.helperURL.deletingLastPathComponent()
            .appendingPathComponent("Quota", isDirectory: true)
    }

    var isInstalled: Bool {
        guard let settings = try? ClaudeSettings.read(),
              let line = settings["statusLine"] as? [String: Any],
              line["type"] as? String == "command",
              let command = line["command"] as? String else { return false }
        return command == ownCommand || originalCommand(from: command) != nil
    }

    func install() throws {
        try ClaudeSettings.prepareHelper()
        try ClaudeSettings.update { settings in
            var line: [String: Any]
            if let existing = settings["statusLine"] {
                guard let current = existing as? [String: Any], current["type"] as? String == "command",
                      let command = current["command"] as? String, !command.isEmpty else {
                    throw setupError("Die bestehende Statuszeile verwendet ein unbekanntes Format. Ihre Konfiguration bleibt erhalten.")
                }
                line = current
                if command != ownCommand && originalCommand(from: command) == nil {
                    line["command"] = pipePrefix + command + pipeSuffix
                }
            } else {
                line = ["type": "command", "command": ownCommand]
            }
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            settings["statusLine"] = line
        }
    }

    func uninstall() throws {
        try ClaudeSettings.update { settings in
            guard var line = settings["statusLine"] as? [String: Any],
                  line["type"] as? String == "command", let command = line["command"] as? String else { return }
            if command == ownCommand {
                settings.removeValue(forKey: "statusLine")
            } else if let original = originalCommand(from: command) {
                line["command"] = original
                settings["statusLine"] = line
            }
        }
        // The collector never creates this directory. Once removed, an already-running
        // Claude Code session cannot keep recording new readings.
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    private func originalCommand(from command: String) -> String? {
        guard command.hasPrefix(pipePrefix), command.hasSuffix(pipeSuffix),
              command.count > pipePrefix.count + pipeSuffix.count else { return nil }
        return String(command.dropFirst(pipePrefix.count).dropLast(pipeSuffix.count))
    }

    private func setupError(_ message: String) -> NSError {
        NSError(domain: "ClawdCompanion.Quota", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func latest() -> CodeQuotaSnapshot? {
        guard let raw = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(CodeQuotaSnapshot.self, from: raw) else { return nil }
        return snapshot.valid(at: Date())
    }

    /// These are subscription rate limits from the documented status-line stdin schema.
    /// Only percentages, reset times and the local observation time are written to disk.
    static func parse(_ input: Data, at now: Date) -> CodeQuotaSnapshot? {
        struct Input: Decodable {
            struct Window: Decodable {
                let used_percentage: Double
                let resets_at: Double

                func reading(at now: Date) -> CodeQuotaWindow? {
                    guard (0...100).contains(used_percentage), resets_at > now.timeIntervalSince1970,
                          resets_at < 32_503_680_000 else { return nil }
                    return CodeQuotaWindow(remainingPercent: 100 - used_percentage, resetsAt: Date(timeIntervalSince1970: resets_at))
                }
            }
            struct Limits: Decodable {
                let session: Window?
                let week: Window?
                enum CodingKeys: String, CodingKey { case five_hour, seven_day }

                init(from decoder: Decoder) throws {
                    let fields = try decoder.container(keyedBy: CodingKeys.self)
                    session = try? fields.decode(Window.self, forKey: .five_hour)
                    week = try? fields.decode(Window.self, forKey: .seven_day)
                }
            }
            let rate_limits: Limits?
        }
        guard let limits = try? JSONDecoder().decode(Input.self, from: input).rate_limits else { return nil }
        let session = limits.session?.reading(at: now)
        let week = limits.week?.reading(at: now)
        guard session != nil || week != nil else { return nil }
        return CodeQuotaSnapshot(observedAt: now, fiveHour: session, sevenDay: week)
    }

    /// Call before starting AppKit. A chained status line must receive exactly the
    /// original byte stream, including fields we never read or store.
    static func handleCommandLine() -> Bool {
        let argument = CommandLine.arguments.dropFirst().first
        guard argument == "--clawd-quota" || argument == "--clawd-quota-pipe" else { return false }
        QuotaStatusLine().collect(passThrough: argument == "--clawd-quota-pipe")
        return true
    }

    private func collect(passThrough: Bool) {
        var data = Data()
        var oversized = false
        while let chunk = try? FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
            if passThrough { try? FileHandle.standardOutput.write(contentsOf: chunk) }
            if !oversized && data.count + chunk.count <= 2_097_152 {
                data.append(chunk)
            } else {
                oversized = true
            }
        }
        let reading = oversized ? nil : Self.parse(data, at: Date())
        if let reading, let encoded = try? JSONEncoder().encode(reading) {
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        if !passThrough {
            let portions = [(reading?.fiveHour, "5 h"), (reading?.sevenDay, "7 Tage")].compactMap { window, name in
                window.map { "\(name) · \(Int($0.remainingPercent.rounded(.down))) % frei" }
            }
            print(portions.isEmpty ? "Claw’d" : portions.joined(separator: "   "))
        }
    }
}
