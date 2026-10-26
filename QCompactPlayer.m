#import "QPlayerView.h"
#import <objc/runtime.h>
#import <dlfcn.h>

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);

static NSHashTable<UIView *> *qCompactHosts;
static NSDictionary *qCompactSettings;
static BOOL qCompactExpanded;
static const void *QCompactPlayerKey = &QCompactPlayerKey;
static const void *QCompactVisibilityKey = &QCompactVisibilityKey;
static const void *QCompactGestureKey = &QCompactGestureKey;

static void QRestoreCompactContent(UIView *host) {
    NSMapTable<UIView *, NSArray<NSNumber *> *> *visibility = objc_getAssociatedObject(host, QCompactVisibilityKey);
    [UIView performWithoutAnimation:^{
        for (UIView *view in visibility.keyEnumerator.allObjects) {
            NSArray<NSNumber *> *state = [visibility objectForKey:view];
            view.alpha = state.firstObject.doubleValue;
            view.hidden = state.lastObject.boolValue;
        }
    }];
    objc_setAssociatedObject(host, QCompactVisibilityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMapTable<UIGestureRecognizer *, NSNumber *> *gestures = objc_getAssociatedObject(host, QCompactGestureKey);
    for (UIGestureRecognizer *gesture in gestures.keyEnumerator.allObjects)
        gesture.enabled = [[gestures objectForKey:gesture] boolValue];
    objc_setAssociatedObject(host, QCompactGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QRestoreCompactHost(UIView *host) {
    QRestoreCompactContent(host);
    QPlayerView *player = objc_getAssociatedObject(host, QCompactPlayerKey);
    [player removeFromSuperview];
    objc_setAssociatedObject(host, QCompactPlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QLayoutCompactHost(UIView *host) {
    [qCompactHosts addObject:host];
    // The notification player belongs to the cover-sheet list scene.
    BOOL listScene = [host.window.windowScene.session.role isEqualToString:@"ActivitySceneSessionRoleListItem"];
    BOOL enabled = [qCompactSettings[@"masterEnabled"] boolValue] &&
                   [qCompactSettings[@"playerEnabled"] boolValue];
    if (!listScene || !enabled || CGRectIsEmpty(host.bounds)) {
        QRestoreCompactHost(host);
        return;
    }

    QPlayerView *player = objc_getAssociatedObject(host, QCompactPlayerKey);
    if (!player) {
        player = [[QPlayerView alloc] initWithFrame:CGRectZero];
        [player setSuppressSiblingViews:NO];
        [player setUsesNativeMetadataFallback:YES];
        objc_setAssociatedObject(host, QCompactPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:player];
    }
    CGFloat height = MIN(88, MAX(0, host.bounds.size.height - 8));
    player.frame = CGRectMake(CGRectGetMinX(host.bounds),
        CGRectGetMinY(host.bounds) + (host.bounds.size.height - height) * 0.75,
        host.bounds.size.width, height);
    [player applySettings:qCompactSettings];
    [player seedFromNativePlayer:host];
    [player setExpandedArtwork:qCompactExpanded];

    NSMapTable<UIView *, NSArray<NSNumber *> *> *visibility = objc_getAssociatedObject(host, QCompactVisibilityKey);
    if (!visibility) {
        visibility = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(host, QCompactVisibilityKey, visibility, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [UIView performWithoutAnimation:^{
        for (UIView *view in host.subviews) {
            if (view == player) continue;
            if (![visibility objectForKey:view])
                [visibility setObject:@[@(view.alpha), @(view.hidden)] forKey:view];
            // Native cover transitions animate opacity independently of layout.
            view.hidden = YES;
            view.alpha = 0;
        }
    }];
    // Native platter taps must not cancel the custom controls' touches.
    NSMapTable<UIGestureRecognizer *, NSNumber *> *gestures = objc_getAssociatedObject(host, QCompactGestureKey);
    if (!gestures) {
        gestures = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(host, QCompactGestureKey, gestures, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIGestureRecognizer *gesture in host.gestureRecognizers) {
        if (![gestures objectForKey:gesture]) [gestures setObject:@(gesture.enabled) forKey:gesture];
        gesture.enabled = NO;
    }
    [host bringSubviewToFront:player];
}

static void (*qCompactOriginalLayout)(UIView *, SEL);
static void QCompactLayout(UIView *host, SEL selector) {
    qCompactOriginalLayout(host, selector);
    QLayoutCompactHost(host);
}

static void (*qCompactOriginalDidMove)(UIView *, SEL);
static void QCompactDidMove(UIView *host, SEL selector) {
    qCompactOriginalDidMove(host, selector);
    if (host.window) NSLog(@"[Quart17] compact scene role=%@ enabled=%d/%d bounds=%@",
        host.window.windowScene.session.role, [qCompactSettings[@"masterEnabled"] boolValue],
        [qCompactSettings[@"playerEnabled"] boolValue], NSStringFromCGRect(host.bounds));
    QLayoutCompactHost(host);
}

static void QCompactSettingsChanged(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        qCompactSettings = QReadPlayerSettings();
        for (UIView *host in qCompactHosts.allObjects) {
            [host setNeedsLayout];
            [host layoutIfNeeded];
        }
    });
}

static void QCompactArtworkChanged(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object, CFDictionaryRef info) {
    BOOL expanded = CFEqual(name, CFSTR("com.gushi.quart17/nativeartworkexpanded"));
    dispatch_async(dispatch_get_main_queue(), ^{
        qCompactExpanded = expanded;
        for (UIView *host in qCompactHosts.allObjects) {
            QPlayerView *player = objc_getAssociatedObject(host, QCompactPlayerKey);
            [player setExpandedArtwork:expanded];
        }
    });
}

void QInstallCompactPlayerHooks(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) return;
    dlopen("/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls", RTLD_LAZY);
    Class hostClass = objc_getClass("MRUCoverSheetView");
    NSLog(@"[Quart17] compact hook host=%@", hostClass);
    if (!hostClass) return;
    qCompactHosts = [NSHashTable weakObjectsHashTable];
    qCompactSettings = QReadPlayerSettings();
    MSHookMessageEx(hostClass, @selector(layoutSubviews), (IMP)QCompactLayout, (IMP *)&qCompactOriginalLayout);
    MSHookMessageEx(hostClass, @selector(didMoveToWindow), (IMP)QCompactDidMove, (IMP *)&qCompactOriginalDidMove);
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL, QCompactSettingsChanged,
        CFSTR("com.gushi.quart17/playercornerchanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, QCompactSettingsChanged,
        CFSTR("com.gushi.quart17/preferenceschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, QCompactSettingsChanged,
        CFSTR("com.gushi.aura/preferenceschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, QCompactArtworkChanged,
        CFSTR("com.gushi.quart17/nativeartworkexpanded"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, QCompactArtworkChanged,
        CFSTR("com.gushi.quart17/nativeartworkcollapsed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
