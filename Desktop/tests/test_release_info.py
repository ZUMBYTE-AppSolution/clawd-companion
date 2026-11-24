import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_info import (LIMIT, MANIFEST_URL, REPOSITORY, fetch_latest, package_names, package_options, parse_manifest,
                          platform_packages, trusted_metadata_url, version_key)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.names = package_names("0.10.0")
        self.manifest = {"schema": 1, "version": "0.10.0", "tag": "v0.10.0", "notes": "## Changes\n- Better",
                         "notesByLanguage": {"de": "## Änderungen", "pt-BR": "Brasil"},
                         "assets": list(self.names.values())}

    def test_semver_spec(self):
        versions = ["0.6.9", "0.6.10", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta",
                    "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        ordered = list(map(version_key, versions))
        self.assertEqual(ordered, sorted(ordered))
        self.assertEqual(version_key("1.0.0+build.3"), version_key("1.0.0+42"))
        for value in ["1", "0.01.4", "0.0.1-01", "0.4.0/other", "0.4.0‪", "1.0.0\n", "../", "v0.6.0"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                version_key(value)

    def test_check_and_download_without_api(self):
        release = parse_manifest(json.dumps(self.manifest).encode())
        self.assertEqual(MANIFEST_URL, REPOSITORY + "/releases/latest/download/clawd-update.json")
        self.assertEqual(release.localized_notes("de-DE"), "## Änderungen")
        self.assertEqual(release.localized_notes("pt_BR"), "Brasil")
        self.assertEqual(release.localized_notes("zh"), self.manifest["notes"])
        self.assertEqual(release.download(self.names["pkg"]),
                         f"{REPOSITORY}/releases/download/v0.10.0/{self.names['pkg']}")
        for name in ["../some.exe", "https://example.org/test.deb", "other.pkg", ""]:
            with self.assertRaises(ValueError):
                release.download(name)

    def test_platform_selection_and_redirects(self):
        names = self.names
        def options(osname, arch, distro=""):
            return package_options("0.10.0", names.values(), osname, arch, distro)
        self.assertEqual(options("Windows","AMD64"), [names["exe"], names["winzip"]])
        self.assertEqual(options("Darwin","arm64"), [names["pkg"], names["dmg"], names["maczip"]])
        self.assertEqual(options("Linux","x86_64","ubuntu debian")[0], names["deb"])
        self.assertEqual(options("Linux","x86_64","fedora")[0], names["rpm"])
        self.assertEqual(options("Linux","x86_64","arch")[0], names["tar"])
        self.assertEqual(options("Linux","aarch64"), [])
        self.assertEqual(options("Windows","ARM64"), [])
        self.assertTrue(trusted_metadata_url(MANIFEST_URL))
        self.assertTrue(trusted_metadata_url("https://release-assets.githubusercontent.com/file?token=abc"))
        for url in ["http://github.com/a", "https://api.github.com", "https://github.com/other/a/releases/",
                    "https://evil.github.com/", "https://x@github.com/ZUMBYTE-AppSolution/clawd-companion/releases/",
                    "https://objects.githubusercontent.com:8080/path"]:
            self.assertFalse(trusted_metadata_url(url))

    def test_real_client_with_fake_http_stream_and_no_remote_installer_fetch(self):
        import io
        class Response(io.BytesIO):
            status = 200
            def geturl(self):
                return "https://release-assets.githubusercontent.com/github-production-release-asset/test"
        with patch("urllib.request.build_opener") as build:
            build.return_value.open.return_value = Response(json.dumps(self.manifest).encode())
            self.assertEqual(fetch_latest().version, "0.10.0")
            self.assertEqual(build.return_value.open.call_args.args[0].full_url, MANIFEST_URL)
            build.return_value.open.return_value = Response(bytes(LIMIT + 1))
            with self.assertRaises(ValueError):
                fetch_latest()

    def test_bogus_or_malicious_manifest(self):
        for change in [dict(schema=2), dict(tag="v1.0.0"), dict(assets=[]), dict(notes=" "),
                       dict(version="9.0.0?url=http"), dict(notesByLanguage={"..": "hmm"})]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                parse_manifest(json.dumps(self.manifest | change).encode())
        release = parse_manifest(json.dumps(self.manifest | {"assets": ["../../bad.pkg"]}).encode())
        self.assertEqual(release.assets, ())

    def test_release_generator_uses_only_built_files_and_real_notes(self):
        script = Path(__file__).resolve().parents[2] / "Scripts" / "make-update-manifest.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "0.10.0.md"
            notes.write_text(self.manifest["notes"], encoding="utf-8")
            locales = notes.with_suffix("")
            locales.mkdir()
            (locales / "de.md").write_text("## Änderungen", encoding="utf-8")
            (root / self.names["rpm"]).touch()
            destination = root / "clawd-update.json"
            subprocess.run([sys.executable, str(script), "--tag", "v0.10.0", "--notes", str(notes),
                            "--assets-dir", str(root), "--output", str(destination)], check=True)
            release = parse_manifest(destination.read_bytes())
            self.assertEqual(release.notes, notes.read_text())
            self.assertEqual(release.localized_notes("de"), "## Änderungen")
            self.assertEqual(release.assets, (self.names["rpm"],))

    def test_linux_portable_marker_keeps_archive_on_debian(self):
        release = parse_manifest(json.dumps(self.manifest).encode())
        with tempfile.TemporaryDirectory() as temp:
            (Path(temp) / "clawd-package.txt").write_text("linux-portable")
            with patch.object(sys, "frozen", True, create=True), patch.object(sys, "executable", temp + "/ClawdCompanion"), \
                 patch("platform.machine", return_value="x86_64"), patch("platform.system", return_value="Linux"), \
                 patch("platform.freedesktop_os_release", return_value={"ID": "debian"}, create=True):
                self.assertEqual(platform_packages(release)[0], self.names["tar"])
