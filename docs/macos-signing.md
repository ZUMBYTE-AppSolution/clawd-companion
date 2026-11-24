# Sign and publish a macOS release

## Sign with Xcode on your Mac

Open `ClawdCompanion.xcodeproj` in Xcode 16 or later. In **Xcode → Settings → Accounts**, select the account with access to Zumbyte’s developer team (`J97L2NDXQR`). The shared `ClawdCompanion` scheme builds the app and its Safari extension for Apple silicon and Intel. Both targets use automatic signing.

Choose **Product → Archive**. In Organizer select the archive, then **Distribute App → Direct Distribution** to sign with Developer ID and submit for notarization. Export the app after Apple accepts it. The account needs permission to use the team’s cloud-managed Developer ID certificate. [Apple’s cloud signing guide](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)

Package the app you exported in Organizer into a Homebrew ZIP and a drag-to-install DMG. Run this command from the source checkout, with the full path to your export.

```sh
CLAWD_EXPORTED_APP="/path/to/Clawd Companion.app" bash Scripts/package-mac.sh dist --distribution
```

To archive, sign, notarize and package in one terminal command, run `bash Scripts/package-mac.sh dist --distribution` in a session where Xcode can access the team account.

The packaging script verifies the Developer ID team, both architectures, Gatekeeper acceptance and the notarization ticket on the app. A locally configured notarytool profile (`CLAWD_NOTARY_PROFILE`) can also notarize the outer DMG. When that authentication and a matching **Developer ID Installer** identity are available, the script produces a signed, notarized PKG as well.

## Publish a locally signed build

From the exact `main` commit you built, stage its signed packages in a GitHub release draft. The following commands use the GitHub CLI from an authenticated maintainer checkout.

```sh
version=$(cat VERSION)
tag="v$version"
base="dist/Clawd-Companion-$version-macOS-universal"
gh release create "$tag" --draft --target "$(git rev-parse HEAD)" --title "Claw’d Companion $version" --notes-file "docs/releases/$version.md"
gh release upload "$tag" "$base.zip" "$base.dmg"
if test -f "$base.pkg"; then gh release upload "$tag" "$base.pkg"; fi
gh workflow run release.yml --ref main -f use_signed_draft=true
```

The workflow matches the draft to the selected commit, verifies the Mac artifacts, builds and tests the other platforms, publishes the release and updates the Homebrew cask. This route uses the Apple account on the signing Mac and GitHub’s repository token on the runner.

## Sign on GitHub Actions

The hosted Mac starts with its own Xcode installation. To let this runner sign for the team, configure these repository Actions secrets with an App Store Connect team key authorized for cloud signing and notarization.

| Secret | Value |
| --- | --- |
| `MACOS_NOTARY_P8` | PEM contents of the App Store Connect private key |
| `MACOS_NOTARY_KEY_ID` | Key ID |
| `MACOS_NOTARY_ISSUER` | Team issuer ID |

For an additional flat PKG from the hosted runner, supply the optional `MACOS_CERTIFICATES_P12` (base64-encoded Developer ID Installer identity) and `MACOS_CERTIFICATES_PASSWORD` secrets. Keep private keys out of the repository.

## Upgrade an installation

Homebrew users can get the latest published release as follows.

```sh
brew update
brew upgrade --cask zumbyte/clawd/clawd-companion
```

For an older ad-hoc installation, quit Claw’d, open the first Developer ID release’s DMG and drag the app into Applications. Future signed versions can check the publisher and version of a downloaded DMG before showing the app in Finder. If the release includes a signed PKG, the updater verifies its publisher and opens macOS Installer.
