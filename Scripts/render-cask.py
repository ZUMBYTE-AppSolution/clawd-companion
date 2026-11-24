#!/usr/bin/env python3
"""Pin the Homebrew cask to the verified macOS archive from this release."""
import hashlib
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
version = sys.argv[2] if len(sys.argv) > 2 else (root / "VERSION").read_text().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Invalid VERSION")
cask = root / "Casks" / "clawd-companion.rb"
if cask.exists():
    pinned = re.search(r'^  version "(\d+\.\d+\.\d+)"$', cask.read_text(), re.MULTILINE)
    if not pinned:
        raise SystemExit("Cannot determine the existing cask version")
    if tuple(map(int, pinned[1].split("."))) > tuple(map(int, version.split("."))):
        print(f"Homebrew already points to a newer release ({pinned[1]})")
        sys.exit(0)
archive = Path(sys.argv[1]) / f"Clawd-Companion-{version}-macOS-universal.zip"
with archive.open("rb") as source:
    checksum = hashlib.file_digest(source, "sha256").hexdigest()
(root / "Casks").mkdir(exist_ok=True)
cask.write_text(f'''cask "clawd-companion" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v#{{version}}/Clawd-Companion-#{{version}}-macOS-universal.zip"
  name "Claw’d Companion"
  desc "Animated pixel desktop companion for Claude"
  homepage "https://github.com/ZUMBYTE-AppSolution/clawd-companion"

  depends_on macos: ">= :ventura"
  app "Clawd Companion.app"
end
''', encoding="utf-8")
