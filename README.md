<p align="center">
  <img width="128" height="128" src="src/Assets.xcassets/AppIcon.appiconset/icon_512x512.png">
</p>

# NetSpeedMonitorSwift

A minimal menu bar network speed monitor for macOS.

Shows upload and download speeds for the most active `en*` or `utun*` interface,
with stable switching and a system default fallback when idle. Speeds use 1024-byte
scaling. Unavailable readings show `--` and recover automatically.

Built upon [elegracer/NetSpeedMonitor](https://github.com/elegracer/NetSpeedMonitor) and [byrencheema/airstats](https://github.com/byrencheema/airstats).

## Requirements

- macOS 26.0+
- Apple Silicon (ARM64)

## Installation

Download the app from [GitHub Releases](https://github.com/qvshuo/NetSpeedMonitorSwift/releases/latest), unzip it and move it to **Applications**.

If macOS blocks the first launch, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine "/Applications/NetSpeedMonitorSwift.app"
```

## Build

Requires Xcode 26.0 or later; tested locally with Xcode 27.0.
Open `NetSpeedMonitorSwift.xcodeproj` in Xcode, or build without signing:

```bash
xcodebuild -project NetSpeedMonitorSwift.xcodeproj \
  -scheme NetSpeedMonitorSwift -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

Output: `build/Build/Products/Release/NetSpeedMonitorSwift.app`.
Both Debug and Release build for ARM64 only.

## Screenshot

![Menu bar network speed monitor](./screenshot.png)

## License

[MIT](LICENSE)
