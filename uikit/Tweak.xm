// Quart17UIKit - 应用进程通用弹窗玻璃
// 注入所有链接 UIKit 的应用进程，为 UIAlertController / 操作表提供玻璃效果。
// 与 SpringBoard dylib 完全独立，互不影响。

#import <UIKit/UIKit.h>
#import "../shared/QGlassCore.h"
#import <objc/runtime.h>
extern void QRefreshComponents(void);

%group QSystemAlerts

%hook _UIAlertControllerView

- (void)didMoveToWindow {
    %orig;
    QGlassStyleSystemAlert((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    QGlassStyleSystemAlert((UIView *)self);
}

%end

%hook UIAlertController

- (void)viewDidLayoutSubviews {
    %orig;
    QGlassStyleSystemAlert(((UIViewController *)self).view);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    UIViewController *controller = (UIViewController *)self;
    if (controller.isViewLoaded) QGlassRestoreSystemAlert(controller.view);
}

%end

%end

%group QSystemContextMenus

%hook _UIContextMenuListView

- (void)didMoveToWindow {
    %orig;
    QGlassStyleSystemAlert((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    QGlassStyleSystemAlert((UIView *)self);
}

%end

%end

static void QUIKitSettingsChanged(CFNotificationCenterRef center, void *observer,
    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        QGlassLoadSettings();
        QGlassRefreshAlerts();
        QRefreshComponents();
    });
}

%ctor {
    @autoreleasepool {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier;
        // SpringBoard 由主 dylib 处理，避免双重注入
        if ([bid isEqualToString:@"com.apple.springboard"] ||
            [bid isEqualToString:@"com.apple.MediaRemoteUI"]) return;
        QGlassLoadSettings();
        // 监听设置变化
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            QUIKitSettingsChanged,
            CFSTR("com.gushi.quart17/preferenceschanged"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // 只在有弹窗类时初始化（所有 UIKit 应用都有）
        if (objc_getClass("_UIAlertControllerView")) %init(QSystemAlerts);
        if (objc_getClass("_UIContextMenuListView")) %init(QSystemContextMenus);
    }
}
