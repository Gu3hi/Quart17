# Quart17 2.1.0

## 中文

- 恢复锁屏左半屏下拉打开系统搜索；右半屏仍保留连续两次下滑清除普通通知。
- 修复浏览大量通知时误触清除：清除手势需要从右半屏空白处开始、完成两次明确下滑；通知列表滚动不计入。
- 新增桌面横幅等比例缩放开关，使用锁屏通知列表的大小设置。
- 桌面横幅和锁屏普通通知可共用玻璃效果；二级设置页可分别调节模糊、边缘折射和高光。折射使用 iOS 17 可用的背景网格，缺失时回退到系统模糊。
- 更新中英文设置说明，移除缩放调试文件写入。

## English

- Restored system Search when swiping down on the left half of the Lock Screen. Two downward swipes on the right half still clear ordinary notifications.
- Prevented accidental clearing while browsing long notification lists. Clearing now requires two completed swipes starting from empty space on the right; scrolling notification cards does not count.
- Added optional proportional scaling for desktop notification banners, using the Lock Screen list size setting.
- Added shared glass styling for desktop banners and ordinary Lock Screen notifications. Blur, edge refraction, and highlights have separate controls on a secondary settings page. The iOS 17 backdrop mesh is used when available, with a system blur fallback.
- Updated Chinese and English settings text and removed scale diagnostic file writes.

RootHide: `iphoneos-arm64e` · Standard rootless: `iphoneos-arm64` · Target: iOS 17
