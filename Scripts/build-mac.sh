#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/.build/app}"
mkdir -p "$output_dir"
staging="$(mktemp -d "${TMPDIR:-/tmp}/clawd-build.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Clawd Companion.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$staging/modules"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -whole-module-optimization \
        -target "$arch-apple-macos13.0" -module-cache-path "$staging/modules" \
        -module-name ClawdCompanion "$project_dir"/Sources/ClawdCompanion/*.swift \
        -o "$staging/ClawdCompanion-$arch"
done
xcrun lipo -create "$staging/ClawdCompanion-arm64" "$staging/ClawdCompanion-x86_64" \
    -output "$contents/MacOS/ClawdCompanion"
cp -X "$project_dir/Resources/Info.plist" "$contents/Info.plist"
cp -X "$project_dir/Resources/ClawdDialogue.ttf" "$project_dir/Resources/Clawd.icns" "$project_dir/Resources/MenuPet.png" \
    "$project_dir/Resources/MenuPet@2x.png" "$contents/Resources/"
ditto --norsrc --noextattr --noqtn "$project_dir/Resources/Languages" "$contents/Resources/Languages"
if [[ -f "$project_dir/Resources/ArenaEndpoint.txt" ]]; then
    cp -X "$project_dir/Resources/ArenaEndpoint.txt" "$contents/Resources/ArenaEndpoint.txt"
fi
ditto --norsrc --noextattr --noqtn "$project_dir/BrowserExtension" "$contents/Resources/BrowserExtension"
bash "$project_dir/Scripts/build-safari.sh" "$app"
codesign --force --sign "${CLAWD_SIGN_IDENTITY:--}" --timestamp=none "$app"
codesign --verify --deep --strict --verbose=1 "$app"
ditto --norsrc --noextattr --noqtn "$app" "$output_dir/Clawd Companion.app"
echo "Gebaut: $output_dir/Clawd Companion.app"
