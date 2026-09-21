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
static void *QOriginalStyleKey = &QOriginalStyleKey;
static void QStyle(UIView *root);

@interface NCNotificationShortLookViewController : UIViewController
- (UIView *)viewForPreview;
@end

static void QLoadSettings(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    qSettings = [@{ @"masterEnabled": @YES, @"enabled": @YES, @"darkCards": @YES,
                    @"roundIcons": @YES, @"showContent": @YES, @"radius": @24,
                    @"playerEnabled": @YES, @"roundArtwork": @YES,
                    @"showProgress": @YES, @"backgroundProgress": @YES, @"hideRoute": @YES,
                    @"titleFromArtwork": @YES, @"artistFromArtwork": @YES,
                    @"progressFromArtwork": @YES, @"backgroundFromArtwork": @YES } mutableCopy];
    if ([saved isKindOfClass:NSDictionary.class]) [qSettings addEntriesFromDictionary:saved];
}

static void QChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                     const void *object, CFDictionaryRef userInfo) {
    QLoadSettings();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (QPlayerView *player in qActivePlayers.allObjects) {
            [player applySettings:qSettings];
            [player refresh];
        }
        for (UIView *platter in qActivePlatters.allObjects) {
            [platter setNeedsLayout];
            [platter layoutIfNeeded];
        }
        for (UIView *notification in qActiveNotifications.allObjects) QStyle(notification);
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
            if (![qSettings[@"showContent"] boolValue] && label.font.pointSize < 17) label.hidden = YES;
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

// On iOS 16/17 the lock-screen player lives in MediaRemoteUI. Its context is 2;
// Control Center can use the same class, so never style by class name alone.
@interface MRUNowPlayingViewController : UIViewController
- (long long)context;
@end

@interface PLPlatterView : UIView
@end
@interface CSMediaControlsView : UIView
@end
@interface _UISceneLayerHostContainerView : UIView
@end
@interface _UIContextLayerHostView : UIView
@end

static BOOL QIsLockScreenPlayer(MRUNowPlayingViewController *controller) {
    if ([controller respondsToSelector:@selector(context)] && controller.context == 2) return YES;
    for (UIViewController *parent = controller.parentViewController; parent; parent = parent.parentViewController) {
        if ([NSStringFromClass(parent.class) isEqualToString:@"MRUCoverSheetViewController"]) return YES;
    }
    return NO;
}

static void *QPlayerBackdropKey = &QPlayerBackdropKey;
static void *QCustomPlayerKey = &QCustomPlayerKey;
static void *QSpringBoardPlayerKey = &QSpringBoardPlayerKey;

static void QClearMediaMaterials(UIView *host) {
    if (!host) return;
    host.backgroundColor = UIColor.clearColor;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:host.subviews];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"MaterialView"] || [name isEqualToString:@"UIVisualEffectView"]) {
            view.alpha = 0;
        } else {
            [queue addObjectsFromArray:view.subviews];
        }
    }
}

static void QStylePlayer(UIView *player) {
    if (!player) return;
    QPlayerView *custom = objc_getAssociatedObject(player, QCustomPlayerKey);
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"playerEnabled"] boolValue]) {
        custom.hidden = YES;
        return;
    }
    player.backgroundColor = UIColor.clearColor;
    player.layer.cornerRadius = 0;
    player.layer.borderWidth = 0;
    player.clipsToBounds = NO;

    UIView *backdrop = objc_getAssociatedObject(player, QPlayerBackdropKey);
    if (!backdrop) {
        backdrop = [[UIView alloc] initWithFrame:player.bounds];
        backdrop.userInteractionEnabled = NO;
        backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [player insertSubview:backdrop atIndex:0];
        objc_setAssociatedObject(player, QPlayerBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    backdrop.hidden = YES;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:player];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"MRUNowPlayingTimeControlsView"]) {
            view.hidden = ![qSettings[@"showProgress"] boolValue];
        }
        if ([name containsString:@"RoutingButton"] || [name isEqualToString:@"MPRouteLabel"]) {
            view.hidden = [qSettings[@"hideRoute"] boolValue];
        }
        if ([qSettings[@"roundArtwork"] boolValue] &&
            [name containsString:@"Artwork"] && view.bounds.size.width > 25) {
            CGFloat artworkRadius = MIN(18, MIN(view.bounds.size.width, view.bounds.size.height) * 0.16);
            view.layer.cornerRadius = artworkRadius;
            view.layer.cornerCurve = kCACornerCurveContinuous;
            view.clipsToBounds = YES;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    if (!custom) {
        custom = [[QPlayerView alloc] initWithFrame:player.bounds];
        custom.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [player addSubview:custom];
        objc_setAssociatedObject(player, QCustomPlayerKey, custom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [qActivePlayers addObject:custom];
    }
    CGFloat capsuleHeight = MIN(88, MAX(70, player.bounds.size.height));
    custom.frame = CGRectMake(0, (player.bounds.size.height - capsuleHeight) / 2,
                              player.bounds.size.width, capsuleHeight);
    [custom applySettings:qSettings];
    [custom seedFromNativePlayer:player];
    [player bringSubviewToFront:custom];
    custom.hidden = NO;
}

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

%group QPlayer
%hook MRUNowPlayingViewController

- (void)viewDidLoad {
    %orig;
    if (QIsLockScreenPlayer(self)) QStylePlayer(self.view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!QIsLockScreenPlayer(self)) return;
    QStylePlayer(self.view);
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

%group QHostMedia
%hook CSMediaControlsView

- (void)layoutSubviews {
    %orig;
    if ([qSettings[@"masterEnabled"] boolValue] && [qSettings[@"playerEnabled"] boolValue]) {
        QClearMediaMaterials(self);
    }
}

%end
%end

%group QSceneHost
%hook _UISceneLayerHostContainerView

- (void)layoutSubviews {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    CGSize size = self.bounds.size;
    // iOS 17 CoverSheet's remote Now Playing host; measured on the target
    // device as 402 x 167 pt. Keep other remote scenes untouched.
    if (size.width < 340 || size.width > 500 || size.height < 145 || size.height > 195) return;
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"playerEnabled"] boolValue]) return;
    self.backgroundColor = UIColor.clearColor;
    self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

%end
%end

%ctor {
    @autoreleasepool {
        qActivePlayers = [NSHashTable weakObjectsHashTable];
        qActivePlatters = [NSHashTable weakObjectsHashTable];
        qActiveNotifications = [NSHashTable weakObjectsHashTable];
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
        if (objc_getClass("MRUNowPlayingViewController")) %init(QPlayer);
        if (objc_getClass("PLPlatterView")) %init(QHostPlatter);
        if (objc_getClass("CSMediaControlsView")) %init(QHostMedia);
        if (objc_getClass("_UISceneLayerHostContainerView")) %init(QSceneHost);
    }
}
