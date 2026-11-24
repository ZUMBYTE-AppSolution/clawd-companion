#!/usr/bin/env python3
"""Pin the Homebrew cask to the verified macOS archive from this release."""
import hashlib
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
version = (root / "VERSION").read_text().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Invalid VERSION")
archive = Path(sys.argv[1]) / f"Clawd-Companion-{version}-macOS-universal.zip"
with archive.open("rb") as source:
    checksum = hashlib.file_digest(source, "sha256").hexdigest()
(root / "Casks").mkdir(exist_ok=True)
(root / "Casks" / "clawd-companion.rb").write_text(f'''cask "clawd-companion" do
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
