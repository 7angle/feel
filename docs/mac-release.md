# Mac release (GitHub)

Feel Editor and Feel Player ship as notarized DMG files on GitHub Releases. Only Feel for iPhone ships on the App Store.

## Install (users)

1. Download `feel-editor-<version>.dmg` or `feel-player-<version>.dmg` from [Releases](https://github.com/7angle/feel/releases).
2. Open the DMG. Drag the app to Applications.

The apps are signed with a Developer ID and notarized by Apple. macOS opens them without a warning.

## One-time setup (maintainer)

You need a paid Apple Developer Program account.

1. Make a **Developer ID Application** certificate (Xcode > Settings > Accounts > Manage Certificates). Export it as `.p12` with a password.
2. Make an App Store Connect API key (Users and Access > Integrations > Keys). Download the `.p8` file. Note the key ID and the issuer ID.
3. Add GitHub secrets:
   - `MAC_CERT_P12_BASE64`: `base64 -i cert.p12`
   - `MAC_CERT_PASSWORD`
   - `MAC_TEAM_ID`: your 10-character team ID
   - `MAC_NOTARY_KEY_P8`: the full text of the `.p8` file
   - `MAC_NOTARY_KEY_ID`
   - `MAC_NOTARY_ISSUER_ID`

## Make a release

```
git tag mac-v1.0.0
git push origin mac-v1.0.0
```

The workflow `.github/workflows/mac-release.yml` builds both apps. It signs them and notarizes them. It staples the ticket, makes the DMG files, and attaches them to the release.

## Notes

- The Android and Mac releases use different tag prefixes (`android-v*`, `mac-v*`). Obtainium for Android uses the filter in `android-release.md`, so Mac files do not matter there.
- The Mac apps keep the App Sandbox. Developer ID apps do not need it, but it limits damage.
- Mac App Store is not used. Remove the Mac apps from the store listing plan (`store/appstore.md`).
