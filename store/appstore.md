# App Store metadata

Use for Feel (iPhone) only. Limits: name 30, subtitle 30, keywords 100, promo text 170, description 4000.

## Feel Player (Mac)

Not on the App Store. Ships on GitHub Releases. See docs/mac-release.md.

## Feel (iPhone)

- Bundle ID: com.feelplayer.phone
- Category: Entertainment (secondary: Utilities)
- Name: Feel: Video Haptics
- Subtitle: Feel the video on your phone
- Keywords: haptic,haptics,vibration,video,player,mac,sync,touch,feel,core haptics,ahap
- Promo text: Join your Mac, press play, and feel the video in your hand. No account. No ads. No tracking.
- Description:
  Feel turns a video into touch. Join Feel Player or Feel Editor on your Mac, press play, and your iPhone plays haptics in time with the video.

  - Scan the QR code on your Mac to join.
  - Use more than one phone at the same time.
  - Play a video with haptics on the phone alone.
  - Uses Core Haptics. Needs an iPhone with a Taptic Engine.
  - No account. No ads. No tracking.
- Age rating: 4+
- Price: Free

## URLs

- Support URL: https://github.com/7angle/feel
- Marketing URL: https://7angle.github.io/feel/
- Privacy policy URL: https://github.com/7angle/feel/blob/main/PRIVACY.md
- EULA: Apple standard, or https://github.com/7angle/feel/blob/main/TERMS.md

## App Privacy (App Store Connect)

- Feel (iPhone): feedback is optional and sent to FeedbackJar only on Send. Answer in App Store Connect:
  - Data types: Other User Content (feedback text), Device ID is not used. Email/Name only if typed (Contact Info).
  - Purpose: App Functionality. Linked to identity: No unless user types email. Tracking: No.
  - Check with the FeedbackJar SDK privacy manifest before you answer.

## Export compliance

ITSAppUsesNonExemptEncryption = NO is set in Info.plist. Check: the apps use TLS-PSK (Network.framework). This is standard OS encryption, so it is exempt under the standard-encryption exemption. Confirm in App Store Connect.

## Review notes (paste to App Review)

Feel Player (Mac) plays a video that the user opens. It sends haptics to phones on the local network. To test, you need no account.

1. Open Feel Player. Open any video with File > Open.
2. A QR code and a pairing code show in the app.
3. On an iPhone with Feel, tap Scan and scan the QR code. The phone joins. Press play on the Mac. The phone vibrates.

Local network permission is needed to find and join the Mac. Camera permission is needed to scan the QR code. Both are used only for this. The apps collect no data. Feedback is optional.

If no iPhone is at hand, the Mac app plays video and shows the QR code without a phone. Haptics need a physical iPhone (simulator has no Taptic Engine).

## Screenshots needed

- iPhone: 6.9" (1320x2868) and 6.5". Show join, playing, and haptic view.

## Before submit

- Set DEVELOPMENT_TEAM in project.yml. Bump CURRENT_PROJECT_VERSION for each upload.
- Run `bash ~/.claude/hooks/app-store-compliance-guard.sh .`
- Note on AGPL: 7 Angle owns the copyright, so it may ship under App Store terms. Outside Contributions need the CLA (CLA.md).
