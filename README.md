# Quart17

Quart inspired Lock Screen player and notification styling for iOS 17. RootHide and standard rootless packages are available. Both include arm64 and arm64e code slices. iOS 16, iOS 18, and other environments have not been verified.

## Features

- Capsule Lock Screen player with circular artwork, scrolling title and artist, playback controls, and three exclusive seekable progress styles: player background, bottom bar, or clockwise artwork ring.
- Artwork colors for the player background, text, and progress.
- Dark notification cards and round application icons.
- Adjustable Lock Screen notification list size that scales cards, spacing, and group headings together.
- On the Lock Screen, two downward swipes on the right half clear ordinary notifications while preserving media controls and Live Activities. The left half does not open Search. Clearing can give a light haptic response.
- Chinese and English settings, with a master switch and live style refresh that keeps audio playing.
- One corner slider controls the player, background progress fill, artwork, and artwork progress ring. The playback placeholder follows the current system language.
- Dark mode dims the player background while keeping progress visible. The artwork ring seeks with the same left-to-right drag direction as the background progress style.
- The two size sliders use dedicated rows with a title, value, and unobstructed track.

The four control icons are replaceable PNG files at `/Library/Application Support/Quart17/Buttons/previous.png`, `play.png`, `pause.png`, and `next.png` under the jailbreak root. Use Settings → Quart17 → Button icon folder to see and copy the actual device path, which is randomized on RootHide and normally starts with `/var/jb` on standard rootless systems. Replace a file and use Settings → Quart17 → Refresh to reload it. PNG files are scaled to the control size and tinted to match the player; if a file is absent, the built-in outline remains available. Pause shows a square while playback is active; play shows a circle when paused.

The “Hide playback buttons” switch removes their icons while keeping the three touch areas and playback actions active.

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
