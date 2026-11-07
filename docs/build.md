# Build

## Apple apps

You must have a Mac with macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Feel.xcodeproj
```

Select one of these schemes:

| Scheme | App |
| --- | --- |
| `FeelEditor` | Feel Editor |
| `FeelPlayer` | Feel Player |
| `FeelPhone` | Feel for iPhone |

To run an app on a device, set your signing team and bundle IDs in `project.yml`. Then generate the project again.

## Android app

You must have JDK 17 and the Android SDK. Open `Apps/FeelAndroid` in Android Studio, or use this command:

```sh
cd Apps/FeelAndroid && ./gradlew assembleDebug
```

## Tests

```sh
# Shared Swift package
cd Packages/FeelCore && swift test

# Android app
cd Apps/FeelAndroid && ./gradlew test
```
