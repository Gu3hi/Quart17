#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import "QPlayerView.h"

static NSString *const QPrefs = @"com.gushi.quart17";
static NSMutableDictionary *qSettings;
static NSHashTable<QPlayerView *> *qActivePlayers;
static NSHashTable<UIView *> *qActivePlatters;
static NSHashTable<UIView *> *qActiveNotifications;
static NSHashTable<UIView *> *qActiveLists;
static void *QOriginalStyleKey = &QOriginalStyleKey;
static void *QOwnLayerTransformKey = &QOwnLayerTransformKey;
static void *QOriginalLayerTransformKey = &QOriginalLayerTransformKey;
static void *QScalePendingKey = &QScalePendingKey;
static void *QScaleDiagnosticKey = &QScaleDiagnosticKey;
static void *QOriginalIndicatorKey = &QOriginalIndicatorKey;
static __weak id qMasterList;
static CFAbsoluteTime qLastRightSwipe;
static void *QSearchPanInstalledKey = &QSearchPanInstalledKey;
static void *QSearchPanCountedKey = &QSearchPanCountedKey;



static void QStyle(UIView *root);
static void QApplyListScaling(UIView *list);
static void QScheduleListScaling(UIView *list);
static void QClearOwnLayerTransform(UIView *list);

@interface NCNotificationShortLookViewController : UIViewController
- (UIView *)viewForPreview;
@end

static void QLoadSettings(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    qSettings = [@{ @"masterEnabled": @YES, @"enabled": @YES, @"darkCards": @NO,
                    @"roundIcons": @YES, @"radius": @24,
                    @"playerEnabled": @YES, @"disableListScaling": @NO,
                    @"clearAllEnabled": @YES, @"clearHapticEnabled": @YES,
                    @"showProgress": @YES, @"backgroundProgress": @YES, @"hideRoute": @YES,
                    @"hideControls": @NO,
                    @"titleFromArtwork": @YES, @"artistFromArtwork": @YES,
                    @"progressFromArtwork": @YES, @"backgroundFromArtwork": @YES } mutableCopy];
    if ([saved isKindOfClass:NSDictionary.class]) [qSettings addEntriesFromDictionary:saved];
    if (!qSettings[@"progressStyle"]) {
        qSettings[@"progressStyle"] = [qSettings[@"backgroundProgress"] boolValue] ? @0 : @1;
    }
    if (!qSettings[@"playerCornerRoundness"]) {
        qSettings[@"playerCornerRoundness"] = saved[@"roundArtwork"] && ![saved[@"roundArtwork"] boolValue] ? @0 : @1;
    }
}

static void QChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                     const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *previous = [qSettings copy];
        QLoadSettings();
        NSMutableDictionary *beforeStyle = [previous mutableCopy];
        NSMutableDictionary *afterStyle = [qSettings mutableCopy];
        for (NSString *key in @[@"widthScale", @"disableListScaling"]) {
            [beforeStyle removeObjectForKey:key];
            [afterStyle removeObjectForKey:key];
        }
        if ([beforeStyle isEqualToDictionary:afterStyle]) {
            for (UIView *list in qActiveLists.allObjects) QScheduleListScaling(list);
            return;
        }
        for (QPlayerView *player in qActivePlayers.allObjects) {
            [player applySettings:qSettings];
            [player refresh];
        }
        for (UIView *platter in qActivePlatters.allObjects) {
            [platter setNeedsLayout];
            [platter layoutIfNeeded];
        }
        for (UIView *notification in qActiveNotifications.allObjects) QStyle(notification);
        for (UIView *list in qActiveLists.allObjects) QScheduleListScaling(list);
    });
}

static void QLaunchPlayingBundle(NSString *bundleID) {
    if (!bundleID.length) return;
    UIApplication *springBoard = UIApplication.sharedApplication;
    SEL launch = @selector(launchApplicationWithIdentifier:suspended:);
    if ([springBoard respondsToSelector:launch]) {
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, launch, bundleID, NO);
    }
}

