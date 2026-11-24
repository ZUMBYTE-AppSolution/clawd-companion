#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/Scripts/mac-signing.sh"
if [[ "${2:-}" == "--distribution" ]]; then
    export CLAWD_DISTRIBUTION=1
    if [[ -z "${CLAWD_SIGN_IDENTITY:-}" ]]; then CLAWD_SIGN_IDENTITY="$(developer_identity Application codesigning)"; fi
    if [[ -z "${CLAWD_INSTALLER_IDENTITY:-}" ]]; then CLAWD_INSTALLER_IDENTITY="$(developer_identity Installer basic)"; fi
    [[ "$CLAWD_SIGN_IDENTITY" != "-" && "$CLAWD_INSTALLER_IDENTITY" != "-" ]] || exit 1
    export CLAWD_SIGN_IDENTITY CLAWD_INSTALLER_IDENTITY
    if [[ -z "${CLAWD_NOTARY_PROFILE:-}" ]]; then
        : "${CLAWD_NOTARY_KEY:?Set CLAWD_NOTARY_PROFILE or configure App Store Connect API authentication}"
    fi
elif [[ -n "${2:-}" ]]; then
    echo "Usage: package-mac.sh [output] [--distribution]" >&2; exit 2
fi
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
if [[ "${CLAWD_DISTRIBUTION:-0}" == 1 ]]; then
    notarize_artifact "$build/$name.zip"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
    rm "$build/$name.zip"
    ditto -c -k --keepParent --norsrc --noextattr --noqtn "$app" "$build/$name.zip"
    ditto -x -k "$build/$name.zip" "$build/zip-check"
    xcrun stapler validate "$build/zip-check/Clawd Companion.app"
fi
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
if [[ "${CLAWD_DISTRIBUTION:-0}" == 1 ]]; then
    notarize_artifact "$build/$name.pkg"
    xcrun stapler staple "$build/$name.pkg"
    xcrun stapler validate "$build/$name.pkg"
    pkgutil --check-signature "$build/$name.pkg"
    spctl --assess --type install "$build/$name.pkg"
    app_team="$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    [[ "$app_team" =~ ^[A-Z0-9]{10}$ ]]
    pkgutil --check-signature "$build/$name.pkg" > "$build/installer-signature"
    LC_ALL=C awk -v team="$app_team" '/^[[:space:]]*1[.] Developer ID Installer: / && index($0, "(" team ")") {found=1} END {exit !found}' "$build/installer-signature"
fi
pkgutil --expand-full "$build/$name.pkg" "$build/expanded"
test -x "$build/expanded/Payload/Clawd Companion.app/Contents/MacOS/ClawdCompanion"
codesign --verify --deep --strict "$build/expanded/Payload/Clawd Companion.app"
mv "$build/$name.zip" "$build/$name.pkg" "$out/"
