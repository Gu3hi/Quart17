# Quart17

iOS 17 锁屏播放器与通知样式插件 / Lock Screen Player & Notification Styling for iOS 17

## 简介 / Introduction

Quart17 为 iOS 17 越狱设备带来全新的锁屏音乐播放器与通知中心体验。自 2.1 版本起，玻璃拟态效果已拆分至独立插件 **Aura**，Quart17 专注于播放器功能、通知排版与手势交互。

Quart17 brings a brand-new lock screen music player and notification experience to jailbroken iOS 17 devices. Since v2.1, glassmorphism effects have been split into the standalone tweak **Aura** — Quart17 now focuses on player functionality, notification layout, and gesture interactions.

> **注意 / Note**: 如需玻璃拟态效果，请同时安装 [Aura](https://github.com/Gu3hi/Aura)（`com.gushi.aura`）。两者不可同时接管同一表面，Aura 负责所有玻璃渲染。
> To get glassmorphism effects, install [Aura](https://github.com/Gu3hi/Aura) (`com.gushi.aura`) alongside. The two tweaks must not take over the same surfaces — Aura handles all glass rendering.

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
- 可自定义手势灵敏度
- Customizable gesture sensitivity

## 安装要求 / Requirements

- iOS 17.0 – 17.3.1
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
- 手势：灵敏度、开关

After installation, find Quart17 in Settings to configure:
- Player: artwork style, control layout
- Notifications: scale ratio, layout options
- Gestures: sensitivity, toggles

## 与 Aura 的配合 / Working with Aura

| 功能 | 归属 |
|---|---|
| 锁屏/通知/控制中心/桌面/弹窗的玻璃效果 | **Aura** |
| 播放器功能、通知排版缩放、清理手势 | **Quart17** |

**不要同时安装两个都能渲染玻璃的版本**，否则会冲突。2.1 基线之后的 Quart17 已移除所有玻璃代码。

**Do not install two versions that both render glass** — they will conflict. Quart17 after the 2.1 baseline has removed all glass code.

## 版本历史 / Changelog

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
