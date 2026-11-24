"""Package the Arena WSGI service from reviewed source files, without host state."""
import argparse
import gzip
import tarfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    destination = parser.parse_args().archive
    root = Path(__file__).resolve().parent.parent
    version = (root / "VERSION").read_text().strip()
    sources = ["VERSION", "Desktop/arcade.py", "Server/__init__.py", "Server/app.py",
               "Server/game.py", "Server/schema.sql", "Server/wsgi.py", "Server/README.md"]
    sources.extend(str(p.relative_to(root)) for p in sorted((root / "Server/deploy").iterdir())
                   if p.is_file() and not p.name.startswith(".") and p.suffix in {".nginx", ".conf", ".service", ".md", ".txt", ".example", ".sh"})
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output, gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
        with tarfile.open(mode="w", fileobj=compressed) as archive:
            for name in sources:
                source = root / name
                info = archive.gettarinfo(str(source), arcname=f"Clawd-Arena-API-{version}/{name}")
                info.mtime = info.uid = info.gid = 0
                info.uname = info.gname = ""
                with source.open("rb") as file:
                    archive.addfile(info, file)


if __name__ == "__main__":
    main()