static void QLaunchAfterUnlock(NSString *bundleID, NSUInteger attempt) {
    Class lockClass = objc_getClass("SBLockScreenManager");
    id manager = [lockClass respondsToSelector:@selector(sharedInstance)]
        ? ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance)) : nil;
    SEL visibleSelector = @selector(isLockScreenVisible);
    BOOL visible = [manager respondsToSelector:visibleSelector]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(manager, visibleSelector) : NO;
    if (!visible) {
        QLaunchPlayingBundle(bundleID);
    } else if (attempt < 60) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ QLaunchAfterUnlock(bundleID, attempt + 1); });
    }
}

static void QOpenPlayingApp(CFNotificationCenterRef center, void *observer, CFStringRef name,
                            const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static CFAbsoluteTime lastOpen = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastOpen < 1.5) return;
        lastOpen = now;
        Class mediaClass = objc_getClass("SBMediaController");
        id media = [mediaClass respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(mediaClass, @selector(sharedInstance)) : nil;
        id playingApp = [media respondsToSelector:@selector(nowPlayingApplication)]
            ? ((id (*)(id, SEL))objc_msgSend)(media, @selector(nowPlayingApplication)) : nil;
        NSString *bundleID = [playingApp respondsToSelector:@selector(bundleIdentifier)]
            ? ((id (*)(id, SEL))objc_msgSend)(playingApp, @selector(bundleIdentifier)) : nil;
        if (!bundleID.length) return;
        Class lockClass = objc_getClass("SBLockScreenManager");
        id manager = [lockClass respondsToSelector:@selector(sharedInstance)]
            ? ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance)) : nil;
        BOOL visible = [manager respondsToSelector:@selector(isLockScreenVisible)]
            ? ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isLockScreenVisible)) : NO;
        if (visible) {
            if ([manager respondsToSelector:@selector(lockScreenViewControllerRequestsUnlock)]) {
                ((void (*)(id, SEL))objc_msgSend)(manager, @selector(lockScreenViewControllerRequestsUnlock));
                QLaunchAfterUnlock(bundleID, 0);
            }
        } else {
            QLaunchPlayingBundle(bundleID);
        }
    });
}

static UIView *QFind(UIView *root, NSString *className) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *child in root.subviews) {
        UIView *match = QFind(child, className);
        if (match) return match;
    }
    return nil;
}

static BOOL QHasAncestor(UIView *view, NSString *className) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview)
        if ([NSStringFromClass(ancestor.class) isEqualToString:className]) return YES;
    return NO;
}

