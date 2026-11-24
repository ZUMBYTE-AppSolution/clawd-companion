"""Release metadata and installation choices shared by the desktop UI and release build."""
from __future__ import annotations

import json
import platform
import re
import sys
from pathlib import Path
import urllib.request
from dataclasses import dataclass
from urllib.parse import urlsplit

REPOSITORY = "https://github.com/ZUMBYTE-AppSolution/clawd-companion"
MANIFEST_URL = REPOSITORY + "/releases/latest/download/clawd-update.json"
LIMIT = 768 * 1024
_VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", re.ASCII)


def version_key(value: str) -> tuple:
    match = _VERSION.fullmatch(value) if isinstance(value, str) and len(value) <= 100 else None
    if not match:
        raise ValueError("Invalid semantic version")
    pre = match[4].split(".") if match[4] else []
    if any(part.isdigit() and len(part) > 1 and part.startswith("0") for part in pre):
        raise ValueError("Invalid numeric prerelease")
    return (tuple(int(x) for x in match.groups()[:3]), not pre,
            tuple((0, int(part)) if part.isdigit() else (1, part) for part in pre))


def _installed_version() -> str:
    root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[1]))
    try:
        version = (root / "VERSION").read_text(encoding="ascii").strip()
        version_key(version)
        return version
    except (OSError, ValueError):
        return "0.7.3"


VERSION = _installed_version()


def package_names(version: str) -> dict[str, str]:
    version_key(version)
    prefix = f"Clawd-Companion-{version}-"
    return {
        "pkg": prefix + "macOS-universal.pkg", "maczip": prefix + "macOS-universal.zip",
        "dmg": prefix + "macOS-universal.dmg",
        "exe": prefix + "Windows-x64-Setup.exe", "winzip": prefix + "Windows-x64-Portable.zip",
        "deb": f"clawd-companion_{version}_amd64.deb", "rpm": f"clawd-companion-{version}-1.x86_64.rpm",
        "tar": prefix + "Linux-x86_64.tar.gz",
    }


def package_options(version: str, assets, system: str, machine: str, distro: str = "") -> list[str]:
    arch = machine.lower()
    if system == "Darwin" and arch in {"arm64", "aarch64", "amd64", "x86_64"}:
        order = ["pkg", "dmg", "maczip"]
    elif arch not in {"x86_64", "amd64"}:
        return []
    elif system == "Windows":
        order = ["exe", "winzip"]
    elif system == "Linux":
        families = set(distro.lower().split())
        if families.intersection({"debian", "ubuntu", "linuxmint"}):
            order = ["deb", "tar", "rpm"]
        elif families.intersection({"fedora", "rhel", "suse", "opensuse", "centos"}):
            order = ["rpm", "tar", "deb"]
        else:
            order = ["tar", "deb", "rpm"]
    else:
        return []
    names = package_names(version)
    return [names[k] for k in order if names[k] in assets]


def platform_packages(release: Release) -> list[str]:
    try:
        distro = platform.freedesktop_os_release()
    except (AttributeError, OSError):
        distro = {}
    options = package_options(release.version, release.assets, platform.system(), platform.machine(),
                              distro.get("ID", "") + " " + distro.get("ID_LIKE", ""))
    if getattr(sys, "frozen", False):
        try:
            marker = Path(sys.executable).with_name("clawd-package.txt").read_text(encoding="ascii").strip()
        except (OSError, UnicodeError):
            marker = ""
        kinds = {"windows-portable": "winzip", "windows-installer": "exe", "linux-portable": "tar",
                 "linux-deb": "deb", "linux-rpm": "rpm"}
        preferred = package_names(release.version).get(kinds.get(marker))
        if preferred in options:
            options.remove(preferred)
            options.insert(0, preferred)
    return options


@dataclass(frozen=True)
class Release:
    version: str
    notes: str
    notes_by_language: dict[str, str]
    assets: tuple[str, ...]

    def localized_notes(self, language: str) -> str:
        code = language.replace("_", "-").lower()
        return self.notes_by_language.get(code) or self.notes_by_language.get(code.split("-")[0]) or self.notes

    @property
    def url(self) -> str:
        return REPOSITORY + "/releases/tag/v" + self.version

    def download(self, name: str) -> str:
        if name not in self.assets or name not in package_names(self.version).values():
            raise ValueError("Unrecognized package")
        return f"{REPOSITORY}/releases/download/v{self.version}/{name}"


def parse_manifest(data: bytes) -> Release:
    if len(data) > LIMIT:
        raise ValueError("Manifest too large")
    value = json.loads(data)
    if not isinstance(value, dict) or type(value.get("schema")) is not int or value["schema"] != 1:
        raise ValueError("Unsupported schema")
    version = value.get("version")
    version_key(version)
    if value.get("tag") != "v" + version:
        raise ValueError("Tag mismatch")
    notes, translations, assets = value.get("notes"), value.get("notesByLanguage", {}), value.get("assets")
    if not isinstance(notes, str) or not notes.strip() or len(notes.encode()) > 65_536:
        raise ValueError("Missing release notes")
    if not isinstance(translations, dict) or len(translations) > 24 or any(
        not re.fullmatch(r"[a-z]{2,3}(?:-[a-zA-Z0-9]{2,8})*", code)
        or not isinstance(text, str) or not text.strip() or len(text.encode()) > 65_536
        for code, text in translations.items()
    ):
        raise ValueError("Invalid translated release notes")
    if not isinstance(assets, list) or not 0 < len(assets) <= 64 or not all(isinstance(a, str) for a in assets):
        raise ValueError("Invalid assets")
    accepted = set(package_names(version).values())
    return Release(version, notes.strip(), {k.lower(): v.strip() for k, v in translations.items()},
                   tuple(a for a in assets if a in accepted))


def trusted_metadata_url(url: str) -> bool:
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.username or parts.password or parts.port not in (None, 443):
        return False
    if parts.hostname == "github.com":
        return parts.path.lower().startswith("/zumbyte-appsolution/clawd-companion/releases/")
    return parts.hostname in {"release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"}


class _ReleaseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not trusted_metadata_url(newurl):
            raise ValueError("Unexpected release redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_latest() -> Release:
    request = urllib.request.Request(MANIFEST_URL, headers={"User-Agent": "Clawd-Companion/" + VERSION})
    with urllib.request.build_opener(_ReleaseRedirect()).open(request, timeout=12) as response:
        if response.status != 200 or not trusted_metadata_url(response.geturl()):
            raise ValueError("Release unavailable")
        return parse_manifest(response.read(LIMIT + 1))
