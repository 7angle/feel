# Export haptics

1. Start Feel Editor and open your project.
2. In the toolbar, click **Export**.
3. Select one or more formats.
4. Click **Export…**.
5. Select a folder, then click **Export Here**.

Feel Editor writes these files:

| Format | Files | Platform | Use |
| --- | --- | --- | --- |
| AHAP | `<project>.ahap` | iOS | Play the pattern with Core Haptics. There is no video sync. |
| JSON | `<project>.json` | iOS, Android | Open the file in Feel for iPhone or Feel for Android. |
| Swift playback code | `FeelHapticVideoSync.swift`, `<project>.ahap` | iOS 16 or later | Add haptics to your iOS app. Sync with `AVPlayer`. See [iOS integration](ios.md). |
| Kotlin playback code | `FeelHapticVideoSync.kt`, `<project>.json` | Android 8.0 (API 26) or later | Add haptics to your Android app. Sync with a Media3 player. See [Android integration](android.md). |

> [!WARNING]
> Export replaces files that have the same name in the selected folder. Export the haptics to an empty folder if you must keep the old files.

Export stops if the project has no events, or if an event has an invalid number. Export continues, and shows a warning, if:

- An event starts after the video ends, or continues after the video ends.
- An event has zero intensity.
- The project has no video.
