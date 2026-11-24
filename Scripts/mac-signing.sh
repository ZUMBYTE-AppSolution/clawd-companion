# Shared by the macOS build and packaging scripts (Bash).
sign_bundle() {
    local bundle="$1"
    shift
    local options=(--timestamp=none)
    if [[ "${CLAWD_DISTRIBUTION:-0}" == 1 || "${CLAWD_SIGN_IDENTITY:--}" != "-" ]]; then
        options=(--options runtime --timestamp)
    fi
    /usr/bin/codesign --force --sign "${CLAWD_SIGN_IDENTITY:--}" "${options[@]}" "$@" "$bundle"
}

developer_identity() {
    local prefix="$1" policy="$2" candidates count
    candidates="$(security find-identity -v -p "$policy" | awk -v label="\"Developer ID $prefix:" 'index($0,label) {print $2}')"
    count="$(awk 'NF {n++} END {print n+0}' <<< "$candidates")"
    [[ "$count" == 1 ]] || { echo "Expected one usable Developer ID $prefix identity, found $count." >&2; return 1; }
    echo "$candidates"
}

notarize_artifact() {
    local file="$1"
    local auth=()
    if [[ -n "${CLAWD_NOTARY_PROFILE:-}" ]]; then
        auth=(--keychain-profile "$CLAWD_NOTARY_PROFILE")
    else
        auth=(--key "${CLAWD_NOTARY_KEY:?Missing notary key file}" --key-id "${CLAWD_NOTARY_KEY_ID:?Missing key ID}" --issuer "${CLAWD_NOTARY_ISSUER:?Missing issuer}")
    fi
    xcrun notarytool submit "$file" "${auth[@]}" --wait --timeout 30m --output-format plist > "$build/notary-result.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :status' "$build/notary-result.plist")" == Accepted ]] || {
        echo "Apple did not accept this artifact for notarization." >&2
        return 1
    }
}
