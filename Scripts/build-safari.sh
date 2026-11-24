#!/bin/bash
set -euo pipefail
if [[ $# != 1 || ! -f "$1/Contents/Info.plist" ]]; then
    echo "Aufruf: build-safari.sh /Pfad/zu/ClawdCompanion.app" >&2
    exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/Scripts/mac-signing.sh"
host="$1/Contents"
out="$host/PlugIns/ClawdSafari.appex/Contents"
src="$root/SafariExtension"
shared="$root/BrowserExtension"
mkdir -p "$out/MacOS" "$out/Resources"
cp "$src/Info.plist" "$out/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$host/Info.plist")"
/usr/bin/plutil -replace CFBundleIdentifier -string "$bundle_id.Safari" "$out/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$host/Info.plist")"
    /usr/bin/plutil -replace "$key" -string "$value" "$out/Info.plist"
done
cp "$src/manifest.json" "$out/Resources/"
for asset in background.js signals.js webpush.js observer.js notices.js popup.html popup.css popup-locale.js popup.js icon32.png icon128.png; do
    cp "$shared/$asset" "$out/Resources/"
done
ditto --norsrc --noextattr --noqtn "$shared/_locales" "$out/Resources/_locales"
command_args=(-arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -Os -fobjc-arc -fapplication-extension
              -framework Foundation -framework SafariServices -Xlinker -e -Xlinker _NSExtensionMain)
/usr/bin/xcrun --sdk macosx clang "${command_args[@]}" "$src/ClawdSafariHandler.m" -o "$out/MacOS/ClawdSafari"
# Finder may attach display metadata to a newly created bundle in Documents/iCloud.
# Remove only metadata that Apple's code signer rejects from this generated extension.
for key in com.apple.FinderInfo com.apple.ResourceFork; do
    /usr/bin/xattr -dr "$key" "$out/.." 2>/dev/null || true
done
sign_bundle "$out/.." --entitlements "$src/ClawdSafari.entitlements"
/usr/bin/codesign --verify --strict "$out/.."
