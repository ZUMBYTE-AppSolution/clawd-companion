#!/usr/bin/env python3
"""Exercise the macOS Claude Code integration in an isolated temporary home."""
import json
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources/ClawdCompanion"
HARNESS = """
import Foundation
let sandbox = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!
let canonicalHome = URL(fileURLWithPath: sandbox).resolvingSymlinksInPath().standardizedFileURL.path
for path in [ClaudeSettings.helperURL, ClaudeSettings.settingsURL] {
    var ancestor = path
    while !FileManager.default.fileExists(atPath: ancestor.path) {
        ancestor = ancestor.deletingLastPathComponent()
    }
    let existing = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
    guard existing == canonicalHome || existing.hasPrefix(canonicalHome + "/") else {
        FileHandle.standardError.write(Data("Refusing to run outside temporary home".utf8))
        exit(2)
    }
}
do {
    switch CommandLine.arguments[1] {
    case "--clawd-code-hook": ClaudeHooks.receive()
    case "install": try ClaudeHooks.install()
    case "uninstall": try ClaudeHooks.uninstall()
    case "installed": print(ClaudeHooks.isInstalled ? "yes" : "no")
    case "needs-upgrade": print(ClaudeHooks.needsUpgrade ? "yes" : "no")
    case "agents": print(ClaudeHooks.poll()?.agentCount ?? 0)
    case "approvals": print(ClaudeHooks.poll()?.approvalCount ?? 0)
    case "pending": print(ClaudeHooks.poll()?.pendingApprovals[CommandLine.arguments[2]]?.timeIntervalSince1970 ?? 0)
    case "resolve":
        ClaudeHooks.resolveApprovals(through: [CommandLine.arguments[2]: Date(timeIntervalSince1970: Double(CommandLine.arguments[3])!)])
    case "poll": print(ClaudeHooks.poll()?.pose.rawValue ?? "none")
    case "install-quota": try QuotaStatusLine().install()
    case "uninstall-quota": try QuotaStatusLine().uninstall()
    default: exit(2)
    }
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
"""