static void QRememberStyle(UIView *view) {
    if (objc_getAssociatedObject(view, QOriginalStyleKey)) return;
    NSDictionary *state = @{
        @"radius": @(view.layer.cornerRadius),
        @"curve": view.layer.cornerCurve ?: kCACornerCurveCircular,
        @"clips": @(view.clipsToBounds),
        @"background": view.backgroundColor ?: (id)NSNull.null,
        @"hidden": @(view.hidden),
        @"textColor": [view isKindOfClass:UILabel.class] ? (((UILabel *)view).textColor ?: (id)NSNull.null) : (id)NSNull.null
    };
    objc_setAssociatedObject(view, QOriginalStyleKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QRestoreStyle(UIView *root) {
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        NSDictionary *state = objc_getAssociatedObject(view, QOriginalStyleKey);
        if (state) {
            view.layer.cornerRadius = [state[@"radius"] doubleValue];
            view.layer.cornerCurve = state[@"curve"];
            view.clipsToBounds = [state[@"clips"] boolValue];
            view.backgroundColor = state[@"background"] == NSNull.null ? nil : state[@"background"];
            view.hidden = [state[@"hidden"] boolValue];
            if ([view isKindOfClass:UILabel.class])
                ((UILabel *)view).textColor = state[@"textColor"] == NSNull.null ? nil : state[@"textColor"];
        }
        [pending addObjectsFromArray:view.subviews];
    }
}

static void QStyle(UIView *root) {
    if (!root) return;
    [qActiveNotifications addObject:root];
    QRestoreStyle(root);
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"enabled"] boolValue]) return;
    CGFloat radius = MAX(8, MIN(40, [qSettings[@"radius"] doubleValue]));
    QRememberStyle(root);
    root.layer.cornerRadius = radius;
    root.layer.cornerCurve = kCACornerCurveContinuous;
    root.clipsToBounds = YES;

    UIView *material = QFind(root, @"MTMaterialView");
    if (material) {
        QRememberStyle(material);
        material.layer.cornerRadius = radius;
        material.layer.cornerCurve = kCACornerCurveContinuous;
        material.clipsToBounds = YES;
        if ([qSettings[@"darkCards"] boolValue]) {
            material.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.82];
        }
    }

    // Keep Apple's notification actions, privacy rules, and accessibility hierarchy.
    // Only the visible labels and containers receive styling.
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            QRememberStyle(label);
            if ([qSettings[@"darkCards"] boolValue]) label.textColor = UIColor.whiteColor;
        }
        NSString *name = NSStringFromClass(view.class);
        BOOL iconClass = [name containsString:@"IconView"] || [name isEqualToString:@"NCBadgedIconView"];
        BOOL smallImage = [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image != nil;
        CGSize size = view.bounds.size;
        if ((iconClass || smallImage) && size.width >= 24 && size.width <= 80 &&
            fabs(size.width - size.height) < 5) {
            CGRect position = [view convertRect:view.bounds toView:root];
            if (position.origin.x < 105) {
                QRememberStyle(view);
                view.layer.cornerRadius = [qSettings[@"roundIcons"] boolValue] ? size.width / 2.0 : 0;
                view.layer.cornerCurve = kCACornerCurveCircular;
                view.clipsToBounds = [qSettings[@"roundIcons"] boolValue];
            }
        }
        [queue addObjectsFromArray:view.subviews];
    }
}

@interface PLPlatterView : UIView
@end
static void *QSpringBoardPlayerKey = &QSpringBoardPlayerKey;

%group QNotifications
%hook NCNotificationShortLookViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *preview = nil;
    if ([self respondsToSelector:@selector(viewForPreview)]) {
        preview = ((id (*)(id, SEL))objc_msgSend)(self, @selector(viewForPreview));
    }
    QStyle(preview ?: self.view);
}

%end
%end

#pragma mark - 锁屏通知列表等比缩放

static CGFloat QShrinkScale(void) {
    if (![qSettings[@"masterEnabled"] boolValue] ||
        [qSettings[@"disableListScaling"] boolValue]) return 1.0;
    id raw = qSettings[@"widthScale"];
    if (![raw isKindOfClass:NSNumber.class]) return 1.0;
    CGFloat scale = [raw doubleValue];
    return isfinite(scale) && scale > 0 ? MIN(1.0, MAX(0.7, scale)) : 1.0;
}

