# macOS distribution

The macOS release job signs the application and its Safari extension with Developer ID Application and the installer with Developer ID Installer from the same Apple developer team. It submits the ZIP and the installer to Apple, staples the tickets, checks Gatekeeper and validates the packaged files before uploading them.

## From Xcode on a Mac

In Xcode Settings → Accounts, select the developer team and open **Manage Certificates**. Check that both Developer ID identities have their private keys on the signing Mac. Configure a notarytool Keychain profile using the Apple account or App Store Connect credentials for that team. Run from the checkout:

```sh
export CLAWD_NOTARY_PROFILE='your-existing-profile'
bash Scripts/package-mac.sh dist --distribution
```

The script selects the identities automatically when there is one valid match of each type. To choose among several, set `CLAWD_SIGN_IDENTITY` and `CLAWD_INSTALLER_IDENTITY` to the appropriate certificate fingerprints. The resulting PKG installs into Applications. Quit the running older copy and reopen the updated app from Applications after installation.

## GitHub Actions

Configure the following **repository Actions secrets**. The signing job imports them into a temporary keychain on the hosted Mac. Keep exports and private keys outside the checkout.

| Secret | Contents |
| --- | --- |
| MACOS_CERTIFICATES_P12 | A base64-encoded PKCS#12 export containing both identities and their private keys |
| MACOS_CERTIFICATES_PASSWORD | Password for the PKCS#12 export |
| MACOS_NOTARY_P8 | The PEM contents of the App Store Connect team API private key |
| MACOS_NOTARY_KEY_ID | App Store Connect API key ID |
| MACOS_NOTARY_ISSUER | Team API issuer UUID |

Pull requests use the local test build. Distribution builds require signing credentials. After configuring secrets, rerun failed jobs for the release commit.

## Updating an existing installation

Earlier ad-hoc builds open the package download in the browser. Install the first Developer ID release manually from the project release page. Signed builds offer **Install update**, check the installer against their own team and ask macOS Installer to open it. Homebrew installations can also use `brew upgrade --cask clawd-companion`.
