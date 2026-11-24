#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/Scripts/mac-signing.sh"
version="$(<"$root/VERSION")"
out="${1:-$root/dist}"
distribution=0
case "${2:-}" in
    --distribution) distribution=1 ;;
    "") ;;
    *) echo "Usage: package-mac.sh [output] [--distribution]" >&2; exit 2 ;;
esac
mkdir -p "$out"
out="$(cd "$out" && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/clawd-macos.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
mkdir -p "$build/apps"
app="$build/apps/Clawd Companion.app"
name="Clawd-Companion-$version-macOS-universal"
notary_auth=0
if [[ -n "${CLAWD_NOTARY_PROFILE:-}" || -n "${CLAWD_NOTARY_KEY:-}" ]]; then notary_auth=1; fi

if [[ -n "${CLAWD_EXPORTED_APP:-}" ]]; then
    ((distribution)) && [[ -d "$CLAWD_EXPORTED_APP/Contents" ]] || {
        echo "CLAWD_EXPORTED_APP must identify an exported app for --distribution." >&2; exit 2;
    }
    ditto "$CLAWD_EXPORTED_APP" "$app"
elif ((distribution)) && [[ -z "${CLAWD_SIGN_IDENTITY:-}" ]]; then
    # The account on this Mac can submit the app for notarization in Xcode too.
    if ((!notary_auth)); then export CLAWD_XCODE_NOTARIZE=1; fi
    bash "$root/Scripts/export-mac-xcode.sh" "$build/apps"
else
    if ((distribution)); then
        [[ "$CLAWD_SIGN_IDENTITY" != "-" && "$notary_auth" == 1 ]] || {
            echo "Explicit signing identity needs notarytool authentication." >&2; exit 1;
        }
        export CLAWD_DISTRIBUTION=1
    fi
    bash "$root/Scripts/build-mac.sh" "$build/apps"
fi
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"
codesign --verify --deep --strict "$app"
for executable in "$app/Contents/MacOS/ClawdCompanion" "$app/Contents/PlugIns/ClawdSafari.appex/Contents/MacOS/ClawdSafari"; do
    architectures=" $(lipo -archs "$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]]
done
if ((distribution)); then
    app_team="${CLAWD_DEVELOPMENT_TEAM:-J97L2NDXQR}"
    [[ "$app_team" =~ ^[A-Z0-9]{10}$ ]] || exit 2
    requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$app_team\""
    codesign --verify --strict --all-architectures -R="$requirement and identifier \"de.zumbyte.clawdcompanion\"" "$app"
    codesign --verify --strict --all-architectures -R="$requirement and identifier \"de.zumbyte.clawdcompanion.Safari\"" "$app/Contents/PlugIns/ClawdSafari.appex"
    if ((notary_auth)); then
        ditto -c -k --keepParent --norsrc --noextattr --noqtn "$app" "$build/submission.zip"
        notarize_artifact "$build/submission.zip"
        xcrun stapler staple "$app"
    fi
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
fi
ditto -c -k --keepParent --norsrc --noqtn "$app" "$build/$name.zip"
assets=("$build/$name.zip")
if ((distribution)); then
    ditto -x -k "$build/$name.zip" "$build/zip-check"
    xcrun stapler validate "$build/zip-check/Clawd Companion.app"
    mkdir "$build/image"
    ditto "$app" "$build/image/Clawd Companion.app"
    ln -s /Applications "$build/image/Applications"
    hdiutil create -quiet -format UDZO -fs HFS+ -volname "Claw’d Companion" -srcfolder "$build/image" "$build/$name.dmg"
    if ((notary_auth)); then
        notarize_artifact "$build/$name.dmg"
        xcrun stapler staple "$build/$name.dmg"
        xcrun stapler validate "$build/$name.dmg"
    fi
    hdiutil verify "$build/$name.dmg"
    assets+=("$build/$name.dmg")
    # This identity signs the optional flat installer, independently of app signing.
    if [[ -z "${CLAWD_INSTALLER_IDENTITY:-}" ]] && ((notary_auth)); then
        CLAWD_INSTALLER_IDENTITY="$(security find-identity -v -p basic | awk -v team="($app_team)" 'index($0,"\"Developer ID Installer:") && index($0, team "\"") {print $2; exit}')"
    fi
fi
if ((!distribution)) || [[ -n "${CLAWD_INSTALLER_IDENTITY:-}" && "$notary_auth" == 1 ]]; then
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
    sign=()
    if [[ -n "${CLAWD_INSTALLER_IDENTITY:-}" ]]; then sign=(--sign "$CLAWD_INSTALLER_IDENTITY"); fi
    pkgbuild --root "$build/apps" --component-plist "$build/components.plist" --install-location /Applications \
        --identifier de.zumbyte.clawdcompanion.pkg --version "$version" ${sign[@]+"${sign[@]}"} "$build/$name.pkg"
    if ((distribution)); then
        notarize_artifact "$build/$name.pkg"
        xcrun stapler staple "$build/$name.pkg"
        xcrun stapler validate "$build/$name.pkg"
        spctl --assess --type install "$build/$name.pkg"
        LC_ALL=C pkgutil --check-signature "$build/$name.pkg" > "$build/installer-signature"
        awk -v team="$app_team" '/^[[:space:]]*1[.] Developer ID Installer: / && index($0, "(" team ")") {found=1} END {exit !found}' "$build/installer-signature"
    fi
    pkgutil --expand-full "$build/$name.pkg" "$build/expanded"
    codesign --verify --deep --strict "$build/expanded/Payload/Clawd Companion.app"
    assets+=("$build/$name.pkg")
elif [[ -e "$out/$name.pkg" ]]; then
    # Keep any older local installer separate from the new release artifacts.
    mkdir -p "$out/previous"
    mv "$out/$name.pkg" "$out/previous/$name-$(date +%s).pkg"
fi
mv "${assets[@]}" "$out/"