static void QUpdateScrollIndicator(UIView *view) {
    if (![view isKindOfClass:UIScrollView.class]) return;
    UIScrollView *scroll = (UIScrollView *)view;
    NSNumber *original = objc_getAssociatedObject(scroll, QOriginalIndicatorKey);
    if (QShrinkScale() < 1.0) {
        if (!original) objc_setAssociatedObject(scroll, QOriginalIndicatorKey,
                                                @(scroll.showsVerticalScrollIndicator),
                                                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (scroll.showsVerticalScrollIndicator) scroll.showsVerticalScrollIndicator = NO;
    } else if (original) {
        scroll.showsVerticalScrollIndicator = original.boolValue;
        objc_setAssociatedObject(scroll, QOriginalIndicatorKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIView *QOutermostList(UIView *view) {
    UIView *outer = nil;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCNotificationListView"]) {
            QUpdateScrollIndicator(ancestor);
            if (outer) QClearOwnLayerTransform(outer);
            outer = ancestor;
        }
    }
    return outer;
}

static void QClearOwnLayerTransform(UIView *list) {
    NSValue *owned = objc_getAssociatedObject(list, QOwnLayerTransformKey);
    NSValue *original = objc_getAssociatedObject(list, QOriginalLayerTransformKey);
    if (owned && original &&
        CATransform3DEqualToTransform(list.layer.sublayerTransform, owned.CATransform3DValue)) {
        list.layer.sublayerTransform = original.CATransform3DValue;
    }
    objc_setAssociatedObject(list, QOwnLayerTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, QOriginalLayerTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 不改 UIScrollView.transform：系统按 frame 重新布局时会把 bounds 扩到 1/scale，
// 截图实测 430pt 变成 581.625pt，视觉宽度因而回到原生。
// sublayerTransform 只变换子层的绘制坐标，不会让滚动视图本身的 bounds 被反向放大。
static void QApplyListScaling(UIView *list) {
    if (!list || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    QUpdateScrollIndicator(list);
    for (UIView *ancestor = list.superview; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCNotificationListView"]) {
            QClearOwnLayerTransform(list);
            return;
        }
    }
    CGFloat scale = QShrinkScale();
    if (scale >= 1.0) { QClearOwnLayerTransform(list); return; }
    NSValue *owned = objc_getAssociatedObject(list, QOwnLayerTransformKey);
    if (!owned) {
        CATransform3D original = list.layer.sublayerTransform;
        if (!CATransform3DIsIdentity(original)) return;
        objc_setAssociatedObject(list, QOriginalLayerTransformKey,
                                 [NSValue valueWithCATransform3D:original],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!CATransform3DEqualToTransform(list.layer.sublayerTransform,
                                              owned.CATransform3DValue)) {
        return; // 系统正在修改这一层，不覆盖系统的变换。
    }
    CATransform3D target = CATransform3DMakeScale(scale, scale, 1);
    if (CATransform3DEqualToTransform(list.layer.sublayerTransform, target)) return;
    objc_setAssociatedObject(list, QOwnLayerTransformKey,
                             [NSValue valueWithCATransform3D:target],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.layer.sublayerTransform = target;
}

static BOOL QClearOrdinaryNotifications(void) {
    SEL clear = @selector(_clearAllNotifications:supplementaryViewControllers:);
    id master = qMasterList;
    if ([master respondsToSelector:clear]) {
        ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(master, clear, YES, NO);
        return YES;
    }
    for (UIView *list in qActiveLists.allObjects) {
        id source = [list respondsToSelector:@selector(dataSource)]
            ? ((id (*)(id, SEL))objc_msgSend)(list, @selector(dataSource)) : nil;
        if ([source respondsToSelector:clear] &&
            [source isKindOfClass:objc_getClass("NCNotificationMasterList")]) {
            // The second flag excludes supplementary sections (Now Playing and Live Activities).
            ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(source, clear, YES, NO);
            return YES;
        }
    }
    return NO;
}

static BOOL QIsCoverSheetScroll(UIView *view) {
    if (!view) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        NSString *name = NSStringFromClass(ancestor.class);
        if ([name containsString:@"CoverSheet"] ||
            [name containsString:@"CSMainPage"] ||
            [name containsString:@"NCNotificationListView"]) return YES;
    }
    Class lockClass = objc_getClass("SBLockScreenManager");
    id manager = [lockClass respondsToSelector:@selector(sharedInstance)]
        ? ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance)) : nil;
    if ([manager respondsToSelector:@selector(isLockScreenVisible)] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isLockScreenVisible))) return YES;
    return NO;
}

@interface QSearchPanHelper : NSObject
+ (instancetype)shared;
- (void)track:(UIPanGestureRecognizer *)pan;
@end

@implementation QSearchPanHelper

+ (instancetype)shared {
    static QSearchPanHelper *helper;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ helper = [QSearchPanHelper new]; });
    return helper;
}