def run_tests(home):
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
               CLAUDE_CONFIG_DIR=str(home / "custom config"))
    config = home / "custom config/settings.json"
    config.parent.mkdir()
    foreign = {"matcher": "Read", "hooks": [{"type": "command", "command": "echo keep"}]}
    initial = {
        "permissions": {"allow": ["Read"]}, "hooks": {"PreToolUse": [foreign]},
        "statusLine": {"type": "command", "command": "cat >/dev/null && echo original"},
        "unrelated": ["α", 1, False],
    }
    config.write_text(json.dumps(initial))
    config.chmod(0o640)
    main = home / "main.swift"
    cli = home / "test-cli"
    main.write_text(HARNESS)
    subprocess.run(["/usr/bin/xcrun", "swiftc", "-module-cache-path", home / "cache",
                    SOURCES / "ClaudeSettings.swift", SOURCES / "ClaudeHooks.swift",
                    SOURCES / "QuotaStatusLine.swift", SOURCES / "Localization.swift", SOURCES / "MascotArt.swift",
                    main, "-o", cli], check=True)

    def invoke(*args, check=True):
        result = subprocess.run([cli, *args], text=True, env=env, capture_output=True)
        if check and result.returncode:
            raise AssertionError(f"{args}: {result.stderr}")
        return result

    def settings():
        return json.loads(config.read_text())

    invoke("install")
    assert stat.S_IMODE(config.stat().st_mode) == 0o640
    installed = settings()
    assert invoke("installed").stdout.strip() == "yes"
    assert installed["hooks"]["PreToolUse"][0] == foreign
    registered = installed["hooks"]["Stop"][0]["hooks"][0]["command"]

    def emit(session, event, tool=None, agent=None, background=None, call=None, notice=None):
        payload = json.dumps({"hook_event_name": event, "session_id": session, "tool_name": tool,
                              "agent_id": agent, "background_tasks": background,
                              "tool_use_id": call, "notification_type": notice,
                              "prompt": "private-sensitive", "cwd": "/private-sensitive",
                              "tool_input": {"command": "private-sensitive"}})
        run = subprocess.run(["/bin/sh", "-c", registered], env=env, input=payload, text=True,
                             capture_output=True, check=True)
        assert not run.stdout and not run.stderr

    emit("session1", "UserPromptSubmit")
    assert invoke("poll").stdout.strip() == "thinking"
    emit("session1", "PreToolUse", "Write")
    assert invoke("poll").stdout.strip() == "typing"
    approvals = lambda: int(invoke("approvals").stdout)
    emit("session1", "PermissionRequest", "Write")
    assert approvals() == 1 and invoke("poll").stdout.strip() == "typing"
    emit("session2", "UserPromptSubmit")
    emit("session1", "Stop")
    assert approvals() == 0
    assert invoke("poll").stdout.strip() == "thinking"
    emit("session2", "SessionEnd")
    assert invoke("poll").stdout.strip() == "happy"
    sessions = list(home.glob("Library/Application Support/ClawdCompanion/Integration/Sessions/*.json"))
    assert len(sessions) == 1 and "session1" not in sessions[0].name
    assert set(json.loads(sessions[0].read_text())) == {"phase", "date"}
    assert "private-sensitive" not in sessions[0].read_text()

    # Only explicit action names choose a specialized prop, including MCP
    # actions where the server name happens to resemble a different activity.
    for tool, pose in {
        "EnterPlanMode": "planning", "ExitPlanMode": "planning", "TodoWrite": "planning",
        "TaskCreate": "planning", "TaskList": "planning", "Grep": "researching",
        "WebSearch": "researching", "WebFetch": "researching", "Read": "reading",
        "Edit": "typing", "NotebookEdit": "typing", "Bash": "executing",
        "PowerShell": "executing", "Artifact": "drawing",
        "mcp__studio__generate_image": "drawing", "mcp__imagegen__read_file": "reading",
        "mcp__search__delete_drawing": "typing",
    }.items():
        emit("props", "PreToolUse", tool)
        assert invoke("poll").stdout.strip() == pose, tool
    emit("props", "PreToolUse", "Read")
    emit("props", "PostToolUse", "Read")
    assert invoke("poll").stdout.strip() == "reading"
    props = sessions[0].parent / (hashlib.sha256(b"props").hexdigest() + ".json")
    saved = json.loads(props.read_text())
    saved["visibleUntil"] -= 60
    props.write_text(json.dumps(saved))
    assert invoke("poll").stdout.strip() == "thinking"
    emit("props", "PreToolUse", "Artifact")
    emit("props", "PostToolUse", "Artifact")
    emit("props", "Stop")
    assert invoke("poll").stdout.strip() == "happy"
    emit("props", "SessionEnd")
    # A v0.3 install already knows about agents but not prompt fallback and
    # parallel-tool batch boundaries. Install upgrades that helper in place.
    legacy_v3 = settings()
    assert legacy_v3["hooks"]["Notification"][0]["matcher"] == "permission_prompt"
    for event in ("Notification", "PostToolBatch"):
        del legacy_v3["hooks"][event]
    config.write_text(json.dumps(legacy_v3))
    assert invoke("needs-upgrade").stdout.strip() == "yes"
    invoke("install")
    assert settings() == installed

    # PermissionRequest has no call ID. A completed sibling of the same tool
    # must not dismiss the older prompt that remains outstanding.
    session_hash = hashlib.sha256(b"parallel").hexdigest()
    emit("parallel", "PreToolUse", "PrivateMCPTool", call="sensitive-call-a")
    emit("parallel", "PermissionRequest", "PrivateMCPTool")
    first = float(invoke("pending", session_hash).stdout)
    emit("parallel", "PreToolUse", "PrivateMCPTool", call="sensitive-call-b")
    emit("parallel", "PostToolUse", "PrivateMCPTool", call="sensitive-call-b")
    emit("parallel", "Notification", notice="permission_prompt")
    assert approvals() == 1
    emit("parallel", "PreToolUse", "Bash", call="sensitive-call-c")
    emit("parallel", "PermissionRequest", "Bash")
    emit("other-session", "PermissionRequest", "Write")
    emit("parallel", "SubagentStart", agent="private-worker")
    emit("parallel", "PermissionRequest", "Edit", agent="private-worker")
    assert approvals() == 4 and invoke("agents").stdout.strip() == "1"
    # +1 microsecond covers the Python text round trip of this timestamp.
    # Every later request, the other session, and the agent must survive.
    invoke("resolve", session_hash, str(first + 0.000001))
    assert approvals() == 3
    newest = float(invoke("pending", session_hash).stdout)
    invoke("resolve", session_hash, str(newest + 1))
    assert approvals() == 2
    emit("parallel", "PostToolBatch")
    assert approvals() == 2
    emit("parallel", "SubagentStop", agent="private-worker")
    emit("other-session", "SessionEnd")
    assert approvals() == 0

    # Parallel calls of the same tool, both of which need a decision.
    for call in ["call-1", "call-2"]:
        emit("parallel", "PreToolUse", "Bash", call=call)
    for _ in range(2):
        emit("parallel", "PermissionRequest", "Bash")
    assert approvals() == 2
    emit("parallel", "PostToolUseFailure", "Bash", call="call-2")
    assert approvals() == 1
    emit("parallel", "PostToolUse", "Bash", call="call-1")
    assert approvals() == 0
    emit("parallel", "Notification", notice="idle_prompt")
    assert approvals() == 0
    emit("parallel", "Notification", notice="permission_prompt")
    assert approvals() == 1
    emit("parallel", "PostToolBatch")
    assert approvals() == 0
    # AskUserQuestion can reach an SDK permission host to collect a choice.
    # A distinct tool's genuine approval remains visible even with that form open.
    emit("parallel", "PermissionRequest", "AskUserQuestion")
    emit("parallel", "Notification", notice="permission_prompt")
    assert approvals() == 0
    emit("parallel", "PermissionRequest", "mcp__example__ask")
    assert approvals() == 1
    emit("parallel", "PostToolUse", "AskUserQuestion", call="choice")
    assert approvals() == 1
    emit("parallel", "PostToolBatch")
    emit("parallel", "PermissionRequest", "ExitPlanMode")
    assert approvals() == 1
    emit("parallel", "PostToolBatch")
    emit("parallel", "PermissionRequest", "PrivateMCPTool")
    for file in (sessions[0].parent / "Approvals").glob("*.json"):
        value = file.read_text()
        assert not any(raw in value for raw in ["PrivateMCPTool", "sensitive-call", "private-sensitive", "private-worker"])
    emit("parallel", "SessionEnd")

    # Upgrade a previously opted-in v0.1 installation in place, including the copied helper.
    legacy = settings()
    for event in ("SubagentStart", "SubagentStop"):
        assert event in legacy["hooks"]
        del legacy["hooks"][event]
    config.write_text(json.dumps(legacy))
    helper = home / "Library/Application Support/ClawdCompanion/Integration/ClawdCLI"
    helper.write_text("#!/bin/sh\nexit 0\n")
    assert invoke("installed").stdout.strip() == "yes"
    assert invoke("needs-upgrade").stdout.strip() == "yes"
    invoke("install")
    assert helper.read_bytes() == cli.read_bytes()
    assert invoke("needs-upgrade").stdout.strip() == "no"
    # Older builds could subscribe to all current events without classifying
    # planning or artifact tools. Offer the existing in-place update once.
    (sessions[0].parent / ".activity-props-v1").unlink()
    helper.write_text("#!/bin/sh\nexit 0\n")
    assert invoke("needs-upgrade").stdout.strip() == "yes"
    invoke("install")
    assert helper.read_bytes() == cli.read_bytes()
    assert invoke("needs-upgrade").stdout.strip() == "no"

    agents = lambda: int(invoke("agents").stdout)
    # Concurrent starts, repeated events and same id in distinct sessions.
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda i: emit("team", "SubagentStart", agent=f"worker{i}"), range(12)))
    emit("team", "SubagentStart", agent="worker1")
    emit("elsewhere", "SubagentStart", agent="worker1")
    emit("team", "SubagentStop", agent="never-observed")
    emit("team", "PreToolUse", tool="Read", agent="not-observed")
    assert agents() == 13 and invoke("poll").stdout.strip() == "juggling"
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda i: emit("team", "SubagentStop", agent=f"worker{i}"), range(11)))
    emit("team", "SubagentStop", agent="worker10")
    assert agents() == 2
    emit("team", "Stop", background=[{"id": "task-id", "type": "subagent", "status": "running"}])
    assert agents() == 2
    emit("team", "Stop", background=[{"type": "shell"}])
    assert agents() == 1
    emit("elsewhere", "SessionEnd")
    assert agents() == 0

    # A known agent's tool hooks renew its last seen time. Expired values stop reporting.
    emit("expiry", "UserPromptSubmit")
    emit("expiry", "SubagentStart", agent="private-worker-name")
    roster_dir = sessions[0].parent / "Agents"
    roster_file, = roster_dir.glob("*.json")
    assert "expiry" not in roster_file.name and "private" not in roster_file.read_text()
    roster = json.loads(roster_file.read_text())
    for key in roster:
        assert len(key) == 64
        roster[key] -= 7200
    roster_file.write_text(json.dumps(roster))
    assert agents() == 0
    emit("expiry", "PreToolUse", "Write", agent="private-worker-name")
    assert agents() == 1
    emit("expiry", "SubagentStop", agent="private-worker-name")
    assert agents() == 0 and invoke("poll").stdout.strip() == "thinking"
    emit("expiry", "SessionEnd")
    emit("finishing", "SubagentStart", agent="a")
    emit("finishing", "StopFailure", background=[])
    assert agents() == 0

    invoke("install")
    assert installed == settings()
    invoke("install-quota")
    assert settings()["hooks"] == installed["hooks"]
    quota = settings()["statusLine"]
    invoke("uninstall")
    assert invoke("installed").stdout.strip() == "no" and settings()["statusLine"] == quota
    invoke("uninstall-quota")
    assert settings() == initial
    emit("old-running-session", "SubagentStart", agent="a")
    emit("old-running-session", "UserPromptSubmit")
    assert invoke("poll").stdout.strip() == "none"
    config.write_text('{"invalid')
    assert invoke("install", check=False).returncode == 1 and config.read_text() == '{"invalid'
    config.unlink()
    invoke("install")
    assert stat.S_IMODE(config.stat().st_mode) == 0o600
    invoke("uninstall")
    assert settings() == {}


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="clawd's integration test ") as directory:
        run_tests(Path(directory).resolve())
    print("PASS: Claude Code hooks, permission lifecycle, parallel calls and sessions, subagents, migration, privacy, expiry and quota coexistence.")
