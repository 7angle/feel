# Add haptics to an iOS app

You do not have to install a library. The exported file contains all of the code.

1. Export with the **Swift playback code** format. See [Export haptics](export.md).
2. Add `FeelHapticVideoSync.swift` and `<project>.ahap` to your app target in Xcode.
3. Create the sync object. Use the name of your file, without the extension:

   ```swift
   let player = AVPlayer(url: videoURL)
   let haptics = try HapticVideoSync(player: player, resource: "<project>")
   player.play()
   ```

4. Keep a strong reference to `haptics` while the video plays. If you do not keep a reference, the haptics stop.

The haptics follow play, pause, seek, and rate changes. Use `HapticVideoSync.isSupported` to find out if the device has Core Haptics.
