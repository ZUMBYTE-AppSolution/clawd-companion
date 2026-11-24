"""Claude Code hooks run without Qt; only compact activity summaries reach the desktop."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import sys
import time
import uuid

from desktop_core import atomic_json, config_dir

HOOKS = ("UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","PostToolUseFailure","Stop",
         "StopFailure","SessionEnd","SubagentStart","SubagentStop","Notification")
TOOL_POSES = {"read":"reading","grep":"researching","glob":"researching","webfetch":"researching",
              "websearch":"researching","bash":"executing","powershell":"executing","write":"typing",
              "edit":"typing","notebookedit":"drawing","todowrite":"planning","enterplanmode":"planning",
              "exitplanmode":"planning"}


def helper(flag):
    args = [Path(sys.executable).resolve().as_posix()]
    if not getattr(sys, "frozen", False):
        args.append(str(Path(__file__).with_name("companion.py").resolve().as_posix()))
    if sys.platform == "win32":
        return " ".join('"' + arg + '"' for arg in args) + " " + flag
    return shlex.join(args + [flag])


def settings_path():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "settings.json"


def configure(feature, enable, path=None):
    path = path or settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError("Die Claude-Einstellungen sind keine reguläre Datei.")
    lock = path.with_suffix(".clawd-lock")
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    try:
        old = path.read_bytes() if path.exists() else None
        data = json.loads(old) if old is not None else {}
        if not isinstance(data, dict):
            raise ValueError("Die Claude-Einstellungen enthalten kein gültiges JSON-Objekt. Die Datei wurde unverändert gelassen.")
        if feature == "hooks":
            if enable and data.get("disableAllHooks") is True:
                raise ValueError("Claude Code hat alle Hooks deaktiviert. Aktiviere Hooks in Claude Code, bevor du Clawd verbindest.")
            hooks = data.setdefault("hooks", {})
            if not isinstance(hooks, dict):
                raise ValueError("Das bestehende hooks-Feld in den Claude-Einstellungen ist kein Objekt.")
            cmd = helper("--clawd-hook")
            for name in HOOKS:
                groups = hooks.get(name, [])
                if not isinstance(groups, list):
                    raise ValueError("Die vorhandene Hook-Konfiguration für {0} hat ein unbekanntes Format.")
                own = {"hooks":[{"type":"command","command":cmd}]}
                updated = [group for group in groups if group != own]
                if enable:
                    updated.append(own)
                if updated:
                    hooks[name] = updated
                else:
                    hooks.pop(name,None)
            if not hooks:
                data.pop("hooks",None)
        elif feature == "quota":
            cmd = helper("--clawd-quota")
            current = data.get("statusLine")
            prefix, suffix = helper("--clawd-quota-pipe") + " | ( ", " )"
            if current is None and enable:
                data["statusLine"] = {"type":"command","command":cmd}
            elif current is not None:
                if not isinstance(current,dict) or current.get("type")!="command" or not isinstance(current.get("command"),str) or not current["command"]:
                    if enable:
                        raise ValueError("Die bestehende Statuszeile verwendet ein unbekanntes Format. Ihre Konfiguration bleibt erhalten.")
                else:
                    original=current["command"]
                    ours=original.startswith(prefix) and original.endswith(suffix)
                    if enable and original!=cmd and not ours:
                        current["command"]=prefix+original+suffix
                    elif not enable and ours:
                        current["command"]=original[len(prefix):-len(suffix)]
                    elif not enable and original==cmd:
                        data.pop("statusLine")
        else:
            raise ValueError(feature)
        if (path.read_bytes() if path.exists() else None) != old:
            raise ValueError("Claude hat seine Einstellungen gleichzeitig geändert. Bitte versuche es noch einmal.")
        atomic_json(path, data)
    finally:
        lock.unlink(missing_ok=True)


def installed(feature):
    try:
        data = json.loads(settings_path().read_bytes())
        if feature == "quota":
            cmd=data.get("statusLine", {}).get("command","")
            return cmd==helper("--clawd-quota") or (cmd.startswith(helper("--clawd-quota-pipe")+" | ( ") and cmd.endswith(" )"))
        own = {"hooks":[{"type":"command","command":helper("--clawd-hook")}]}
        return own in data["hooks"]["PreToolUse"]
    except (OSError, KeyError, TypeError, AttributeError, ValueError):
        return False


def hook_event(raw):
    name = raw.get("hook_event_name")
    if name not in HOOKS:
        return None
    def key(value):
        return hashlib.sha256(str(value)[:1024].encode()).hexdigest()[:32]
    session = key(raw.get("session_id",""))
    event = {"type":"code","session":session,"action":name}
    if name.startswith("Subagent"):
        agent = raw.get("agent_id")
        if not isinstance(agent,str) or not agent:
            return None
        event["agent"] = key(agent)
    elif name in ("PreToolUse","PostToolUse"):
        event["pose"] = TOOL_POSES.get(str(raw.get("tool_name","")).lower(),"typing")
    elif name == "Notification":
        event["waiting"] = raw.get("notification_type") == "permission_prompt"
    return event


def status_quota(raw, now):
    limits = raw.get("rate_limits")
    if not isinstance(limits,dict):
        return None
    windows = []
    def utc(seconds):
        return datetime.datetime.fromtimestamp(seconds,datetime.timezone.utc).isoformat()
    for name,kind in (("five_hour","session"),("seven_day","weekly")):
        win = limits.get(name)
        if not isinstance(win,dict):
            continue
        used, reset = win.get("used_percentage"), win.get("resets_at")
        if type(used) not in (int,float) or type(reset) not in (int,float) or not 0 <= used <= 100 or not now < reset < 32503680000:
            continue
        windows.append({"kind":kind, "remainingPercent":int(100-used), "resetAt":utc(reset)})
    if windows:
        return {"type":"usage","source":"Claude Code","observedAt":utc(now),"windows":windows}


def _stream(which):
    stream=getattr(sys,which)
    if stream is not None:
        return stream.buffer
    if sys.platform=="win32":
        import ctypes
        from ctypes import wintypes
        import msvcrt
        # PyInstaller's windowed entry point omits Python stdio even if Claude supplied redirected pipes.
        fn=ctypes.WinDLL("kernel32",use_last_error=True).GetStdHandle
        fn.argtypes,fn.restype=[wintypes.DWORD],wintypes.HANDLE
        read=which=="stdin"
        handle=fn(-10 if read else -11)
        if handle and handle!=ctypes.c_void_p(-1).value:
            fd=msvcrt.open_osfhandle(handle, (os.O_RDONLY if read else os.O_WRONLY) | os.O_BINARY)
            return os.fdopen(fd,"rb" if read else "wb",closefd=False)
    return None


def collect(flag):
    try:
        source=_stream("stdin")
        if source is None:
            return
        output=_stream("stdout")
        if flag=="--clawd-quota-pipe":
            chunks=bytearray()
            oversize=False
            while block:=source.read(65536):
                if output:
                    output.write(block)
                if len(chunks)+len(block)<=2_097_152 and not oversize:
                    chunks.extend(block)
                else:
                    oversize=True
            if output:
                output.flush()
            if oversize:
                return
            body=bytes(chunks)
        else:
            body=source.read(2_097_153)
        if len(body)>2_097_152:
            return
        raw = json.loads(body)
        if not isinstance(raw,dict):
            return
        now = time.time()
        summary = status_quota(raw, now) if flag in ("--clawd-quota","--clawd-quota-pipe") else hook_event(raw)
        if flag=="--clawd-quota" and output:
            message="   ".join(f"{w['remainingPercent']}%" for w in (summary or {}).get("windows", [])) or "Claw’d"
            output.write((message+"\n").encode("utf-8"))
            output.flush()
        if not summary or not installed("hooks" if flag=="--clawd-hook" else "quota"):
            return
        inbox = config_dir() / "events"
        inbox.mkdir(parents=True, exist_ok=True)
        # A closed GUI leaves a bounded journal even during long Claude sessions.
        files = sorted(inbox.glob("*.json"))
        for file in files[:-120]:
            file.unlink(missing_ok=True)
        atomic_json(inbox / f"{time.time_ns():020d}-{uuid.uuid4().hex}.json", summary)
    except (OSError,ValueError,RecursionError):
        pass


def drain():
    inbox = config_dir() / "events"
    for path in sorted(inbox.glob("*.json"))[:128]:
        try:
            if time.time() - path.stat().st_mtime < 1800 and path.stat().st_size < 8192:
                data = json.loads(path.read_bytes())
                if isinstance(data,dict):
                    yield data
        except (OSError,ValueError):
            pass
        finally:
            path.unlink(missing_ok=True)
