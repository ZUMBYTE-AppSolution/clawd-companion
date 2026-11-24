#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(<"$root/VERSION")"
[[ "$(uname -sm)" = "Linux x86_64" && "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
out="${1:-$root/dist}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
python3 "$root/Scripts/freeze-desktop.py" --out "$build/frozen"
frozen="$build/frozen/ClawdCompanion"
test -x "$frozen/ClawdCompanion"
echo linux-portable > "$frozen/clawd-package.txt"
tar -C "$build/frozen" -czf "$out/Clawd-Companion-$version-Linux-x86_64.tar.gz" ClawdCompanion
payload="$build/payload"
mkdir -p "$payload/opt" "$payload/usr/bin" "$payload/usr/share/applications" "$payload/usr/share/icons/hicolor/128x128/apps"
cp -a "$frozen" "$payload/opt/clawd-companion"
ln -s /opt/clawd-companion/ClawdCompanion "$payload/usr/bin/clawd-companion"
cp "$root/Packaging/linux/clawd-companion.desktop" "$payload/usr/share/applications/"
cp "$root/BrowserExtension/icon128.png" "$payload/usr/share/icons/hicolor/128x128/apps/clawd-companion.png"
mkdir -p "$build/rpm"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
echo linux-rpm > "$payload/opt/clawd-companion/clawd-package.txt"
tar -C "$payload" -czf "$build/rpm/SOURCES/payload.tar.gz" .
sed "s/@VERSION@/$version/g" "$root/Packaging/linux/clawd-companion.spec.in" > "$build/rpm/SPECS/clawd-companion.spec"
rpmbuild --define "_topdir $build/rpm" --define '_binary_payload w9.gzdio' -bb "$build/rpm/SPECS/clawd-companion.spec"
rpmfile="clawd-companion-$version-1.x86_64.rpm"
rpm -qpl "$build/rpm/RPMS/x86_64/$rpmfile" > "$build/rpm-files"
grep -Fxq /opt/clawd-companion/ClawdCompanion "$build/rpm-files"
mv "$build/rpm/RPMS/x86_64/$rpmfile" "$out/"
echo linux-deb > "$payload/opt/clawd-companion/clawd-package.txt"
mkdir -p "$payload/DEBIAN"
sed "s/@VERSION@/$version/g" "$root/Packaging/linux/control.in" > "$payload/DEBIAN/control"
deb="$out/clawd-companion_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$payload" "$deb"
test "$(dpkg-deb -f "$deb" Version)" = "$version"
test "$(dpkg-deb -f "$deb" Architecture)" = amd64
