"""Declare the external ELF libraries used by the bundled Qt WebEngine on x86_64."""
import os
from pathlib import Path
import re
import subprocess
import sys

bundle = Path(sys.argv[1]).resolve()
template = Path(sys.argv[2]).read_text()
libraries = sorted({p.parent for p in bundle.rglob("*.so*") if p.is_file()})
environment = dict(os.environ, LD_LIBRARY_PATH=os.pathsep.join(map(str, [bundle, *libraries])))
required = set()
for filename in ("libQt6WebEngineCore.so.6", "QtWebEngineProcess"):
    target = next(p for p in bundle.rglob(filename) if p.is_file())
    output = subprocess.check_output(["ldd", str(target)], env=environment, text=True)
    if "=> not found" in output:
        raise SystemExit(f"Unresolved ELF dependencies for {filename}:\n{output}")
    for soname, path in re.findall(r"^\s*(\S+) => (/\S+)", output, re.MULTILINE):
        if not Path(path).resolve().is_relative_to(bundle):
            required.add(f"Requires: {soname}()(64bit)")
print(template.replace("@VERSION@", sys.argv[3]).replace("@WEBENGINE_REQUIRES@", "\n".join(sorted(required))))
