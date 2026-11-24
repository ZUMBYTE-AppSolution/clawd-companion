import CryptoKit
import Darwin
import Foundation

/// Looks up only sessions that reported an outstanding main-thread permission hook.
/// Each request date is returned unchanged, so the hook store can reject stale answers.
@MainActor
final class ClaudeSessionStatus {
    private var pending: [String: Date] = [:]
    private var tracker = ClaudeApprovalSamples()
    private var task: Task<Void, Never>?
    private var epoch: UInt = 0
    private var nextRead: TimeInterval = 0
    private let read: @Sendable (Set<String>) -> [String: Bool]?
    private let uptime: () -> TimeInterval

    init(read: @escaping @Sendable (Set<String>) -> [String: Bool]? = { ClaudeAgentList.read(sessionKeys: $0) },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.read = read
        self.uptime = uptime
    }

    nonisolated static func sessionKey(_ sessionID: String) -> String {
        SHA256.hash(data: Data(sessionID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func update(pending requests: [String: Date], onResume: @escaping @MainActor ([String: Date]) -> Void) {
        guard !requests.isEmpty else { stop(); return }
        if pending.isEmpty { nextRead = 0 }
        pending = requests
        tracker.retain(requests)
        guard task == nil, uptime() >= nextRead else { return }
        let launchedIn = epoch
        let read = self.read
        task = Task.detached(priority: .utility) { [weak self] in
            let states = Task.isCancelled ? nil : read(Set(requests.keys))
            await self?.completed(states, queried: requests, epoch: launchedIn, onResume: onResume)
        }
    }

    private func completed(_ states: [String: Bool]?, queried: [String: Date], epoch: UInt,
                           onResume: @MainActor ([String: Date]) -> Void) {
        task = nil
        guard epoch == self.epoch, !pending.isEmpty else { return }
        nextRead = uptime() + (states == nil ? 20 : 1)
        let stillCurrent = queried.filter { pending[$0.key] == $0.value }
        let resolved = tracker.observe(states ?? [:], requests: stillCurrent)
        if !resolved.isEmpty { onResume(resolved) }
    }

    func stop() {
        guard !pending.isEmpty else { return }
        epoch &+= 1
        pending.removeAll()
        tracker = ClaudeApprovalSamples()
        task?.cancel()
        // Keep the slot occupied until the cancelled reader has exited.
    }
}

struct ClaudeApprovalSamples {
    private var lastKnown: [String: Date] = [:]

    mutating func retain(_ requests: [String: Date]) {
        lastKnown = lastKnown.filter { requests[$0.key] == $0.value }
    }

    /// The first busy sample may predate display of a just-announced prompt.
    /// Confirm a transition from waiting, or require two consecutive known nonwaits.
    mutating func observe(_ states: [String: Bool], requests: [String: Date]) -> [String: Date] {
        var resolved: [String: Date] = [:]
        for (key, date) in requests {
            guard let waiting = states[key] else { lastKnown.removeValue(forKey: key); continue }
            if !waiting, lastKnown[key] == date {
                // A previous wait confirms the transition. A previous nonwait
                // confirms progress for prompts answered before our first lookup.
                resolved[key] = date
            }
            lastKnown[key] = date
        }
        return resolved
    }
}

enum ClaudeAgentList {
    private struct Row: Decodable {
        let sessionId: String?
        let status: String?
        let waitingFor: String?
        let state: String?

        var waiting: Bool? {
            switch status {
            case "busy", "idle": return false
            case "waiting":
                switch waitingFor {
                case "permission prompt", "sandbox request": return true
                case "input needed", "worker request", "dialog open": return false
                default: return nil
                }
            case nil where ["done", "failed", "stopped"].contains(state): return false
            default: return nil
            }
        }
    }

    static func decode(_ data: Data, sessionKeys: Set<String>) -> [String: Bool]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var result: [String: Bool] = [:]
        for row in rows {
            guard let id = row.sessionId, !id.isEmpty, id.utf8.count <= 512,
                  let waiting = row.waiting else { continue }
            let key = ClaudeSessionStatus.sessionKey(id)
            if sessionKeys.contains(key) {
                // If two rows describe a resumed session, an explicit prompt wins.
                result[key] = waiting || result[key] == true
            }
        }
        return result
    }

    static func read(sessionKeys: Set<String>) -> [String: Bool]? {
        guard !sessionKeys.isEmpty, !Task.isCancelled else { return nil }
        let fm = FileManager.default
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let directories = inherited.filter { $0.hasPrefix("/") } + [
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
        ]
        for directory in directories {
            let executable = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("claude")
            guard fm.isExecutableFile(atPath: executable.path) else { continue }
            // GUI apps often have a smaller PATH than the user's terminal. Keep
            // npm-installed binaries able to find their node interpreter.
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = directories.joined(separator: ":")
            guard let data = output(executable: executable, arguments: ["agents", "--json"],
                                    environment: environment) else { return nil }
            return decode(data, sessionKeys: sessionKeys)
        }
        return nil
    }

    /// Reads the CLI on a worker. Timeout and size are enforced while the child
    /// runs, including when stdout is left open by a descendant.
    static func output(executable: URL, arguments: [String], environment: [String: String],
                       timeout: TimeInterval = 3, limit: Int = 1024 * 1024) -> Data? {
        let command = Process()
        command.executableURL = executable
        command.arguments = arguments
        command.environment = environment
        command.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        command.standardInput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        command.standardOutput = pipe
        guard !Task.isCancelled else { return nil }
        do { try command.run() } catch { return nil }
        try? pipe.fileHandleForWriting.close()
        defer {
            try? pipe.fileHandleForReading.close()
            if command.isRunning { Darwin.kill(command.processIdentifier, SIGKILL) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var bytes = [UInt8](repeating: 0, count: 8192)
        var data = Data()
        var ended = false
        while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            if ended && !command.isRunning {
                return command.terminationStatus == 0 ? data : nil
            }
            var fd = pollfd(fd: ended ? -1 : pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&fd, 1, 40)
            if ready < 0 && errno != EINTR { return nil }
            guard ready > 0 else { continue }
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd.fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { ended = true; continue }
            guard data.count + count <= limit else { return nil }
            data.append(contentsOf: bytes.prefix(count))
        }
        return nil
    }
}
