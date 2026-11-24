"""Exercise the operator cutover and rollback with fake service and network boundaries."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from Scripts import deploy_arena_host as deploy

ROOT = Path(__file__).resolve().parents[2]
SITE = """# Existing CMS server
server { listen 80; server_name zumbyte.de; return 301 https://$host$request_uri; }
server {
    listen 443 ssl;
    server_name www.zumbyte.de zumbyte.de;
    location /api/other/ { proxy_pass http://other; }
    location / { try_files $uri /index.php; }
}
server { listen 443 ssl; server_name other.example; location / { return 204; } }
"""


class OperatorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.archive = self.root / "release.tar.gz"
        subprocess.run([sys.executable, str(ROOT / "Scripts/package-arena-server.py"), str(self.archive)], check=True)
        self.version, self.sha, self.files = deploy.archive_files(self.archive)
        self.site = self.root / "etc/nginx/sites-enabled/site.conf"
        self.site.parent.mkdir(parents=True)
        self.site.write_text(SITE)
        self.running = self.enabled = self.fail_nginx = False
        self.calls, self.smokes = [], []

    def command(self, *args, check=True):
        self.calls.append(args)
        status, output = 0, ""
        if args == ("nginx", "-T"):
            output = "# configuration file " + str(self.site) + ":\n" + self.site.read_text()
        elif args == ("nginx", "-t") and self.fail_nginx:
            status = 1
        elif args == ("systemctl", "is-active", "--quiet", "clawd-arena"):
            status = int(not self.running)
        elif args == ("systemctl", "is-enabled", "--quiet", "clawd-arena"):
            status = int(not self.enabled)
        elif args[:2] in (("systemctl", "start"), ("systemctl", "restart")):
            self.running = True
        elif args[:2] == ("systemctl", "stop"):
            self.running = False
        elif args[:2] == ("systemctl", "enable"):
            self.enabled = True
        if check and status:
            raise subprocess.CalledProcessError(status, args)
        return subprocess.CompletedProcess(args, status, output, "")

    def install(self, *, fail_public=False, files=None, sha=None):
        def smoke(url, local=False):
            self.smokes.append(url)
            if fail_public and not local:
                raise RuntimeError("fixture public JSON is not 401")
        with patch.object(deploy, "run", self.command), patch.object(deploy, "smoke", smoke), contextlib.redirect_stdout(io.StringIO()):
            deploy.apply_release(self.version, sha or self.sha, files or self.files, "", root=self.root)

    def test_archive_inspection_cli_runs_offline_and_rejects_traversal(self):
        normal = [str(ROOT / "Scripts/deploy-arena.sh"), "--archive", str(self.archive), "--check-local"]
        with tempfile.TemporaryDirectory() as fake_bin:
            ssh = Path(fake_bin, "ssh")
            ssh.write_text("#!/bin/sh\nexit 77\n")
            ssh.chmod(0o755)
            env = dict(os.environ, PATH=fake_bin + ":" + os.environ["PATH"])
            output = subprocess.check_output(normal + ["--sha256", self.sha], env=env, text=True)
            self.assertIn(self.sha, output)
            self.assertNotEqual(subprocess.run(normal + ["--sha256", "0"*64], env=env, capture_output=True).returncode, 0)
        malicious = self.root / "invalid.tar.gz"
        with tarfile.open(malicious, "w:gz") as tar:
            entry = tarfile.TarInfo("../outside")
            entry.size = 1
            tar.addfile(entry, io.BytesIO(b"x"))
        with self.assertRaises(ValueError):
            deploy.archive_files(malicious)

    def test_ssh_options_and_identity_are_local_and_remote_payload_is_literal(self):
        tools_dir = self.root / "fake-bin"
        tools_dir.mkdir()
        ssh = tools_dir / "ssh"
        ssh.write_text("#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\n"
                       "out=Path(os.environ['FIXTURE_CAPTURE'])\n"
                       "(out/'arguments').write_text(json.dumps(sys.argv[1:]))\n"
                       "(out/'payload.tar').write_bytes(sys.stdin.buffer.read())\n")
        ssh.chmod(0o755)
        identity = self.root / "operator identity"
        identity.write_text("placeholder fixture, no private key")
        site = "/etc/nginx/sites-available/test site.conf"
        subprocess.run([str(ROOT / "Scripts/deploy-arena.sh"), "--host", "fixture-user@fixture.invalid",
                        "--port", "2222", "--identity", str(identity), "--archive", str(self.archive),
                        "--nginx-site", site], env=dict(os.environ, PATH=str(tools_dir) + ":" + os.environ["PATH"],
                                                       FIXTURE_CAPTURE=str(self.root)), check=True, capture_output=True)
        argv = json.loads((self.root / "arguments").read_text())
        for value in ["StrictHostKeyChecking=yes", "BatchMode=yes", "ForwardAgent=no", "fixture-user@fixture.invalid"]:
            self.assertIn(value, argv)
        self.assertEqual(argv[argv.index("-i") + 1], str(identity))
        self.assertEqual(argv[argv.index("-p") + 1], "2222")
        with tarfile.open(self.root / "payload.tar") as upload:
            self.assertEqual(set(upload.getnames()), {"deploy.py", "release.tar.gz", "options.json"})
            options = json.load(upload.extractfile("options.json"))
            self.assertEqual(options, {"sha256": self.sha, "site": site})
            self.assertNotIn(site, argv[-1])

    def test_discovers_only_active_exact_tls_vhost_preserving_adjacent_routes(self):
        file, original, revised = deploy.choose_site([self.site], str(self.site))
        self.assertEqual(file, self.site.resolve())
        self.assertEqual(revised.replace(("\n    " + deploy.INCLUDE).encode(), b""), original)
        self.assertIn(("server {\n    " + deploy.INCLUDE + "\n    listen 443 ssl;").encode(), revised)
        other = self.site.with_name("second.conf")
        other.write_text("server {listen [::]:443 ssl; server_name zumbyte.de;}")
        with self.assertRaises(ValueError):
            deploy.choose_site([self.site, other], "")
        self.assertEqual(deploy.choose_site([self.site, other], str(other))[0], other.resolve())
        with self.assertRaises(ValueError):
            deploy.choose_site([self.site], str(other))
        self.site.write_text(SITE.replace("location /api/other/", "location /api/clawd/v1/"))
        with self.assertRaises(ValueError):
            deploy.choose_site([self.site], "")

    def test_second_deploy_preserves_secret_database_and_service(self):
        self.install()
        self.assertTrue(self.running and self.enabled)
        first = self.site.read_bytes()
        key = self.root / "etc/clawd-arena.env"
        secret = key.read_bytes()
        db = self.root / "var/lib/clawd-arena/arena.sqlite3"
        db.parent.mkdir(parents=True)
        db.write_bytes(b"operator-owned data")
        self.calls.clear()
        self.install()
        self.assertEqual(first, self.site.read_bytes())
        self.assertEqual(key.read_bytes(), secret)
        self.assertEqual(db.read_bytes(), b"operator-owned data")
        self.assertNotIn(("systemctl", "restart", "clawd-arena"), self.calls)
        self.assertNotIn(("systemctl", "reload", "nginx"), self.calls)
        self.assertEqual(len(self.smokes), 4)

    def test_bad_nginx_and_public_smoke_restore_vhost_unit_and_service(self):
        unit = self.root / "etc/systemd/system/clawd-arena.service"
        self.fail_nginx = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual(self.site.read_text(), SITE)
        self.assertFalse(unit.exists())
        self.assertNotIn(("systemctl", "reload", "nginx"), self.calls)
        self.fail_nginx = False
        with self.assertRaisesRegex(RuntimeError, "fixture public"):
            self.install(fail_public=True)
        self.assertFalse(self.running or self.enabled or unit.exists())
        self.assertEqual(self.site.read_text(), SITE)
        self.install()
        previous = unit.read_bytes()
        altered = dict(self.files)
        altered["Server/app.py"] += b"\n# fixture release\n"
        with self.assertRaisesRegex(RuntimeError, "fixture public"):
            self.install(files=altered, sha=hashlib.sha256(altered["Server/app.py"]).hexdigest(), fail_public=True)
        self.assertTrue(self.running and self.enabled)
        self.assertEqual(unit.read_bytes(), previous)

    def test_missing_secret_for_existing_database_stops_before_service_change(self):
        db = self.root / "var/lib/clawd-arena/arena.sqlite3"
        db.parent.mkdir(parents=True)
        db.write_bytes(b"existing")
        with self.assertRaisesRegex(ValueError, "matching environment"):
            self.install()
        self.assertEqual(db.read_bytes(), b"existing")
        self.assertEqual(self.site.read_text(), SITE)
        self.assertFalse(self.running)
