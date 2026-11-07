# Feel Player

Design haptics that match a video. Edit on Mac, feel it on your phone.

- **Mac editor** (SwiftUI): import video, edit a haptic timeline, use presets, auto-suggest haptics from video and audio, export.
- **iPhone companion** (Core Haptics): joins the Mac over the local network and plays haptics in sync.
- **Android companion** (Kotlin, Compose): same, with the device vibrator.
- **Export**: AHAP, JSON, and Swift playback code.

Status: early. Tested on a Pixel 6a. Not yet validated on a real iPhone or with many phones at once.

## Layout

| Path | What |
| --- | --- |
| `Packages/FeelCore` | Shared Swift package: models, timebase, presets, export, protocol. |
| `Apps/FeelMac` | macOS app. |
| `Apps/FeelPhone` | iOS companion. |
| `Apps/FeelAndroid` | Android companion. |
| `project.yml` | XcodeGen spec for the Xcode project. |

## Build

Needs macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Feel.xcodeproj
```

Pick the `FeelMac` or `FeelPhone` scheme. Set your own signing team and bundle IDs in `project.yml` to run on a device.

Run core tests:

```sh
cd Packages/FeelCore && swift test
```

Android: open `Apps/FeelAndroid` in Android Studio, or run `./gradlew assembleDebug`.

## Use

1. Start the Mac app and import a video.
2. Phone and Mac must be on the same network. Scan the QR code in the Mac app with the phone app.
3. Edit the timeline. The phone plays haptics in sync with the video.
4. Export when done.

The link between devices uses TLS-PSK. The pairing code is in the QR code.

## Notes

- Videos are referenced, never copied.
- Do not commit videos or projects made from copyrighted media.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

The "Feel" and "Feel Player" names, the app icon, and the bundle IDs belong to the project owner. They are not covered by the AGPL. Forks must use their own name, icon, and bundle IDs.
