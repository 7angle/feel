# Android release (GitHub + Obtainium)

The Android app ships as a signed APK on GitHub Releases. Users install and update it with [Obtainium](https://obtainium.imranr.dev/).

## Install (users)

1. Install Obtainium.
2. In Obtainium, tap **Add App**.
3. Enter the source URL: `https://github.com/7angle/feel`
4. Open **Additional options**. Set **Filter APKs by regular expression** to `^feel-android-.*\.apk$`. Set **Include prereleases** off.
5. Tap **Add**, then **Install**.

Obtainium checks GitHub Releases and updates the app. Obtainium reads the release tag as the version. Tags look like `android-v1.0.0`.

## Make a release (maintainer)

One time:

1. Make a keystore. Keep it safe. If you lose it, users cannot update.
   ```
   keytool -genkeypair -v -keystore feel-release.jks -alias feel -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Add GitHub secrets: `ANDROID_KEYSTORE_BASE64` (`base64 -i feel-release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
3. Do not commit the keystore.

Each release:

1. Raise `versionCode` in `Apps/FeelAndroid/app/build.gradle.kts`. It must go up for each release.
2. Commit. Then tag and push:
   ```
   git tag android-v1.0.0
   git push origin android-v1.0.0
   ```
3. The workflow `.github/workflows/android-release.yml` builds the APK. It signs it and attaches `feel-android-<version>.apk` and a SHA-256 file to the release.

The app version name comes from the tag. The same key must sign every release.

## Notes

- This is not Google Play. No Play policy review applies to GitHub builds. The privacy policy still applies.
- The app uses the Google Play services code scanner. On a phone without Play services, the QR scan can fail.
