import CryptoKit
import Darwin
import Foundation

enum ClaudeHooks {
    typealias Snapshot = (pose: MascotPose, label: String, date: Date, lifetime: TimeInterval, busy: Bool,
                          agentCount: Int, approvalCount: Int, pendingApprovals: [String: Date])
    private typealias Object = ClaudeSettings.Object
    private static var command: String { ClaudeSettings.quotedHelperPath + " --clawd-code-hook" }
    private static let originalEvents = ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
                                 "PostToolUseFailure", "Stop", "StopFailure", "SessionEnd"]
    private static let agentEvents = ["SubagentStart", "SubagentStop"]
    private static let events = originalEvents + agentEvents + ["Notification", "PostToolBatch"]
    // A terminated Claude process can miss its final hooks. Expire that observation;
    // tool events from a known running agent renew its individual window.
    private static let agentLifetime: TimeInterval = 30 * 60
    private static var eventDirectory: URL {
        ClaudeSettings.integrationDirectory.appendingPathComponent("Sessions", isDirectory: true)
    }

    private static var agentDirectory: URL { eventDirectory.appendingPathComponent("Agents", isDirectory: true) }
    private static var approvalDirectory: URL { eventDirectory.appendingPathComponent("Approvals", isDirectory: true) }
    private static var activityMarker: URL { eventDirectory.appendingPathComponent(".activity-props-v1") }

    private static var configuredEvents: Set<String> {
        guard let settings = try? ClaudeSettings.read(), let hooks = settings["hooks"] as? Object else { return [] }
        return Set(events.filter { event in
            (hooks[event] as? [Object] ?? []).contains { group in
                (group["hooks"] as? [Object] ?? []).contains(where: isOurs)
            }
        })
    }

    static var isInstalled: Bool { !configuredEvents.isEmpty }

    static var needsUpgrade: Bool {
        let installed = configuredEvents
        return !installed.isEmpty && (!Set(events).isSubset(of: installed) ||
                                      !FileManager.default.fileExists(atPath: activityMarker.path))
    }

    private static func isOurs(_ handler: Object) -> Bool {
        handler["type"] as? String == "command" && handler["command"] as? String == command
    }

    static func install() throws {
        try ClaudeSettings.prepareHelper()
        try editSettings(install: true)
        // An existing installation can have all the current event handlers
        // while still running a helper that predates the new tool categories.
        if !FileManager.default.fileExists(atPath: activityMarker.path) {
            try Data().write(to: activityMarker, options: .atomic)
        }
    }

    static func uninstall() throws {
        try editSettings(install: false)
        // Removing this directory also disables collectors cached by an older Claude session.
        if FileManager.default.fileExists(atPath: eventDirectory.path) {
            try FileManager.default.removeItem(at: eventDirectory)
        }
    }

    private static func editSettings(install: Bool) throws {
        try ClaudeSettings.update { settings in
            if install && settings["disableAllHooks"] as? Bool == true {
                throw ClaudeSettings.Problem("Claude Code hat alle Hooks deaktiviert. Aktiviere Hooks in Claude Code, bevor du Clawd verbindest.")
            }
            if settings["hooks"] != nil && !(settings["hooks"] is Object) {
                throw ClaudeSettings.Problem("Das bestehende hooks-Feld in den Claude-Einstellungen ist kein Objekt.")
            }
            var hooks = settings["hooks"] as? Object ?? [:]
            for event in events {
                if hooks[event] != nil && !(hooks[event] is [Object]) {
                    throw ClaudeSettings.Problem(L("Die vorhandene Hook-Konfiguration für {0} hat ein unbekanntes Format.", event))
                }
                var groups = hooks[event] as? [Object] ?? []
                if install {
                    guard !groups.contains(where: { ($0["hooks"] as? [Object] ?? []).contains(where: isOurs) }) else { continue }
                    let handler: Object = ["type": "command", "command": command, "timeout": 3]
                    var group: Object = ["hooks": [handler]]
                    if event == "Notification" { group["matcher"] = "permission_prompt" }
                    groups.append(group)
                } else {
                    groups = groups.compactMap { group in
                        guard let handlers = group["hooks"] as? [Object], handlers.contains(where: isOurs) else { return group }
                        let retained = handlers.filter { !isOurs($0) }
                        guard !retained.isEmpty else { return nil }
                        var updated = group
                        updated["hooks"] = retained
                        return updated
                    }
                }
                if groups.isEmpty {
                    // Only remove entries that we emptied.
                    if !(hooks[event] as? [Object] ?? []).isEmpty { hooks.removeValue(forKey: event) }
                } else {
                    hooks[event] = groups
                }
            }
            if hooks.isEmpty {
                if !(settings["hooks"] as? Object ?? [:]).isEmpty { settings.removeValue(forKey: "hooks") }
            } else {
                settings["hooks"] = hooks
            }
            if install {
                try ClaudeSettings.makeDirectory(agentDirectory)
                try ClaudeSettings.makeDirectory(approvalDirectory)
            }
        }
    }

    /// These are the only hook fields decoded. No prompts, transcripts, tool arguments or paths are stored.
    private struct Payload: Decodable {
        var hook_event_name: String
        var session_id: String
        var tool_name: String?
        var tool_use_id: String?
        var notification_type: String?
        var agent_id: String?
        struct BackgroundTask: Decodable { let type: String? }
        var background_tasks: [BackgroundTask]?
    }

    private enum Phase: String, Codable {
        case thinking, reading, searching, editing, executing, planning, drawing, tool, waiting, toolError, stopped, failed

        var presentation: (MascotPose, String) {
            switch self {
            case .thinking: return (.thinking, "Denkt nach")
            case .reading: return (.reading, "Liest eine Datei")
            case .searching: return (.researching, "Recherchiert")
            case .editing: return (.typing, "Bearbeitet eine Datei")
            case .executing: return (.executing, "Führt Code aus")
            case .planning: return (.planning, "Plant die nächsten Schritte")
            case .drawing: return (.drawing, "Erstellt ein Artefakt")
            case .tool: return (.typing, "Verwendet ein Werkzeug")
            case .waiting: return (.idle, "Startklar") // Records written by older installed helpers.
            case .toolError: return (.worried, "Ein Werkzeug meldet einen Fehler")
            case .stopped: return (.happy, "Antwort abgeschlossen")
            case .failed: return (.worried, "Antwort fehlgeschlagen")
            }
        }

        var isActive: Bool { self != .stopped && self != .failed }

        var lifetime: TimeInterval {
            switch self {
            case .waiting: return 15 * 60
            case .thinking, .reading, .searching, .editing, .executing, .planning, .drawing, .tool: return 5 * 60
            case .toolError: return 12
            case .stopped, .failed: return 10
            }
        }
    }

    private struct Record: Codable {
        let phase: Phase
        let date: Date
        // Keep a very short tool action visible through the next UI poll. New
        // activity always replaces this record, even before this deadline.
        var recentTool: Phase?
        var visibleUntil: Date?
    }

    private static func toolPhase(_ name: String?) -> Phase {
        switch name {
        case "Read", "ReadMcpResourceTool", "TaskOutput": return .reading
        case "Grep", "Glob", "WebSearch", "WebFetch", "ToolSearch", "ListMcpResourcesTool": return .searching
        case "Edit", "Write", "NotebookEdit", "MultiEdit": return .editing
        case "Bash", "PowerShell", "REPL": return .executing
        case "EnterPlanMode", "ExitPlanMode", "TodoWrite", "TaskCreate", "TaskGet", "TaskList", "TaskUpdate": return .planning
        case "Artifact": return .drawing
        default: break
        }
        // MCP tool names have the form mcp__server__tool. Match explicit
        // action names, never file extensions, arguments or chat text.
        guard let name, name.hasPrefix("mcp__") else { return .tool }
        let parts = name.components(separatedBy: "__")
        guard parts.count == 3, !parts[1].isEmpty else { return .tool }
        switch parts[2].lowercased() {
        case "read_file", "read_text_file", "read_multiple_files": return .reading
        case "search_web", "web_search", "web_fetch", "search_files": return .searching
        case "edit_file", "write_file": return .editing
        case "run_code", "execute_code", "run_python": return .executing
        case "create_artifact", "create_image", "generate_image", "draw_image", "create_diagram", "draw_diagram", "render_diagram": return .drawing
        default: return .tool
        }
    }

    private static func phase(for input: Payload) -> Phase? {
        switch input.hook_event_name {
        case "UserPromptSubmit", "PostToolUse": return .thinking
        case "PostToolUseFailure": return .toolError
        case "Stop": return input.agent_id == nil ? .stopped : nil
        case "StopFailure": return input.agent_id == nil ? .failed : nil
        case "PreToolUse": return toolPhase(input.tool_name)
        default: return nil
        }
    }

    /// Runs only in hook CLI mode. Silence and an exit code of zero leave Claude Code's decision unchanged.
    static func receive() {
        do {
            var data = Data()
            let input = FileHandle.standardInput
            while let chunk = try input.read(upToCount: 65536), !chunk.isEmpty {
                guard data.count + chunk.count <= 16 * 1024 * 1024 else { return }
                data.append(chunk)
            }
            let event = try JSONDecoder().decode(Payload.self, from: data)
            guard !event.session_id.isEmpty, event.session_id.utf8.count <= 512 else { return }
            try record(event)
        } catch {
            // Malformed or unsupported events must never affect the session that sent them.
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // Modern requests have a tool name, but unlike Pre/PostToolUse they do not
    // include the tool_use_id. Keep only possible call IDs, hashed at ingestion.
    private struct Wait: Codable, Equatable {
        let since: Date
        var possibleCalls: Set<String>
    }

    private struct ToolCalls: Codable, Equatable {
        var running: [String: Date] = [:]
        var waiting: [Wait] = []

        mutating func request(at now: Date, id: String?) {
            let candidates = id.map { Set([$0]) } ?? Set(running.keys)
            let matching = waiting.filter { $0.possibleCalls == candidates }.count
            guard matching < max(1, candidates.count) else { return }
            waiting.append(Wait(since: now, possibleCalls: candidates))
        }

        mutating func finish(_ id: String?) {
            if let id { running.removeValue(forKey: id) }
            guard let id else {
                // Legacy payloads can lack a call ID. A batch-end or session
                // status will settle ambiguous parallel calls.
                if running.count <= 1 && waiting.count == 1 { waiting.removeAll() }
                return
            }
            if let known = waiting.firstIndex(where: { $0.possibleCalls == [id] }) {
                waiting.remove(at: known)
            } else if let unknown = waiting.firstIndex(where: { $0.possibleCalls.isEmpty }) {
                waiting.remove(at: unknown)
            }
            for i in waiting.indices { waiting[i].possibleCalls.remove(id) }
            // With two identical tool names, the first result might have been
            // the sibling that never asked. Retain all still-possible waits.
            let remaining = Set(waiting.flatMap(\.possibleCalls)).count
            let excess = waiting.filter { !$0.possibleCalls.isEmpty }.count - remaining
            if excess > 0 { waiting.removeFirst(excess) }
        }
    }

    /// Session -> actor -> tool. The session is the filename, and opaque IDs
    /// and tool names are all hashed. No tool input is decoded.
    private typealias ApprovalRoster = [String: [String: ToolCalls]]
    private static let mainActorKey = "main"
    private static let unknownToolKey = "unknown"
    // A killed/older client may provide neither a final hook nor agent status.
    private static let orphanLifetime: TimeInterval = 24 * 60 * 60

    private static func readApprovals(_ url: URL) -> ApprovalRoster {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode(ApprovalRoster.self, from: data)) ?? [:]
    }

    private static func saveApprovals(_ roster: ApprovalRoster, to url: URL) throws {
        if roster.isEmpty { try? FileManager.default.removeItem(at: url) }
        else {
            try ClaudeSettings.makeDirectory(approvalDirectory)
            try JSONEncoder().encode(roster).write(to: url, options: .atomic)
        }
    }

    private static func updateApprovals(_ event: Payload, at url: URL, now: Date) throws {
        let name = event.hook_event_name
        let actor = event.agent_id.map(digest) ?? mainActorKey
        let tool = event.tool_name.map(digest) ?? unknownToolKey
        let id = event.tool_use_id.map(digest)
        let before = readApprovals(url)
        var roster = before
        switch name {
        case "Stop", "StopFailure":
            roster.removeValue(forKey: actor)
            if event.agent_id == nil, let tasks = event.background_tasks,
               !tasks.contains(where: { $0.type == nil || $0.type == "subagent" || $0.type == "teammate" }) {
                roster.removeAll()
            }
        case "SubagentStop", "PostToolBatch", "UserPromptSubmit":
            roster.removeValue(forKey: actor)
        case "Notification":
            // A delayed notification for an already observed permission dialog
            // is the same wait. Also covers sandbox prompts without a request hook.
            guard event.notification_type == "permission_prompt",
                  !before.values.contains(where: { $0.values.contains(where: { !$0.waiting.isEmpty }) }) else { return }
            if before[actor]?[digest("AskUserQuestion")]?.running.isEmpty == false { return }
            roster[actor, default: [:]][unknownToolKey, default: ToolCalls()].request(at: now, id: nil)
        case "PreToolUse":
            guard let id else { return }
            roster[actor, default: [:]][tool, default: ToolCalls()].running[id] = now
        case "PermissionRequest":
            // This built-in can use the permission host to collect an answer
            // to a question. A separate named tool approval remains observable.
            if event.tool_name == "AskUserQuestion" {
                if roster[actor]?[tool]?.running.isEmpty != false {
                    roster[actor, default: [:]][tool, default: ToolCalls()].running["question"] = now
                }
            } else {
                roster[actor, default: [:]][tool, default: ToolCalls()].request(at: now, id: id)
            }
        case "PostToolUse", "PostToolUseFailure":
            if var group = roster[actor]?[tool] {
                group.finish(id)
                if event.tool_name == "AskUserQuestion" { group.running.removeValue(forKey: "question") }
                roster[actor]?[tool] = group.running.isEmpty && group.waiting.isEmpty ? nil : group
                if roster[actor]?.isEmpty == true { roster.removeValue(forKey: actor) }
            }
        default: return
        }
        guard roster != before else { return }
        try saveApprovals(roster, to: url)
    }

    /// A live status describes the whole main session. A delayed response must
    /// never acknowledge a newer request, a different session, or a subagent.
    static func resolveApprovals(through observed: [String: Date]) {
        guard !observed.isEmpty else { return }
        try? withSessionLock {
            for (session, cutoff) in observed {
                let file = approvalDirectory.appendingPathComponent(session + ".json")
                guard session.utf8.count == 64, isRecordURL(file) else { continue }
                var roster = readApprovals(file)
                if var groups = roster[mainActorKey] {
                    for key in Array(groups.keys) {
                        groups[key]?.waiting.removeAll { $0.since <= cutoff }
                        if groups[key]?.running.isEmpty == true && groups[key]?.waiting.isEmpty == true {
                            groups.removeValue(forKey: key)
                        }
                    }
                    roster[mainActorKey] = groups.isEmpty ? nil : groups
                    try saveApprovals(roster, to: file)
                }
                let legacy = eventDirectory.appendingPathComponent(session + ".json")
                if let data = try? Data(contentsOf: legacy), let record = try? JSONDecoder().decode(Record.self, from: data),
                   record.phase == .waiting, record.date <= cutoff {
                    try JSONEncoder().encode(Record(phase: .thinking, date: Date())).write(to: legacy, options: .atomic)
                }
            }
        }
    }

    /// Concurrent command hooks are separate processes. Lock the existing session
    /// directory for the small read/modify/write so simultaneous agents never erase
    /// one another. Collectors cannot recreate the directory after disconnection.
    private static func withSessionLock(_ operation: () throws -> Void) rethrows {
        let fd = Darwin.open(eventDirectory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        try operation()
    }

    private static func record(_ event: Payload) throws {
        try withSessionLock { try recordLocked(event) }
    }

    private static func recordLocked(_ event: Payload) throws {
        let sessionFile = digest(event.session_id) + ".json"
        let activityURL = eventDirectory.appendingPathComponent(sessionFile)
        let agentsURL = agentDirectory.appendingPathComponent(sessionFile)
        let approvalsURL = approvalDirectory.appendingPathComponent(sessionFile)
        let name = event.hook_event_name
        if name == "SessionEnd" && event.agent_id == nil {
            try? FileManager.default.removeItem(at: agentsURL)
            try? FileManager.default.removeItem(at: activityURL)
            try? FileManager.default.removeItem(at: approvalsURL)
            return
        }
        let now = Date()
        try updateApprovals(event, at: approvalsURL, now: now)
        if let id = event.agent_id, !id.isEmpty, id.utf8.count <= 512,
           try recordAgent(event: name, id: id, rosterURL: agentsURL, now: now) { return }
        if event.agent_id == nil && (name == "Stop" || name == "StopFailure"),
           let tasks = event.background_tasks,
           !tasks.contains(where: { $0.type == nil || $0.type == "subagent" || $0.type == "teammate" }) {
            // Main turns may stop while detached agents continue. Clear this
            // session only when Claude explicitly reports no agents in flight.
            try? FileManager.default.removeItem(at: agentsURL)
        }
        guard let phase = phase(for: event) else { return }
        var record = Record(phase: phase, date: now)
        if name == "PostToolUse", let tool = event.tool_name,
           let data = try? Data(contentsOf: activityURL),
           let previous = try? JSONDecoder().decode(Record.self, from: data),
           previous.phase == toolPhase(tool), previous.date <= now,
           now.timeIntervalSince(previous.date) < 1.5 {
            record.recentTool = previous.phase
            record.visibleUntil = previous.date.addingTimeInterval(1.5)
        }
        try JSONEncoder().encode(record).write(to: activityURL, options: .atomic)
    }

    /// Returns true for lifecycle events and known subagent activity. Keeping that
    /// separate from the main session restores the parent's own pose on completion.
    private static func recordAgent(event: String, id: String, rosterURL: URL, now: Date) throws -> Bool {
        let key = digest(id)
        var roster = try readRoster(at: rosterURL)
        switch event {
        case "SubagentStart":
            roster[key] = now
        case "SubagentStop":
            guard roster.removeValue(forKey: key) != nil else { return true }
        default:
            // A tool hook also carries agent_id for some teammates. Only an
            // observed start can create an entry. Tool hooks renew known agents.
            guard roster[key] != nil else { return false }
            roster[key] = now
        }
        if roster.isEmpty { try FileManager.default.removeItem(at: rosterURL) }
        else { try JSONEncoder().encode(roster).write(to: rosterURL, options: .atomic) }
        return true
    }

    private static func readRoster(at url: URL) throws -> [String: Date] {
        do { return try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: url)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return [:] }
    }

    private static func activeAgents(at now: Date) -> (count: Int, latest: Date) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: agentDirectory, includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles) else { return (0, .distantPast) }
        var count = 0
        var latest = Date.distantPast
        for file in files where isRecordURL(file) {
            guard let roster = try? readRoster(at: file) else { continue }
            for seen in roster.values {
                let age = now.timeIntervalSince(seen)
                if age >= -2 && age <= agentLifetime {
                    count += 1
                    latest = max(latest, seen)
                }
            }
        }
        return (count, latest)
    }

    private static func isRecordURL(_ url: URL) -> Bool {
        guard url.pathExtension == "json" else { return false }
        let name = url.deletingPathExtension().lastPathComponent
        return name.utf8.count == 64 && name.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func poll() -> Snapshot? {
        let now = Date()
        let agents = activeAgents(at: now)
        var count = 0
        var pending: [String: Date] = [:]
        var newestWait = Date.distantPast
        let approvalFiles = (try? FileManager.default.contentsOfDirectory(at: approvalDirectory, includingPropertiesForKeys: nil,
                                                                         options: .skipsHiddenFiles)) ?? []
        for file in approvalFiles where isRecordURL(file) {
            let session = file.deletingPathExtension().lastPathComponent
            for (actor, groups) in readApprovals(file) {
                for group in groups.values {
                    for wait in group.waiting {
                        let age = now.timeIntervalSince(wait.since)
                        guard age >= -2, age < orphanLifetime else { continue }
                        count += 1
                        newestWait = max(newestWait, wait.since)
                        if actor == mainActorKey { pending[session] = max(pending[session] ?? .distantPast, wait.since) }
                    }
                }
            }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: eventDirectory, includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles) else { return nil }
        var latestActive: Record?
        var latestFinished: Record?
        for file in files where isRecordURL(file) {
            guard let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data) else { continue }
            let age = now.timeIntervalSince(record.date)
            // Inactive sessions can vanish on crashes; let those signals expire.
            guard age >= -2, age <= record.phase.lifetime else { continue }
            if record.phase == .waiting {
                // A helper from a previous installation still writes one
                // waiting phase per session until its in-place upgrade.
                let session = file.deletingPathExtension().lastPathComponent
                if pending[session] == nil {
                    pending[session] = record.date
                    newestWait = max(newestWait, record.date)
                    count += 1
                }
                continue
            }
            if record.phase.isActive {
                if record.date > (latestActive?.date ?? .distantPast) { latestActive = record }
            } else if record.date > (latestFinished?.date ?? .distantPast) {
                latestFinished = record
            }
        }
        if agents.count > 0 {
            let label = agents.count == 1 ? "Jongliert mit einem Agenten" : "Jongliert mit \(agents.count) Agenten"
            return (.juggling, label, agents.latest, agentLifetime, true, agents.count, count, pending)
        }
        guard let record = latestActive ?? latestFinished else {
            return count > 0 ? (.idle, "Startklar", newestWait, orphanLifetime, false, 0, count, pending) : nil
        }
        let visiblePhase = (record.visibleUntil ?? .distantPast) > now ? record.recentTool ?? record.phase : record.phase
        let (pose, label) = visiblePhase.presentation
        return (pose, label, record.date, record.phase.lifetime, record.phase.isActive, 0, count, pending)
    }
}
