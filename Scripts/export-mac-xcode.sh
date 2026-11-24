#!/bin/bash
# Export an automatically signed macOS app using Xcode Accounts or an App Store Connect team key.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?Usage: export-mac-xcode.sh output-directory}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
team="${CLAWD_DEVELOPMENT_TEAM:-J97L2NDXQR}"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid Apple developer team ID." >&2; exit 2; }
stage="$(mktemp -d "${TMPDIR:-/tmp}/clawd-xcode.XXXXXXXX")"
archive="$stage/ClawdCompanion.xcarchive"
keep_archive=false
cleanup() {
    if [[ "$keep_archive" == true ]]; then
        echo "Xcode's submitted archive is available at $archive" >&2
        rm -rf "$stage/DerivedData"
    else
        rm -rf "$stage"
    fi
}
trap cleanup EXIT
auth=(-allowProvisioningUpdates)
if [[ -n "${CLAWD_NOTARY_KEY:-}${CLAWD_NOTARY_KEY_ID:-}${CLAWD_NOTARY_ISSUER:-}" ]]; then
    auth+=(-authenticationKeyPath "${CLAWD_NOTARY_KEY:?Set the App Store Connect key path}"
           -authenticationKeyID "${CLAWD_NOTARY_KEY_ID:?Set the App Store Connect key ID}"
           -authenticationKeyIssuerID "${CLAWD_NOTARY_ISSUER:?Set the App Store Connect issuer}")
fi
version="$(<"$root/VERSION")"
number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/Resources/Info.plist")"
destination="export"
if [[ "${CLAWD_XCODE_NOTARIZE:-0}" == 1 ]]; then destination="upload"; fi
project="$root/ClawdCompanion.xcodeproj"
xcrun xcodebuild archive -project "$project" -scheme ClawdCompanion -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" -derivedDataPath "$stage/DerivedData" \
    "${auth[@]}" "DEVELOPMENT_TEAM=$team" "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$number"
options="$stage/ExportOptions.plist"
/usr/bin/plutil -create xml1 "$options"
/usr/bin/plutil -insert method -string developer-id "$options"
/usr/bin/plutil -insert signingStyle -string automatic "$options"
/usr/bin/plutil -insert teamID -string "$team" "$options"
/usr/bin/plutil -insert destination -string "$destination" "$options"
xcrun xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -exportPath "$stage/export" "${auth[@]}"
if [[ "$destination" == upload ]]; then
    keep_archive=true
    # The notarization service can finish after upload returns. Preserve the archive on timeout.
    finished=false
    for ((attempt=1; attempt<=60; attempt++)); do
        if xcrun xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$stage/notarized" "${auth[@]}"; then
            finished=true
            break
        fi
        if ((attempt < 60)); then sleep 30; fi
    done
    [[ "$finished" == true ]] || { echo "The notarized export is still unavailable. Check this archive in Xcode Organizer." >&2; exit 1; }
    exported="$stage/notarized/Clawd Companion.app"
    xcrun stapler validate "$exported"
    spctl --assess --type execute "$exported"
else
    exported="$stage/export/Clawd Companion.app"
fi
requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
for bundle in "$exported" "$exported/Contents/PlugIns/ClawdSafari.appex"; do
    codesign --verify --strict -R "$requirement" "$bundle"
    signature="$(codesign --display --verbose=4 "$bundle" 2>&1)"
    [[ "$signature" == *"(runtime)"* && "$signature" == *"Timestamp="* ]]
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")"
    architectures=" $(xcrun lipo -archs "$bundle/Contents/MacOS/$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]]
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$exported/Contents/Info.plist")" == "$version" ]]
# Refuse to overlay an existing app; ditto would retain files removed between releases.
[[ ! -e "$out/Clawd Companion.app" ]] || { echo "Choose an output directory without an existing Clawd Companion.app." >&2; exit 2; }
ditto "$exported" "$out/Clawd Companion.app"
keep_archive=false
