# Quart17

Quart inspired Lock Screen player and notification styling for iOS 17. RootHide and standard rootless packages are available. Both include arm64 and arm64e code slices. iOS 16, iOS 18, and other environments have not been verified.

## Features

- Capsule Lock Screen player with circular artwork, a clockwise progress ring, scrolling title and artist, playback controls, and seekable progress.
- Artwork colors for the player background, text, and progress.
- Dark notification cards and round application icons.
- Chinese and English settings, with a master switch and live style refresh that keeps audio playing.

## Install

Download the matching `.deb` from [Releases](https://github.com/Gu3hi/Quart17/releases): `iphoneos-arm64e` for RootHide, or `iphoneos-arm64` for standard rootless. Install it with a compatible package manager. Restart SpringBoard when installing the tweak for the first time.

## Build

Requires Theos, an iOS SDK, and the RootHide package scheme:

```sh
export THEOS="$HOME/theos"
make package FINALPACKAGE=1

# Standard rootless package
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless DEB_ARCH=iphoneos-arm64
```

The source uses the original Quart settings icon from the user supplied Quart 1.4.6.1 package. That icon belongs to its original creator and is not covered by this project's license. The player and notification implementation is independent.

## Credits

Author: [@Put_Story](https://x.com/Put_Story)

致敬 [@LaughingQuoll](https://x.com/LaughingQuoll)<br>
永远怀念最好的开发者。

In tribute to [@LaughingQuoll](https://x.com/LaughingQuoll)<br>
Forever remembering the best developer.
