# Add haptics to an Android app

You do not have to install a Feel library. The exported file contains all of the code. Your app must use Media3 to play the video.

1. Export with the **Kotlin playback code** format. See [Export haptics](export.md).
2. Copy `FeelHapticVideoSync.kt` to your source folder. Use this folder:

   ```text
   app/src/main/java/com/feelplayer/haptics/
   ```

3. Copy `<project>.json` to the assets folder. If the folder does not exist, create it:

   ```text
   app/src/main/assets/
   ```

4. In `app/build.gradle.kts`, add Media3:

   ```kotlin
   dependencies {
       implementation("androidx.media3:media3-exoplayer:1.8.0")
   }
   ```

5. In `AndroidManifest.xml`, add this permission:

   ```xml
   <uses-permission android:name="android.permission.VIBRATE" />
   ```

6. Import the class in your activity:

   ```kotlin
   import com.feelplayer.haptics.HapticVideoSync
   ```

7. Create the sync object after you create the player. Use the full name of your file, with the extension:

   ```kotlin
   val player = ExoPlayer.Builder(this).build()
   val haptics = HapticVideoSync.fromAsset(this, player, "<project>.json")

   player.setMediaItem(MediaItem.fromUri(videoUri))
   player.prepare()
   player.play()
   ```

8. Keep a reference to `haptics` while the video plays.
9. When you close the screen, release the two objects in this sequence:

   ```kotlin
   haptics.release()
   player.release()
   ```

The haptics follow play, pause, buffering, seek, and speed changes. If the file is not a Feel haptics file, `fromAsset` throws `IllegalArgumentException`. If the file does not contain valid JSON, or does not have a list of events, `fromAsset` throws `JSONException`. If the file is not in the assets folder, `fromAsset` throws `FileNotFoundException`. Use `haptics.isSupported` to find out if the device has a vibration motor.

> [!NOTE]
> The **Media vibration** setting on the device controls the strength of these haptics. If the user sets it to off, the haptics do not operate. On a Pixel, this setting is in **Settings > Sound & vibration > Vibration & haptics**. The name and location can be different on other devices.

A system vibration, such as a touch vibration, can stop the haptics for a maximum of 1.5 seconds. The haptics then start again automatically.