- (void)track:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed) {
        objc_setAssociatedObject(pan, QSearchPanCountedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (![qSettings[@"masterEnabled"] boolValue] || !QIsCoverSheetScroll(pan.view) ||
        objc_getAssociatedObject(pan, QSearchPanCountedKey)) return;
    UIWindow *window = pan.view.window;
    if (!window) return;
    CGPoint delta = [pan translationInView:window];
    if (delta.y < 35 || delta.y < fabs(delta.x) * 1.3) return;
    objc_setAssociatedObject(pan, QSearchPanCountedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat startX = [pan locationInView:window].x - delta.x;
    if (startX < CGRectGetMidX(window.bounds)) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (qLastRightSwipe > 0 && now - qLastRightSwipe >= 0.25 &&
        now - qLastRightSwipe <= 3.0) {
        qLastRightSwipe = 0;
        if ([qSettings[@"clearAllEnabled"] boolValue] && QClearOrdinaryNotifications() &&
            [qSettings[@"clearHapticEnabled"] boolValue]) {
            UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleLight];
            [feedback impactOccurred];
        }
    } else {
        qLastRightSwipe = now;
    }
}

@end

@interface SBSearchPresenter : NSObject
@end

%group QSearchGesture
%hook SBSearchPresenter

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if ([qSettings[@"masterEnabled"] boolValue] && QIsCoverSheetScroll(scrollView)) {
        UIPanGestureRecognizer *pan = scrollView.panGestureRecognizer;
        if (!objc_getAssociatedObject(pan, QSearchPanInstalledKey)) {
            [pan addTarget:[QSearchPanHelper shared] action:@selector(track:)];
            objc_setAssociatedObject(pan, QSearchPanInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [[QSearchPanHelper shared] track:pan];
        return; // Do not start Spotlight's interactive presentation on the cover sheet.
    }
    %orig;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ([qSettings[@"masterEnabled"] boolValue] && QIsCoverSheetScroll(scrollView)) {
        [[QSearchPanHelper shared] track:scrollView.panGestureRecognizer];
        return;
    }
    %orig;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity {
    if ([qSettings[@"masterEnabled"] boolValue] && QIsCoverSheetScroll(scrollView)) return;
    %orig;
}

- (BOOL)_canPresent {
    UIScrollView *tracked = [self respondsToSelector:@selector(trackingScrollView)]
        ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(trackingScrollView)) : nil;
    if ([qSettings[@"masterEnabled"] boolValue] && QIsCoverSheetScroll(tracked)) return NO;
    return %orig;
}

%end
%end

%group QMasterGesture
%hook NCNotificationMasterList

- (UIView *)masterListView {
    qMasterList = self;
    return %orig;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    qMasterList = self;
    %orig;
}

%end
%end

static void QScheduleListScaling(UIView *list) {
    if (!list || objc_getAssociatedObject(list, QScalePendingKey)) return;
    objc_setAssociatedObject(list, QScalePendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(list, QScalePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!list.window) return;
        QApplyListScaling(list);
        if (objc_getAssociatedObject(list, QScaleDiagnosticKey)) return;
        objc_setAssociatedObject(list, QScaleDiagnosticKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSString *line = [NSString stringWithFormat:
                @"Quart17 2.0.0 scale=%.3f class=%@ parent=%@ children=%lu bounds=%.1fx%.1f transform=%.3f,%.3f sublayer=%.3f\n",
                QShrinkScale(), NSStringFromClass(list.class),
                NSStringFromClass(list.superview.class), (unsigned long)list.subviews.count,
                list.bounds.size.width, list.bounds.size.height, list.transform.a, list.transform.d,
                list.layer.sublayerTransform.m11];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                [line writeToFile:@"/var/mobile/Library/Quart17-scale-debug.txt"
                        atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            });
        });
    });
}

