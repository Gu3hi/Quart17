# Quart17

iOS 17 锁屏播放器与通知样式插件 / Lock Screen Player & Notification Styling for iOS 17

### 当前源码的播放器架构 / Player ownership in current source

紧凑播放器在 `com.apple.MediaRemoteUI` 的 `MRUCoverSheetView` 内创建，限定于通知列表场景 `ActivitySceneSessionRoleListItem`。SpringBoard 负责通知列表缩放和已识别媒体宿主的外层材质，不再创建播放器覆盖层。设置读取、原生大封面与播放控制沿用现有实现；播放器刷新跟随所在场景的生命周期。

The compact player renders inside MediaRemoteUI's native Now Playing view, scoped to the notification list scene. SpringBoard handles list scaling and the verified media host's outer material, without creating a player overlay. Shared settings, native artwork and playback controls are retained, with refresh tied to the player's own scene.

2.7.112 已采用该架构。RootHide 版本经用户真机测试确认；rootless 已构建并完成包检查，尚未在真机测试。

Version 2.7.112 uses this architecture. The user confirmed device testing for RootHide. The rootless package has been built and inspected but has not been tested on a device.

## 简介 / Introduction

Quart17 为 iOS 17 越狱设备带来全新的锁屏音乐播放器与通知中心体验。自 2.1 版本起，玻璃拟态效果已拆分至独立插件 **Aura**，Quart17 专注于播放器功能、通知排版与手势交互。

Quart17 brings a brand-new lock screen music player and notification experience to jailbroken iOS 17 devices. Since v2.1, glassmorphism effects have been split into the standalone tweak **Aura** — Quart17 now focuses on player functionality, notification layout, and gesture interactions.

> **注意 / Note**: 如需玻璃拟态效果，请同时安装 [Aura](https://github.com/Gu3hi/Aura-Releases/releases)（`com.gushi.aura`）。两者不可同时接管同一表面，Aura 负责所有玻璃渲染。
> To get glassmorphism effects, install [Aura](https://github.com/Gu3hi/Aura-Releases/releases) (`com.gushi.aura`) alongside. The two tweaks must not take over the same surfaces — Aura handles all glass rendering.

## 功能 / Features

### 锁屏播放器 / Lock Screen Player
- 全屏专辑封面展示，支持缩放与位置调整
- Full-screen album artwork with scale and position controls
- 播放/暂停、上一曲/下一曲快捷操作
- Play/pause and skip controls
- 播放进度显示
- Playback progress display

### 通知管理 / Notifications
- 通知缩放（QScale）：自定义通知卡片大小
- Notification scaling (QScale): customize notification card size
- 通知排版优化（QNotifications）：更清晰的通知列表布局
- Notification layout (QNotifications): cleaner notification list arrangement
- 下拉清理手势（QMasterGesture）：下拉手势快速清理通知
- Pull-to-clear gesture (QMasterGesture): quickly clear notifications with a pull gesture

### 手势 / Gestures
- 锁屏下拉清理通知
- Pull down on lock screen to clear notifications

## 安装要求 / Requirements

- 当前 2.8 构建最低系统为 iOS 17；旧版 iOS 16 兼容记录不代表本版支持。
- Version 2.8 requires iOS 17. Historical iOS 16 compatibility does not apply to this release.
- 越狱环境：Dopamine 2.x / RootHide（主要测试环境为 Relaxin 越狱 + RootHide）
- Jailbreak: Dopamine 2.x / RootHide (primarily tested on Relaxin jailbreak + RootHide)
- 架构：arm64 / arm64e
- Architecture: arm64 / arm64e

## 安装包 / Packages

| 环境 / Environment | 文件 / File |
|---|---|
| RootHide | `com.gushi.quart17_<ver>_iphoneos-arm64e.deb` |
| 标准 Rootless / Standard Rootless | `com.gushi.quart17_<ver>_iphoneos-arm64.deb` |

从 [Releases](https://github.com/Gu3hi/Quart17/releases) 页面下载对应环境的安装包，使用 Filza 或 Sileo 安装。

Download the package for your environment from the [Releases](https://github.com/Gu3hi/Quart17/releases) page and install with Filza or Sileo.

## 设置 / Settings

安装后在「设置」中找到 Quart17 进行配置：
- 播放器：封面样式、控件布局
- 通知：缩放比例、排版选项
- 手势：下拉清理与触感开关

After installation, find Quart17 in Settings to configure:
- Player: artwork style, control layout
- Notifications: scale ratio, layout options
- Gestures: pull-to-clear and haptic toggles

## 与 Aura 的配合 / Working with Aura

| 功能 | 归属 |
|---|---|
| 锁屏/通知/控制中心/桌面/弹窗的玻璃效果 | **Aura** |
| 播放器功能、通知排版缩放、清理手势 | **Quart17** |

**不要同时安装两个都能渲染玻璃的版本**，否则会冲突。2.1 基线之后的 Quart17 已移除所有玻璃代码。

**Do not install two versions that both render glass** — they will conflict. Quart17 after the 2.1 baseline has removed all glass code.

## 版本历史 / Changelog

### 2.8 · 2026-10-28
- 调整锁屏紧凑播放器居中布局，并放宽媒体宿主背景的尺寸限制。此版本尚待真机验证。
- Center the compact lock-screen player and remove fixed-size limits from media host background detection. Device validation is pending.

### 2.7.112 · 2026-10-26
- 紧凑播放器移至 MediaRemoteUI 的通知列表场景，按媒体身份识别宿主，避免覆盖普通实时活动。
- Move the compact player into MediaRemoteUI's notification list scene and identify media hosts without replacing ordinary Live Activities.
- 进度拖动接入原生 seek 方法；支持背景、底部条和封面环三种进度样式，并调整斜向起拖识别。
- Use native seeking; support background, bottom-bar and artwork-ring progress styles, with improved diagonal drag recognition.
- 修复隐藏播放/输出按钮、四种封面取色及紧凑播放器圆角的跨进程设置同步。
- Fix cross-process settings for playback/output button visibility, four artwork color options and compact player corners.
- 关闭通知样式时恢复原生通知大小并隐藏计数，修正设置说明。
- Restore native notification sizes and hide counts when notification styling is disabled; correct the setting description.
- RootHide 经用户测试确认；双包均独立构建并验包，rootless 尚未真机测试。
- RootHide testing was confirmed by the user. Both packages are independently built and inspected; rootless device testing remains pending.

### 2.7.96
- 拆分版：播放器功能独立，玻璃效果迁移至 Aura
- Split version: player functionality standalone, glass effects moved to Aura
- 设置页视觉刷新（DESIGN.md 规范）
- Preferences UI refresh (DESIGN.md spec)

## 开源协议 / License

MIT License — 详见 LICENSE 文件。

## 致谢 / Credits

作者 / Author: [@Put_Story](https://github.com/Gu3hi)

致敬 [@LaughingQuoll](https://github.com/LaughingQuoll) —— 原 Quart 插件的作者。
永远怀念最好的开发者。

In tribute to [@LaughingQuoll](https://github.com/LaughingQuoll) — the original author of the Quart tweak.
Forever remembering the best developer.
