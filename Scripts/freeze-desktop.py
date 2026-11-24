#!/usr/bin/env python3
"""Build the self-contained Qt application on the target operating system."""
import argparse
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
if platform.system() not in {"Windows", "Linux"} or platform.machine().lower() not in {"amd64", "x86_64"}:
    parser.error("Run on 64-bit Windows or x86_64 Linux")
out = args.out.resolve()
with tempfile.TemporaryDirectory() as scratch:
    command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir",
               "--windowed", "--noupx", "--name", "ClawdCompanion", "--distpath", str(out),
               "--workpath", scratch + "/build", "--specpath", scratch, "--paths", str(root / "Desktop"),
               ]
    if platform.system() == "Windows":
        images = [(size, (root / "BrowserExtension" / f"icon{size}.png").read_bytes()) for size in (32, 128)]
        offset = 6 + 16 * len(images)
        entries = bytearray(struct.pack("<HHH", 0, 1, len(images)))
        for size, data in images:
            entries.extend(struct.pack("<BBBBHHII", size, size, 0, 0, 1, 32, len(data), offset))
            offset += len(data)
        icon = Path(scratch, "Clawd.ico")
        icon.write_bytes(entries + b"".join(data for _, data in images))
        command.extend(["--icon", str(icon)])
    for source, destination in [("BrowserExtension", "BrowserExtension"), ("Resources", "Resources"),
                                ("Desktop/assets", "Desktop/assets"), ("VERSION", ".")]:
        path = root / source
        if path.exists():
            command.extend(["--add-data", str(path) + os.pathsep + destination])
    if platform.system() == "Linux":
        command.extend(["--collect-submodules", "Xlib"])
    command.append(str(root / "Desktop" / "companion.py"))
    subprocess.run(command, check=True, cwd=root)
