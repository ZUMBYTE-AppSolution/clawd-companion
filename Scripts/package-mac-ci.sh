#!/bin/bash
# The hosted Mac authenticates Xcode with App Store Connect. Certificates are optional.
set -euo pipefail
: "${MACOS_NOTARY_P8:?Configure MACOS_NOTARY_P8 for Xcode on the hosted Mac}"
: "${CLAWD_NOTARY_KEY_ID:?Configure MACOS_NOTARY_KEY_ID}"
: "${CLAWD_NOTARY_ISSUER:?Configure MACOS_NOTARY_ISSUER}"
umask 077
stage="$(mktemp -d "${RUNNER_TEMP:-/tmp}/clawd-sign.XXXXXXXX")"
chain="$stage/signing.keychain-db"
cleanup() {
    if [[ -f "$chain" ]]; then security delete-keychain "$chain" >/dev/null 2>&1 || true; fi
    rm -rf "$stage"
}
trap cleanup EXIT
export CLAWD_NOTARY_KEY="$stage/notary.p8"
printf '%s' "$MACOS_NOTARY_P8" > "$CLAWD_NOTARY_KEY"
unset MACOS_NOTARY_P8
if [[ -n "${MACOS_CERTIFICATES_P12:-}" ]]; then
    : "${MACOS_CERTIFICATES_PASSWORD:?Set the password for the optional PKCS12 export}"
    password="$(openssl rand -hex 32)"
    security create-keychain -p "$password" "$chain"
    security set-keychain-settings -lut 7200 "$chain"
    security unlock-keychain -p "$password" "$chain"
    printf '%s' "$MACOS_CERTIFICATES_P12" | /usr/bin/base64 -D > "$stage/identities.p12"
    security import "$stage/identities.p12" -k "$chain" -P "$MACOS_CERTIFICATES_PASSWORD" -T /usr/bin/codesign -T /usr/bin/pkgbuild -T /usr/bin/productsign
    rm "$stage/identities.p12"
    unset MACOS_CERTIFICATES_P12 MACOS_CERTIFICATES_PASSWORD
    security list-keychains -d user -s "$chain" "$HOME/Library/Keychains/login.keychain-db"
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$chain" >/dev/null
fi
bash "$(dirname "$0")/package-mac.sh" "${1:-dist}" --distribution
