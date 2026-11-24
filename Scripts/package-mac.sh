#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(<"$root/VERSION")"
out="${1:-$root/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/clawd-macos.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
mkdir -p "$build/apps"
bash "$root/Scripts/build-mac.sh" "$build/apps"
app="$build/apps/Clawd Companion.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"
codesign --verify --deep --strict "$app"
for executable in "$app/Contents/MacOS/ClawdCompanion" "$app/Contents/PlugIns/ClawdSafari.appex/Contents/MacOS/ClawdSafari"; do
    architectures=" $(lipo -archs "$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]]
done
name="Clawd-Companion-$version-macOS-universal"
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$app" "$build/$name.zip"
pkgbuild --analyze --root "$build/apps" "$build/components.plist"
python3 - "$build/components.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
path = Path(sys.argv[1])
components = plistlib.loads(path.read_bytes())
companion = next(component for component in components if component["RootRelativeBundlePath"] == "Clawd Companion.app")
companion["BundleIsRelocatable"] = False
path.write_bytes(plistlib.dumps(components))
PY
set --
if [[ -n "${CLAWD_INSTALLER_IDENTITY:-}" ]]; then set -- --sign "$CLAWD_INSTALLER_IDENTITY"; fi
pkgbuild --root "$build/apps" --component-plist "$build/components.plist" --install-location /Applications \
    --identifier de.zumbyte.clawdcompanion.pkg --version "$version" "$@" "$build/$name.pkg"
pkgutil --expand-full "$build/$name.pkg" "$build/expanded"
test -x "$build/expanded/Payload/Clawd Companion.app/Contents/MacOS/ClawdCompanion"
codesign --verify --deep --strict "$build/expanded/Payload/Clawd Companion.app"
mv "$build/$name.zip" "$build/$name.pkg" "$out/"
