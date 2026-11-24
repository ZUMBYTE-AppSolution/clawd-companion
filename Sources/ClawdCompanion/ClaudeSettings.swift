import Darwin
import Foundation

/// Shared by the two optional Claude Code integrations. Neither integration writes settings at launch.
enum ClaudeSettings {
    typealias Object = [String: Any]

    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    static var settingsURL: URL {
        let directory: URL
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], configured.hasPrefix("/") {
            directory = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        }
        return directory.appendingPathComponent("settings.json").resolvingSymlinksInPath()
    }

    static var integrationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClawdCompanion/Integration", isDirectory: true)
    }

    static var helperURL: URL { integrationDirectory.appendingPathComponent("ClawdCLI") }

    static var quotedHelperPath: String {
        "'" + helperURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func prepareHelper() throws {
        guard let executable = Bundle.main.executableURL else {
            throw Problem("Das Programm für die Claude-Code-Anbindung wurde nicht gefunden.")
        }
        try makeDirectory(integrationDirectory)
        if FileManager.default.contentsEqual(atPath: executable.path, andPath: helperURL.path) { return }
        // A single rename replaces an older helper without interrupting running invocations.
        let staged = integrationDirectory.appendingPathComponent(".helper-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: executable, to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        try atomicRename(staged, to: helperURL)
    }

    static func makeDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    static func read() throws -> Object {
        try decode(try readBytes(at: settingsURL))
    }

    private static func readBytes(at url: URL) throws -> Data? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else {
                throw Problem("Die Claude-Einstellungen sind keine reguläre Datei.")
            }
            return try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    private static func decode(_ source: Data?) throws -> Object {
        guard let source else { return [:] }
        guard let result = try? JSONSerialization.jsonObject(with: source) as? Object else {
            throw Problem("Die Claude-Einstellungen enthalten kein gültiges JSON-Objekt. Die Datei wurde unverändert gelassen.")
        }
        return result
    }

    private static func atomicRename(_ source: URL, to destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    static func update(_ transform: (inout Object) throws -> Void) throws {
        let destination = settingsURL
        try makeDirectory(integrationDirectory)
        let lockURL = integrationDirectory.appendingPathComponent("settings.lock")
        let descriptor = Darwin.open(lockURL.path, O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw Problem("Die Einstellungen werden gerade bearbeitet. Bitte versuche es noch einmal.")
        }

        let originalData = try readBytes(at: destination)
        let original = try decode(originalData)
        var changed = original
        try transform(&changed)
        guard !NSDictionary(dictionary: original).isEqual(to: changed) else { return }

        let folder = destination.deletingLastPathComponent()
        try makeDirectory(folder)
        var data = try JSONSerialization.data(withJSONObject: changed, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0a)
        let staged = folder.appendingPathComponent(".clawd-settings-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        if originalData != nil {
            // Retain file permissions and ACLs when replacing the settings file.
            try FileManager.default.copyItem(at: destination, to: staged)
        } else {
            guard FileManager.default.createFile(atPath: staged.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw Problem("Die neuen Claude-Einstellungen konnten nicht vorbereitet werden.")
            }
        }
        let handle = try FileHandle(forWritingTo: staged)
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard try readBytes(at: destination) == originalData else {
            throw Problem("Claude hat seine Einstellungen gleichzeitig geändert. Bitte versuche es noch einmal.")
        }
        try atomicRename(staged, to: destination)
    }
}
