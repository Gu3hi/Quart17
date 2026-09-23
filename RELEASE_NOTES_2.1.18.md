# Quart17 2.1.18

## 中文

- 锁屏通知固定使用深色外观，避免系统浅色模式下折叠通知出现黑块；桌面横幅保持独立外观。
- 桌面横幅与锁屏通知共用模糊、背景折射和高光调节。移除“锁屏玻璃与底色”中效果不明确的三个滑块。
- 在玻璃参数页加入常驻测试横幅，可从页面或横幅本身关闭。它使用桌面玻璃绘制逻辑，不会写入通知中心。
- 拖动三个玻璃滑块时持续更新测试横幅，松手后保存最终数值，无需重新打开横幅。
- 按当前功能重新排列设置分组，补充中英文提示。

## English

- Lock Screen cards keep a dark appearance to avoid black folded stacks in system light mode. Desktop banners retain their own appearance.
- Desktop banners and Lock Screen cards share blur, backdrop refraction, and highlight controls. Removed the three ambiguous Lock Screen tint and opacity sliders.
- Added a persistent test banner to the Glass settings page. It uses the desktop glass renderer, can be closed there or on the banner, and does not enter Notification Center.
- Dragging any of the three glass sliders updates the test banner live; releasing saves the final value without reopening it.
- Reorganized settings around the current features and updated Chinese and English guidance.

RootHide: `iphoneos-arm64e` · Standard rootless: `iphoneos-arm64` · Target: iOS 17
