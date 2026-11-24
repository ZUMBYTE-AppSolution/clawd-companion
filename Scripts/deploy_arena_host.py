"""Private, stdlib-only host implementation for deploy-arena.sh."""
import base64
import datetime
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path, PurePosixPath

DOMAIN = "zumbyte.de"
PREFIX = "/api/clawd/v1/"
SNIPPET = "/etc/clawd-arena/location.nginx"
INCLUDE = f"include {SNIPPET};"
REQUIRED = {"VERSION", "Desktop/arcade.py", "Server/app.py", "Server/__init__.py", "Server/game.py",
            "Server/schema.sql", "Server/wsgi.py", "Server/deploy/location.nginx", "Server/deploy/clawd-arena.service"}


def archive_files(archive, expected=""):
    if archive.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("Archive too large.")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if expected and digest != expected.lower():
        raise ValueError("Archive SHA-256 does not match.")
    files, prefixes, total = {}, set(), 0
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts:
                raise ValueError("Unsafe archive path.")
            prefixes.add(path.parts[0])
            if member.isdir():
                continue
            name = "/".join(path.parts[1:])
            total += member.size
            if (not member.isfile() or not name or name in files or len(files) >= 100
                    or total > 12 * 1024 * 1024 or member.size > 2 * 1024 * 1024):
                raise ValueError("Unsupported archive member.")
            if name not in REQUIRED and name != "Server/README.md":
                raise ValueError("Unexpected archive member: " + name)
            files[name] = tar.extractfile(member).read()
    if not REQUIRED.issubset(files):
        raise ValueError("Not a complete Clawd Arena API archive.")
    version = files["VERSION"].decode("ascii").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version) or prefixes != {"Clawd-Arena-API-" + version}:
        raise ValueError("Invalid archive release version.")
    return version, digest, files


# Preserve all original source bytes while recognizing nginx braces, quotes,
# comments and escaped separators. Directives inside a nested location do not
# qualify the outer server as a matching TLS virtual host.
TOKEN = re.compile(r'''\s+|\#[^\n]*|[{};]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?:\\.|\$\{[^}]*\}|[^\s{};#'"\\])+''')


def virtual_hosts(source):
    stack, words, hosts = [], [], []
    position = 0
    for m in TOKEN.finditer(source):
        if m.start() != position:
            raise ValueError("Unsupported nginx token. Select a simpler --nginx-site file.")
        position = m.end()
        word = m[0]
        if word.isspace() or word.startswith("#"):
            continue
        if word == "{":
            is_server = words == ["server"]
            record = {"insert": m.end(), "ssl": False, "domain": False, "managed": False, "conflict": False} if is_server else None
            if stack and stack[-1] is not None and words and words[0] == "location" and any(re.search(r"/api/clawd/v1(?:/|\$|$)", w) for w in words[1:]):
                stack[-1]["conflict"] = True
            stack.append(record)
            words = []
        elif word == "}":
            if not stack:
                raise ValueError("Unbalanced nginx fragment.")
            record = stack.pop()
            if record is not None and record["domain"] and record["ssl"]:
                hosts.append(record)
            words = []
        elif word == ";":
            if stack and stack[-1] is not None and words:
                rec = stack[-1]
                if words[0] == "server_name":
                    rec["domain"] |= DOMAIN in [v.lower().rstrip(".") for v in words[1:]]
                if words[0] == "listen" and len(words) > 1:
                    rec["ssl"] |= "ssl" in words[2:] and (words[1] == "443" or words[1].endswith(":443"))
                if words == ["include", SNIPPET]:
                    rec["managed"] = True
            words = []
        else:
            words.append(word[1:-1] if word.startswith(('"', "'")) else word)
    if position != len(source) or stack:
        raise ValueError("Unsupported nginx fragment.")
    return hosts


def choose_site(paths, explicit=""):
    active = {Path(p).resolve() for p in paths}
    if explicit:
        requested = Path(explicit).resolve()
        if requested not in active:
            raise ValueError("--nginx-site must be an active file reported by nginx -T.")
        active = {requested}
    candidates = []
    for path in sorted(active):
        source = path.read_bytes().decode("utf-8", errors="surrogateescape")
        if DOMAIN not in source.lower() or "server" not in source:
            continue
        for host in virtual_hosts(source):
            candidates.append((path, source, host))
    if len(candidates) != 1:
        raise ValueError("A single TLS server_name zumbyte.de on port 443 is required; select its file with --nginx-site.")
    path, source, host = candidates[0]
    original = source.encode("utf-8", errors="surrogateescape")
    if host["conflict"]:
        raise ValueError("An existing /api/clawd/v1 location needs operator review; no route was replaced.")
    if not host["managed"]:
        at = host["insert"]
        source = source[:at] + "\n    " + INCLUDE + source[at:]
    return path, original, source.encode("utf-8", errors="surrogateescape")


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=60)


def atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".clawd-deploy-", delete=False) as stream:
        tmp = Path(stream.name)
        stream.write(data)
    try:
        if path.exists():
            info = path.stat()
            os.chown(tmp, info.st_uid, info.st_gid)
            shutil.copystat(path, tmp)
        else:
            tmp.chmod(mode)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def secret(path, db):
    if path.is_symlink():
        raise ValueError("Refusing a symlink for the environment secret.")
    if path.exists():
        if not path.is_file() or path.stat().st_mode & 0o077:
            raise ValueError("The existing environment file must be private (0600 or 0400).")
        lines = [x.partition("=")[2].strip().strip("'\x22") for x in path.read_text().splitlines() if x.startswith("CLAWD_SECRET=")]
        if len(lines) != 1 or len(base64.b64decode(lines[0], validate=True)) < 32:
            raise ValueError("Existing CLAWD_SECRET is invalid. Restore its original value.")
        return
    if db.exists():
        raise ValueError("Existing database without its secret: restore the matching environment file first.")
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("CLAWD_SECRET=" + base64.b64encode(secrets.token_bytes(32)).decode("ascii") + "\n")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def smoke(url, local=False):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    if local:
        request.add_header("X-Forwarded-Proto", "https")
    for attempt in range(6):
        try:
            with opener.open(request, timeout=5):
                pass
        except urllib.error.HTTPError as response:
            with response:
                if response.code == 401 and response.headers.get_content_type() == "application/json":
                    try:
                        if json.loads(response.read(1024)) == {"error": "unauthorized"}:
                            return
                    except ValueError:
                        pass
        except (OSError, urllib.error.URLError):
            pass
        if attempt < 5:
            time.sleep(1)
    raise RuntimeError("API smoke failed (expected HTTP 401 and JSON unauthorized): " + url)


def deploy(stage):
    if os.geteuid() != 0 or sys.platform != "linux":
        raise RuntimeError("The deployment needs root on a systemd/nginx Linux host.")
    import sqlite3
    if sys.version_info < (3, 11) or sqlite3.sqlite_version_info < (3, 35) or not Path("/usr/bin/gunicorn").is_file():
        raise RuntimeError("Install Python 3.11+, SQLite 3.35+ and /usr/bin/gunicorn first.")
    os.umask(0o022)  # Service code is readable by DynamicUser; secret files explicitly use 0600.
    options = json.loads((stage / "options.json").read_text())
    version, digest, files = archive_files(stage / "release.tar.gz", options["sha256"])
    lock = Path("/run/lock/clawd-arena-deploy.lock")
    with lock.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        apply_release(version, digest, files, options["site"])


