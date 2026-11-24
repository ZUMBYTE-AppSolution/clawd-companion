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
lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/ClawdCompanion"
lipo -verify_arch arm64 x86_64 "$app/Contents/PlugIns/ClawdSafari.appex/Contents/MacOS/ClawdSafari"
name="Clawd-Companion-$version-macOS-universal"
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$app" "$build/$name.zip"
pkgbuild --analyze --root "$build/apps" "$build/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$build/components.plist"
sign_args=()
if [[ -n "${CLAWD_INSTALLER_IDENTITY:-}" ]]; then sign_args+=(--sign "$CLAWD_INSTALLER_IDENTITY"); fi
pkgbuild --root "$build/apps" --component-plist "$build/components.plist" --install-location /Applications \
    --identifier de.zumbyte.clawdcompanion.pkg --version "$version" "${sign_args[@]}" "$build/$name.pkg"
pkgutil --expand-full "$build/$name.pkg" "$build/expanded"
test -x "$build/expanded/Payload/Clawd Companion.app/Contents/MacOS/ClawdCompanion"
codesign --verify --deep --strict "$build/expanded/Payload/Clawd Companion.app"
mv "$build/$name.zip" "$build/$name.pkg" "$out/"