%group QScale
%hook NCNotificationListCell

- (void)didMoveToWindow {
    %orig;
    UIView *list = QOutermostList((UIView *)self);
    if (list && ((UIView *)self).window) {
        [qActiveLists addObject:list];
    }
    QScheduleListScaling(list);
}

- (void)layoutSubviews {
    %orig;
    UIView *list = QOutermostList((UIView *)self);
    if (list) {
        [qActiveLists addObject:list];
    }
    QScheduleListScaling(list);
}

%end
%end
%group QHostPlatter
%hook PLPlatterView

- (void)layoutSubviews {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    CGSize size = self.bounds.size;
    if (size.width < 340 || size.width > 500 || size.height < 145 || size.height > 195) return;
    if (!QHasAncestor(self, @"NCNotificationListCell")) return;
    if (!QFind(self, @"CSActivityItemContentView")) return;
    QPlayerView *player = objc_getAssociatedObject(self, QSpringBoardPlayerKey);
    BOOL enabled = [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"playerEnabled"] boolValue];
    if (!enabled) {
        self.alpha = 1;
        player.hidden = YES;
        return;
    }
    UIView *container = self.superview;
    if (!container) return;
    if (!player) {
        player = [[QPlayerView alloc] initWithFrame:CGRectZero];
        [player setSuppressSiblingViews:NO];
        [player setUsesNativeMetadataFallback:NO];
        objc_setAssociatedObject(self, QSpringBoardPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [qActivePlayers addObject:player];
        [qActivePlatters addObject:self];
    }
    for (UIView *sibling in [container.subviews copy]) {
        if (sibling != player && [sibling isKindOfClass:QPlayerView.class]) [sibling removeFromSuperview];
    }
    if (player.superview != container) [container addSubview:player];
    // 播放器不再单独缩放：它位于 cell 的 contentView 之内，随 contentView 的
    // transform 一起等比缩小。若这里再乘一次 s 会得到 s²（78% 会变成约 61%）。
    // 内部度量由 QPlayerView 的 sizeFactor 按自身 bounds 推出，bounds 未受
    // transform 影响，因此内部仍按设计尺寸布局，再整体被 transform 缩下去。
    CGFloat height = MIN(88, size.height);
    CGRect frame = [self convertRect:CGRectMake(0, (size.height - height) / 2,
                                               size.width, height) toView:container];
    CGFloat scale = UIScreen.mainScreen.scale;
    player.frame = CGRectMake(round(frame.origin.x * scale) / scale,
                              round(frame.origin.y * scale) / scale,
                              round(frame.size.width * scale) / scale,
                              round(frame.size.height * scale) / scale);
    [player applySettings:qSettings];
    [player seedFromNativePlayer:self];
    [container bringSubviewToFront:player];
    player.hidden = NO;
    self.alpha = 0;
}

%end

%end

%ctor {
    @autoreleasepool {
        qActivePlayers = [NSHashTable weakObjectsHashTable];
        qActivePlatters = [NSHashTable weakObjectsHashTable];
        qActiveNotifications = [NSHashTable weakObjectsHashTable];
        qActiveLists = [NSHashTable weakObjectsHashTable];
        QLoadSettings();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.quart17/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QOpenPlayingApp, CFSTR("com.gushi.quart17/openplayingapp"),
                                            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        if (objc_getClass("NCNotificationShortLookViewController")) %init(QNotifications);
        if (objc_getClass("PLPlatterView")) %init(QHostPlatter);
        if (objc_getClass("NCNotificationListCell")) %init(QScale);
        if (objc_getClass("NCNotificationMasterList")) %init(QMasterGesture);
        Class searchClass = objc_getClass("SBSearchPresenter");
        if (searchClass &&
            [searchClass instancesRespondToSelector:@selector(scrollViewWillBeginDragging:)] &&
            [searchClass instancesRespondToSelector:@selector(scrollViewDidScroll:)])
            %init(QSearchGesture);
    }
}