def apply_release(version, digest, files, explicit, *, root=Path("/")):
    run("systemctl", "is-active", "--quiet", "nginx")
    config = run("nginx", "-T").stdout
    paths = re.findall(r"^# configuration file (.+):\s*$", config, re.M)
    site, original, revised = choose_site(paths, explicit)
    release_base = root / "opt/clawd-arena/releases"
    release_dir = release_base / digest
    release_base.mkdir(parents=True, exist_ok=True, mode=0o755)
    if release_dir.exists():
        if not all((release_dir / name).read_bytes() == data for name, data in files.items()):
            raise RuntimeError("Existing immutable release directory differs from its archive.")
    else:
        build = Path(tempfile.mkdtemp(dir=release_base))
        try:
            for name, data in files.items():
                target = build / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod(0o644)
            # The unprivileged systemd DynamicUser must be able to traverse the release.
            for directory in [build, *(p for p in build.rglob("*") if p.is_dir())]:
                directory.chmod(0o755)
            build.rename(release_dir)
        finally:
            if build.exists():
                shutil.rmtree(build)

    env = root / "etc/clawd-arena.env"
    db = root / "var/lib/clawd-arena/arena.sqlite3"
    unit = root / "etc/systemd/system/clawd-arena.service"
    snippet = root / SNIPPET.lstrip("/")
    raw_unit = files["Server/deploy/clawd-arena.service"]
    original_wd = b"WorkingDirectory=/opt/clawd-companion\n"
    if raw_unit.count(original_wd) != 1:
        raise ValueError("Unexpected WorkingDirectory in packaged unit.")
    if unit.is_symlink() or snippet.is_symlink():
        raise ValueError("Review existing symlink at the managed unit or snippet path.")
    existing_unit = unit.read_bytes() if unit.exists() else b""
    if existing_unit and (b"EnvironmentFile=/etc/clawd-arena.env" not in existing_unit or
                          b"CLAWD_DATABASE=/var/lib/clawd-arena/arena.sqlite3" not in existing_unit):
        raise ValueError("Unrecognized existing service storage configuration. Review before migration.")
    overrides = run("systemctl", "show", "--property=DropInPaths", "--value", "clawd-arena", check=False).stdout.strip()
    if overrides:
        raise ValueError("The existing service has systemd overrides. Review its storage and command before migrating.")
    fragment = run("systemctl", "show", "--property=FragmentPath", "--value", "clawd-arena", check=False).stdout.strip()
    if fragment and Path(fragment).resolve() != unit.resolve():
        raise ValueError("The existing service is managed by another unit file. Review before migrating.")
    if site.read_bytes() != original:
        raise RuntimeError("TLS virtual host changed during discovery; retry deployment.")
    secret(env, db)
    planned = {unit: raw_unit.replace(original_wd, f"WorkingDirectory={release_dir}\n".encode()),
               snippet: files["Server/deploy/location.nginx"], site: revised}
    before = {path: path.read_bytes() if path.exists() else None for path in planned}
    if before[site] != original:
        raise RuntimeError("TLS virtual host changed during preflight; retry deployment.")
    changed = [path for path in planned if before[path] != planned[path]]
    old_active = run("systemctl", "is-active", "--quiet", "clawd-arena", check=False).returncode == 0
    old_enabled = run("systemctl", "is-enabled", "--quiet", "clawd-arena", check=False).returncode == 0
    backups = None
    if changed:
        backups = root / "var/backups/clawd-arena" / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(4))
        backups.mkdir(parents=True, mode=0o700)
        for index, path in enumerate(changed):
            if before[path] is not None:
                shutil.copy2(path, backups / f"{index}-{path.name}")
        (backups / "paths.json").write_text(json.dumps([str(p) for p in changed]) + "\n")
    written = []
    touched_service = reloaded = enabled_here = False
    try:
        for path in changed:
            actual = path.read_bytes() if path.exists() else None
            if actual != before[path]:
                raise RuntimeError("A configuration file changed during the deployment.")
            atomic(path, planned[path])
            written.append(path)
        run("nginx", "-t")
        if unit in changed or not old_active:
            touched_service = True
            run("systemctl", "daemon-reload")
            run("systemctl", "restart" if old_active else "start", "clawd-arena")
        smoke("http://127.0.0.1:9184/api/clawd/v1/me", local=True)
        if site in changed or snippet in changed:
            reloaded = True
            run("systemctl", "reload", "nginx")
        smoke("https://zumbyte.de/api/clawd/v1/me")
        if not old_enabled:
            enabled_here = True
            run("systemctl", "enable", "clawd-arena")
    except BaseException:
        for path in reversed(written):
            if not path.is_file() or path.read_bytes() != planned[path]:
                raise RuntimeError(f"Concurrent edit at {path}. Rollback needs the backups at {backups}.")
            if before[path] is None:
                path.unlink()
            else:
                atomic(path, before[path])
        if enabled_here:
            run("systemctl", "disable", "clawd-arena", check=False)
        if touched_service:
            if not old_active and run("systemctl", "is-active", "--quiet", "clawd-arena", check=False).returncode == 0:
                run("systemctl", "stop", "clawd-arena")
            run("systemctl", "daemon-reload")
            if old_active:
                run("systemctl", "restart", "clawd-arena")
        if reloaded:
            run("nginx", "-t")
            run("systemctl", "reload", "nginx")
        raise
    print(f"Clawd Arena {version} active; authenticated route returned the expected JSON 401.")
    if backups:
        print(f"Configuration backups: {backups}")


def main():
    if len(sys.argv) == 6 and sys.argv[1] == "--inspect":
        archive, checksum, site, dest = sys.argv[2:]
        if site and (not Path(site).is_absolute() or "\n" in site or "\r" in site):
            raise ValueError("--nginx-site needs an absolute remote path.")
        version, digest, _ = archive_files(Path(archive), checksum)
        Path(dest).write_text(json.dumps({"sha256":digest, "site":site}))
        print(f"API {version} · SHA-256 {digest}")
    elif len(sys.argv) == 3 and sys.argv[1] == "--apply":
        deploy(Path(sys.argv[2]))
    else:
        raise ValueError("Use Scripts/deploy-arena.sh.")

if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError, tarfile.TarError) as err:
        print(f"Deployment failed: {err}", file=sys.stderr)
        sys.exit(1)
