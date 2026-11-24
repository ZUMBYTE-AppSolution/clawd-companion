#!/usr/bin/env python3
"""Build the metadata asset from the release body and the packages actually present."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Desktop"))
from release_info import package_names, parse_manifest

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--notes", required=True, type=Path)
    parser.add_argument("--assets-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    version = args.tag.removeprefix("v")
    names = package_names(version)
    translations = {p.stem: p.read_text(encoding="utf-8") for p in sorted(args.notes.with_suffix("").glob("*.md"))}
    manifest = {"schema": 1, "version": version, "tag": args.tag, "notes": args.notes.read_text(encoding="utf-8"),
                "notesByLanguage": translations, "assets": sorted(n for n in names.values() if (args.assets_dir / n).is_file())}
    data = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    parse_manifest(data)
    args.output.write_bytes(data)

if __name__ == "__main__":
    main()
