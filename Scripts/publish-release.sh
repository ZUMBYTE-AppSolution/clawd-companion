#!/usr/bin/env bash
# Runs only after every platform has passed the packaged application smoke tests.
set -euo pipefail
assets="${1:?release assets directory required}"
version="$(<VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
tag="v$version"
if [[ "${GITHUB_REF_TYPE:-}" = tag && "$GITHUB_REF_NAME" != "$tag" ]]; then echo 'Tag does not match VERSION' >&2; exit 1; fi
notes="docs/releases/$version.md"
test -s "$notes"
packages=("Clawd-Companion-$version-macOS-universal.pkg" "Clawd-Companion-$version-macOS-universal.zip"
          "Clawd-Companion-$version-Windows-x64-Setup.exe" "Clawd-Companion-$version-Windows-x64-Portable.zip"
          "Clawd-Companion-$version-Linux-x86_64.tar.gz" "clawd-companion_${version}_amd64.deb" "clawd-companion-$version-1.x86_64.rpm")
paths=()
for asset in "${packages[@]}"; do test -s "$assets/$asset"; paths+=("$assets/$asset"); done
python3 Scripts/make-update-manifest.py --tag "$tag" --notes "$notes" --assets-dir "$assets" --output "$assets/clawd-update.json"
(cd "$assets" && sha256sum "${packages[@]}" clawd-update.json > SHA256SUMS)
paths+=("$assets/clawd-update.json" "$assets/SHA256SUMS")
state="$(gh release view "$tag" --json isDraft --jq '.isDraft' 2>/dev/null || true)"
if [[ "$state" = false ]]; then
    # A completed release is immutable here. Always pin to the published bytes.
    stable="$(mktemp -d)"
    trap 'rm -rf "$stable"' EXIT
    maczip="Clawd-Companion-$version-macOS-universal.zip"
    gh release download "$tag" --pattern "$maczip" --pattern SHA256SUMS --dir "$stable"
    (cd "$stable" && sha256sum --ignore-missing -c SHA256SUMS)
    cask_assets="$stable"
else
    if [[ -n "$(git ls-remote --tags origin "refs/tags/$tag")" ]]; then
        git fetch origin "refs/tags/$tag:refs/tags/$tag"
        test "$(git rev-list -1 "$tag")" = "$GITHUB_SHA"
    fi
    if [[ "$state" != true ]]; then
        gh release create "$tag" --draft --target "$GITHUB_SHA" --notes-file "$notes" --title "Claw’d Companion $version"
    fi
    gh release upload "$tag" "${paths[@]}" --clobber
    gh release edit "$tag" --draft=false --latest --target "$GITHUB_SHA" --notes-file "$notes"
    cask_assets="$assets"
fi
# Only the cask changes. This commit does not retrigger the release workflow.
git fetch origin main:refs/remotes/origin/main
git switch -C clawd-cask-publish origin/main
if [[ "$(cat VERSION)" != "$version" ]]; then echo "A newer version is already on main"; exit 0; fi
python3 Scripts/render-cask.py "$cask_assets"
if [[ -n "$(git status --porcelain -- Casks/clawd-companion.rb)" ]]; then
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git config user.name "github-actions[bot]"
    git add Casks/clawd-companion.rb
    git commit -m "Pin Homebrew cask for $tag"
    git push origin HEAD:main
fi
