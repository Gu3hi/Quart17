# Quart17

## 中文

Quart17 为越狱版 iOS 17 提供通知与锁屏播放器样式。提供 RootHide 和标准 rootless 安装包，均包含 arm64 与 arm64e 代码。

### 功能

- 调整锁屏通知列表大小、通知卡片与播放器圆角；可单独开启桌面横幅缩放。
- 为锁屏通知和桌面横幅加入液态玻璃外观，可调节模糊、折射与边缘高光。玻璃设置页提供常驻测试横幅，拖动滑块即可预览。
- 锁屏手电筒和相机保留原生图标与操作，并可使用与通知相近的玻璃外观。
- 锁屏右半屏空白处连续两次下滑可清除普通通知，保留音乐控件与实时活动；左半屏下滑打开系统搜索。清除时可开启轻震动。
- 锁屏播放器可选 Quart 原风格或液态玻璃外观。可自定义播放控制图标，并在背景、文字和进度上使用封面颜色。
- 播放进度可选择卡片背景、底部横条或小封面环形进度条；支持拖动调整进度。
- 点击小封面可使用系统动画展开原生大封面。大封面保留原生背景与交互，并提供独立的大小、圆角和封面外侧环形进度条；展开后仍可在播放器上调整进度。点击歌名可打开当前播放 App。
- 设置页面提供中文与英文说明、总开关及不打断播放的样式刷新。

### 安装

从 [Releases](https://github.com/Gu3hi/Quart17/releases) 下载对应的 `.deb`：RootHide 使用 `iphoneos-arm64e`，标准 rootless 使用 `iphoneos-arm64`。通过兼容的包管理器安装；首次安装后重启 SpringBoard。

### 自定义按钮图标

可替换 `previous.png`、`play.png`、`pause.png` 和 `next.png`，放在越狱根目录下的 `/Library/Application Support/Quart17/Buttons/`。实际设备路径可在「设置 → Quart17 → 按钮图标目录」中查看。替换后点击设置页右上角「刷新」。未提供图片时会使用内置图标；隐藏控制按钮时，触控区域和播放操作仍然保留。

### 构建

需要 Theos、iOS SDK 和相应的打包方案。

```sh
export THEOS="$HOME/theos"
make package FINALPACKAGE=1

# 标准 rootless
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless DEB_ARCH=iphoneos-arm64
```

设置图标取自用户提供的 Quart 1.4.6.1 安装包，版权属于原作者，不包含在本项目许可证内。播放器与通知实现为本项目独立代码。

作者：[@Put_Story](https://x.com/Put_Story)

致敬 [@LaughingQuoll](https://x.com/LaughingQuoll)，永远怀念最好的开发者。

---

## English

Quart17 styles notifications and the Lock Screen player on jailbroken iOS 17. RootHide and standard rootless packages are available; both contain arm64 and arm64e code.

### Features

- Adjust the Lock Screen notification list size and the shared corners of notification cards and the player. Desktop banner scaling is optional.
- Apply Liquid Glass styling to Lock Screen notifications and desktop banners, with adjustable blur, refraction, and edge highlights. A persistent test banner previews changes as the sliders move.
- Keep the native flashlight and camera icons and actions while giving their buttons a matching glass appearance.
- Swipe down twice from empty space on the right half of the Lock Screen to clear ordinary notifications while keeping media controls and Live Activities. Swipe down on the left to open system Search. Clearing can trigger a light haptic.
- Choose the original Quart or Liquid Glass player. Playback controls can use custom icons, while the background, text, and progress can draw colors from the artwork.
- Choose one of three seekable progress styles: card background, bottom bar, or a ring around the compact artwork.
- Tap the compact artwork to expand the native system cover with its native animation, background, and interaction. Expanded artwork has separate size and corner controls and an outer progress ring. Seeking remains available on the player; tap the song title to open the playing app.
- Chinese and English settings include a master switch and a style refresh that keeps audio playing.

### Install

Download the matching `.deb` from [Releases](https://github.com/Gu3hi/Quart17/releases): `iphoneos-arm64e` for RootHide or `iphoneos-arm64` for standard rootless. Install with a compatible package manager. Restart SpringBoard after the first installation.

### Custom control icons

Replace `previous.png`, `play.png`, `pause.png`, and `next.png` under `/Library/Application Support/Quart17/Buttons/` in the jailbreak root. Settings → Quart17 → Button icon folder shows the actual device path. Tap Refresh in Settings after replacing a file. Missing files use built-in icons. Hiding playback buttons leaves their touch areas and actions available.

### Build

Theos, an iOS SDK, and the relevant packaging scheme are required.

```sh
export THEOS="$HOME/theos"
make package FINALPACKAGE=1

# Standard rootless
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless DEB_ARCH=iphoneos-arm64
```

The settings icon comes from a user supplied Quart 1.4.6.1 package. It belongs to its original creator and is not covered by this project's license. The player and notification implementation is independent.

Author: [@Put_Story](https://x.com/Put_Story)

In tribute to [@LaughingQuoll](https://x.com/LaughingQuoll). Forever remembering the best developer.
