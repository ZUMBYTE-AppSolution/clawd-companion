#!/bin/bash
# The fetch job can read private drafts. Only the verification job produces release artifacts.
set -euo pipefail
mode="${1:?expected fetch or verify}"
input="${2:?asset directory required}"
version="$(<VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
name="Clawd-Companion-$version-macOS-universal"
tag="v$version"
team=J97L2NDXQR
bundle=de.zumbyte.clawdcompanion
app_name="Clawd Companion.app"

if [[ "$mode" == fetch ]]; then
    [[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch && "${GITHUB_REF:-}" == refs/heads/main ]]
    [[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ && "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
    if git show-ref --verify --quiet "refs/tags/$tag"; then
        [[ "$(git rev-parse "refs/tags/$tag^{commit}")" == "$GITHUB_SHA" ]]
    fi
    metadata="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft,tagName,targetCommitish,assets)"
    jq -e --arg tag "$tag" --arg sha "$GITHUB_SHA" --arg base "$name" '
        .isDraft and .tagName == $tag and .targetCommitish == $sha and
        ([.assets[].name] | sort as $files |
            $files == [$base+".dmg",$base+".zip"] or
            $files == [$base+".dmg",$base+".pkg",$base+".zip"])' <<< "$metadata" >/dev/null
    mkdir -p "$input"
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir "$input" --pattern "$name.zip" --pattern "$name.dmg"
    if jq -e --arg pkg "$name.pkg" 'any(.assets[]; .name == $pkg)' <<< "$metadata" >/dev/null; then
        gh release download "$tag" --repo "$GITHUB_REPOSITORY" --dir "$input" --pattern "$name.pkg"
    fi
    exit 0
fi
[[ "$mode" == verify && "$(uname -s)" == Darwin ]] || exit 2
out="${3:?verified output directory required}"
mkdir -p "$out"
stage="$(mktemp -d "${TMPDIR:-/tmp}/clawd-draft.XXXXXXXX")"
mount="$stage/mounted"
mounted=0
cleanup() {
    if ((mounted)); then hdiutil detach "$mount" -quiet || return; fi
    rm -rf "$stage"
}
trap cleanup EXIT
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
verify_bundle() {
    local path="$1" identifier="$2" executable="$3" plist requirement architectures arch
    [[ -d "$path" && ! -L "$path" ]]
    plist="$path/Contents/Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == "$identifier" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$build_number" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" == "$executable" ]]
    requirement="anchor apple generic and identifier \"$identifier\" and certificate leaf[subject.OU] = \"$team\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    codesign --verify --strict --all-architectures -R="$requirement" "$path"
    architectures=" $(xcrun lipo -archs "$path/Contents/MacOS/$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]]
}
verify_app() {
    local app="$1"
    verify_bundle "$app" "$bundle" ClawdCompanion
    verify_bundle "$app/Contents/PlugIns/ClawdSafari.appex" "$bundle.Safari" ClawdSafari
    codesign --verify --deep --strict "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
}
identity_hashes() {
    local arch app="$1"
    for arch in arm64 x86_64; do
        codesign -d --arch "$arch" -vv "$app" 2>&1 | awk -F= '/^CDHash=/{print $2; n++} END{exit n!=1}'
    done
}

# Inspect ZIP paths before unpacking. This app's bundle does not use framework symlinks.
python3 - "$input/$name.zip" "$app_name" <<'PY'
import stat, sys, zipfile
from pathlib import PurePosixPath
with zipfile.ZipFile(sys.argv[1]) as archive:
    for item in archive.infolist():
        path = PurePosixPath(item.filename)
        if not path.parts or path.parts[0] not in (sys.argv[2], "__MACOSX") or ".." in path.parts:
            raise SystemExit(f"Unexpected ZIP entry: {path}")
        if stat.S_ISLNK(item.external_attr >> 16):
            raise SystemExit(f"Unexpected ZIP symlink: {path}")
PY
ditto -x -k "$input/$name.zip" "$stage/zip"
verify_app "$stage/zip/$app_name"
expected="$(identity_hashes "$stage/zip/$app_name")"
mkdir "$mount"
hdiutil verify "$input/$name.dmg"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" "$input/$name.dmg" >/dev/null
mounted=1
python3 - "$mount" "$app_name" <<'PYDMG'
from pathlib import Path
import sys
allowed = {sys.argv[2], "Applications", ".fseventsd", ".Trashes", ".Spotlight-V100", ".DS_Store",
           ".HFS+ Private Directory Data\r", ".DocumentRevisions-V100"}
for item in Path(sys.argv[1]).iterdir():
    if item.name not in allowed:
        raise SystemExit(f"Unexpected disk image entry: {item.name!r}")
PYDMG
[[ -L "$mount/Applications" && "$(readlink "$mount/Applications")" == /Applications ]]
verify_app "$mount/$app_name"
[[ "$(identity_hashes "$mount/$app_name")" == "$expected" ]]
hdiutil detach "$mount" -quiet
mounted=0
packages=("$input/$name.zip" "$input/$name.dmg")
if [[ -f "$input/$name.pkg" ]]; then
    pkg="$input/$name.pkg"
    LC_ALL=C pkgutil --check-signature "$pkg" > "$stage/pkg-signature"
    awk -v team="($team)" '/^[[:space:]]*1[.] Developer ID Installer: / && substr($0, length($0)-length(team)+1)==team {found=1} END {exit !found}' "$stage/pkg-signature"
    xcrun stapler validate "$pkg"
    spctl --assess --type install "$pkg"
    pkgutil --expand-full "$pkg" "$stage/pkg"
    python3 - "$stage/pkg/PackageInfo" "$version" <<'PYPKG'
import sys, xml.etree.ElementTree as ET
info = ET.parse(sys.argv[1]).getroot()
if (info.get("identifier"), info.get("version"), info.get("install-location")) != (
        "de.zumbyte.clawdcompanion.pkg", sys.argv[2], "/Applications"):
    raise SystemExit("Unexpected installer identifier, version or location")
PYPKG
    verify_app "$stage/pkg/Payload/$app_name"
    [[ "$(identity_hashes "$stage/pkg/Payload/$app_name")" == "$expected" ]]
    packages+=("$pkg")
fi
cp "${packages[@]}" "$out/"
