#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <stdlib.h>
#import <notify.h>
#import <math.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include <string.h>
#include <algorithm>
#include <vector>
#import "QPlayerView.h"
// QRefreshSearchPills 已迁至 Aura（SearchPill.xm）

static NSString *const QPrefs = @"com.gushi.quart17";
static NSMutableDictionary *qSettings;
static int qCornerStateToken = -1;
// notifyd drops a name's state once its last token is cancelled. After a respring SpringBoard
// publishes before MediaRemoteUI registers, so every published state keeps its token open.
static int qOffsetStateToken = -1, qFlagsStateToken = -1, qBorderStateToken = -1, qVelaStateToken = -1;

static NSHashTable<UIView *> *qActivePlatters;
static NSHashTable<UIView *> *qActiveNotifications;
static NSHashTable<UIView *> *qActiveLists;
static NSHashTable<UIView *> *qActiveBanners;
static NSHashTable<UIView *> *qLockClockViews;
static void *QLockClockLabelKey = &QLockClockLabelKey;
static void *QLockClockOriginalHiddenKey = &QLockClockOriginalHiddenKey;
static void *QLockClockOriginalFrameKey = &QLockClockOriginalFrameKey;
static void *QLockClockOriginalTransformKey = &QLockClockOriginalTransformKey;
static void *QLockClockAppliedTransformKey = &QLockClockAppliedTransformKey;
static void *QLockClockAppliedCenterKey = &QLockClockAppliedCenterKey;
static void *QLockClockTopContentKey = &QLockClockTopContentKey;
static void *QLockClockNormalDateKey = &QLockClockNormalDateKey;
static void *QLockClockNormalDateDayKey = &QLockClockNormalDateDayKey;
static BOOL qStylingLockClock;
static BOOL qLockClockRetryPending;
static CFAbsoluteTime qLockClockRetryAt;
static void *QOriginalStyleKey = &QOriginalStyleKey;
static void *QOwnLayerTransformKey = &QOwnLayerTransformKey;
static void *QOriginalLayerTransformKey = &QOriginalLayerTransformKey;
static void *QScalePendingKey = &QScalePendingKey;
static void *QScaleRetryKey = &QScaleRetryKey;
static void *QOriginalIndicatorKey = &QOriginalIndicatorKey;
static void *QBannerOriginalTransformKey = &QBannerOriginalTransformKey;
static void *QBannerOwnedTransformKey = &QBannerOwnedTransformKey;
static void *QBannerShadowHiddenKey = &QBannerShadowHiddenKey;
static void *QCountBadgeKey = &QCountBadgeKey;
static void *QStackKeyKey = &QStackKeyKey;
static void *QRequestKey = &QRequestKey;

// Try several KVC keys; returns the first non-nil value and reports which key hit.
static id QTryKVCKeys(id obj, NSArray<NSString *> *keys, NSString **hitKeyOut) {
    for (NSString *k in keys) {
        id v = nil;
        @try { v = [obj valueForKey:k]; } @catch (NSException *e) { v = nil; }
        if (v && v != (id)[NSNull null]) {
            if (hitKeyOut) *hitKeyOut = k;
            return v;
        }
    }
    return nil;
}
static __weak id qMasterList;
static CFAbsoluteTime qLastRightSwipe;
static void *QSearchPanInstalledKey = &QSearchPanInstalledKey;
static void *QSearchPanEligibleKey = &QSearchPanEligibleKey;
static void *QSearchPanQualifiedKey = &QSearchPanQualifiedKey;



static void QStyle(UIView *root);
static CGFloat QShrinkScale(void);
static BOOL QApplyListScaling(UIView *list);
static void QScheduleListScaling(UIView *list);
static void QApplyListAnchor(UIView *list);
static BOOL QPanBelongsToPlayer(UIScrollView *scroll, UIPanGestureRecognizer *pan);
static void QClearOwnLayerTransform(UIView *list);
static void QApplyBannerScaling(UIView *banner);
static void QStyleLockClock(UIView *dateView);
static void QRestyleLockClockForWidget(UIView *widget);

@interface NCNotificationShortLookViewController : UIViewController
- (UIView *)viewForPreview;
@end

@interface CSQuickActionsButton : UIView
@end

@interface SBFLockScreenDateView : UIView
@end

@interface CSProminentEmptyElementView : UIView
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface _UIAnimatingLabel : UILabel
@end


static void QLoadSettings(void) {
    qSettings = [QReadPlayerSettings() mutableCopy];
    if (qCornerStateToken < 0)
        notify_register_check("com.gushi.quart17/playercorner", &qCornerStateToken);
    if (qCornerStateToken >= 0) {
        CGFloat corner = [qSettings[@"playerCornerRoundness"] doubleValue];
        corner = isfinite(corner) ? MAX(0, MIN(1, corner)) : 1;
        CGFloat scale = qSettings[@"largeArtworkScale"] ?
            [qSettings[@"largeArtworkScale"] doubleValue] : 1;
        scale = isfinite(scale) ? MAX(0.6, MIN(1, scale)) : 1;
        CGFloat expandedCorner = [qSettings[@"largeArtworkRoundness"] doubleValue];
        expandedCorner = isfinite(expandedCorner) ? MAX(0, MIN(1, expandedCorner)) : corner;
        notify_set_state(qCornerStateToken, ((uint64_t)llround(expandedCorner * 10000) << 48) |
            ((uint64_t)llround(scale * 10000) << 32) |
            0x51700000ULL | (uint64_t)llround(corner * 10000));
    }
    if (qOffsetStateToken < 0) notify_register_check("com.gushi.quart17/artworkoffset", &qOffsetStateToken);
    if (qOffsetStateToken >= 0) {
        double offset = [qSettings[@"largeArtworkOffsetY"] doubleValue];
        offset = isfinite(offset) ? MAX(-200, MIN(200, offset)) : 0;
        notify_set_state(qOffsetStateToken, (uint64_t)llround((offset + 200) * 100) + 1);
    }
    if (qFlagsStateToken < 0) notify_register_check("com.gushi.quart17/artworkflags", &qFlagsStateToken);
    if (qFlagsStateToken >= 0) {
        uint64_t flags = 0x51710000ULL |
            ([qSettings[@"masterEnabled"] boolValue] ? 1ULL : 0) |
            ([qSettings[@"playerEnabled"] boolValue] ? 2ULL : 0) |
            ([qSettings[@"showProgress"] boolValue] ? 4ULL : 0) |
            ((uint64_t)(MIN(2, MAX(0, [qSettings[@"progressStyle"] integerValue])) + 1) << 3);
        NSArray *keys = @[@"hideControls", @"hideRoute", @"backgroundFromArtwork", @"titleFromArtwork", @"artistFromArtwork", @"progressFromArtwork"];
        for (NSUInteger i = 0; i < keys.count; i++)
            if ([qSettings[keys[i]] boolValue]) flags |= 1ULL << (i + 5);
        notify_set_state(qFlagsStateToken, flags | (1ULL << 11));
    }
    if (qBorderStateToken < 0) notify_register_check("com.gushi.quart17/playerborder", &qBorderStateToken);
    if (qBorderStateToken >= 0) {
        double width = [qSettings[@"playerBorderWidth"] doubleValue];
        width = isfinite(width) ? MAX(0.5, MIN(4, width)) : 1.5;
        notify_set_state(qBorderStateToken, 0x51720000ULL | ([qSettings[@"playerBorderEnabled"] boolValue] ? 0x8000ULL : 0) |
                                      (uint64_t)llround(width * 100));
    }
    if (qVelaStateToken < 0) notify_register_check("com.gushi.quart17/velatheme", &qVelaStateToken);
    if (qVelaStateToken >= 0) {
        NSString *velaTheme = qSettings[@"velaThemeFolder"];
        notify_set_state(qVelaStateToken, (0x5173ULL << 48) |
            (velaTheme ? (1ULL << 32) | QVelaThemeHash(velaTheme) : 0) |
            ([qSettings[@"customControlIcons"] boolValue] ? (1ULL << 33) : 0));
    }
    // MediaRemoteUI reads every state above when this arrives, so post only after all are written.
    if (qCornerStateToken >= 0) notify_post("com.gushi.quart17/playercornerchanged");
}

static void QChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                     const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *previous = [qSettings copy];
        QLoadSettings();
        NSMutableDictionary *beforeStyle = [previous mutableCopy];
        NSMutableDictionary *afterStyle = [qSettings mutableCopy];
        for (NSString *key in @[@"widthScale", @"disableListScaling", @"scaleBanners"]) {
            [beforeStyle removeObjectForKey:key];
            [afterStyle removeObjectForKey:key];
        }
        if ([beforeStyle isEqualToDictionary:afterStyle]) {
            for (UIView *list in qActiveLists.allObjects) QScheduleListScaling(list);
            for (UIView *banner in qActiveBanners.allObjects) QApplyBannerScaling(banner);
            return;
        }
        for (UIView *platter in qActivePlatters.allObjects) {
            [platter setNeedsLayout];
            [platter layoutIfNeeded];
        }
        for (UIView *notification in qActiveNotifications.allObjects) QStyle(notification);
        for (UIView *list in qActiveLists.allObjects) {
            QApplyListAnchor(list);
            QScheduleListScaling(list);
        }
        for (UIView *banner in qActiveBanners.allObjects) QApplyBannerScaling(banner);
        for (UIView *dateView in qLockClockViews.allObjects) QStyleLockClock(dateView);
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

static BOOL QIsLockScreenVisible(void) {
    Class lockClass = objc_getClass("SBLockScreenManager");
    id manager = [lockClass respondsToSelector:@selector(sharedInstance)]
        ? ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance)) : nil;
    return [manager respondsToSelector:@selector(isLockScreenVisible)] &&
           ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isLockScreenVisible));
}

static BOOL QIsLockScreenNotification(UIView *view) {
    if (!view.window || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
        !QIsLockScreenVisible()) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCNotificationList"]) return YES;
    }
    return NO;
}

static BOOL QIsDesktopBanner(UIView *view) {
    if (!view.window || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])
        return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCNotificationList"]) return NO;
    }
    return !QIsLockScreenVisible();
}

static UIView *QBannerSurface(UIView *view) {
    for (UIView *ancestor = view; ancestor && ![ancestor isKindOfClass:UIWindow.class];
         ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCDimmableView"]) return ancestor;
    }
    // Wait until the short look has been inserted into its banner host. Scaling
    // an inner platter before then leaves the material backing at native size.
    return nil;
}

static UIView *QStackContainer(UIView *view) {
    UIView *cell = nil;
    for (UIView *ancestor = view.superview; ancestor && ![ancestor isKindOfClass:UIWindow.class];
         ancestor = ancestor.superview) {
        NSString *name = NSStringFromClass(ancestor.class);
        if ([name isEqualToString:@"NCNotificationListView"]) return ancestor;
        if (!cell && [name isEqualToString:@"NCNotificationListCell"]) cell = ancestor;
    }
    return cell;
}

static BOOL QIsViewInFrontOf(UIView *upper, UIView *lower) {
    if (!upper || !lower || upper == lower) return NO;
    NSMutableArray<UIView *> *upperChain = [NSMutableArray array];
    for (UIView *a = upper; a; a = a.superview) [upperChain addObject:a];
    NSSet *upperSet = [NSSet setWithArray:upperChain];
    UIView *lca = nil;
    UIView *lowerChild = nil;
    for (UIView *a = lower; a; a = a.superview) {
        if ([upperSet containsObject:a]) { lca = a; break; }
        lowerChild = a;
    }
    if (!lca || !lowerChild) return NO;
    UIView *upperChild = nil;
    for (UIView *a = upper; a && a != lca; a = a.superview) upperChild = a;
    if (!upperChild || upperChild == lowerChild) return NO;
    NSUInteger ui = [lca.subviews indexOfObject:upperChild];
    NSUInteger li = [lca.subviews indexOfObject:lowerChild];
    return ui != NSNotFound && li != NSNotFound && ui > li;
}

// Styled notification views in the same list container whose frames overlap
// root's frame: the folded stack around this card. Empty when the card stands
// alone (banner, expanded list, single notification).
static NSArray<UIView *> *QStackSiblings(UIView *root) {
    NSMutableArray<UIView *> *siblings = [NSMutableArray array];
    UIView *container = QStackContainer(root);
    if (!container || !root.window) return siblings;
    CGRect rootFrame = [root convertRect:root.bounds toView:container];
    if (CGRectIsNull(rootFrame) || CGRectIsEmpty(rootFrame)) return siblings;
    CGFloat rootArea = rootFrame.size.width * rootFrame.size.height;
    if (rootArea <= 0) return siblings;
    for (UIView *other in qActiveNotifications.allObjects) {
        if (other == root || !other.window) continue;
        BOOL sameContainer = NO;
        for (UIView *a = other; a && ![a isKindOfClass:UIWindow.class]; a = a.superview) {
            if (a == container) { sameContainer = YES; break; }
        }
        if (!sameContainer) continue;
        CGRect otherFrame = [other convertRect:other.bounds toView:container];
        if (CGRectIsNull(otherFrame) || CGRectIsEmpty(otherFrame)) continue;
        // 要求显著重叠（>60%）才算堆叠，避免滚动时轻微交错误判为折叠
        CGRect inter = CGRectIntersection(rootFrame, otherFrame);
        if (CGRectIsNull(inter) || CGRectIsEmpty(inter)) continue;
        CGFloat interArea = inter.size.width * inter.size.height;
        if (interArea > rootArea * 0.6)
            [siblings addObject:other];
    }
    return siblings;
}

static UIView *QNotificationAppIcon(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        // Only skip the badge itself (marked @YES). Root also carries this key
        // (it points at the badge view) and must still be traversed.
        if ([objc_getAssociatedObject(view, QCountBadgeKey) isEqual:@YES]) continue;
        NSString *name = NSStringFromClass(view.class);
        BOOL iconClass = [name containsString:@"IconView"];
        BOOL smallImage = [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image != nil;
        CGSize size = view.bounds.size;
        BOOL isIcon = smallImage ||
            (iconClass && view.subviews.count == 0 && ![name containsString:@"Badged"]);
        if (isIcon && size.width >= 24 && size.width <= 80 && fabs(size.width - size.height) < 5) {
            CGRect position = [view convertRect:view.bounds toView:root];
            if (position.origin.x < 105) return view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

static void QUpdateCountBadge(UIView *root, NSInteger count, BOOL front) {
    UILabel *badge = objc_getAssociatedObject(root, QCountBadgeKey);
    BOOL stylingOn = [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"enabled"] boolValue];
    BOOL show = stylingOn && [qSettings[@"showNotificationCount"] boolValue] &&
        front && count > 1 && root.window != nil;
    if (!show) {
        [badge removeFromSuperview];
        if (badge) objc_setAssociatedObject(root, QCountBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!badge) {
        badge = [[UILabel alloc] init];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        badge.textColor = [UIColor colorWithWhite:0.16 alpha:1];
        badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.94];
        badge.layer.masksToBounds = YES;
        badge.userInteractionEnabled = NO;
        // Marked so QStyle's label pass leaves it alone.
        objc_setAssociatedObject(badge, QCountBadgeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(root, QCountBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    badge.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
    [badge sizeToFit];
    CGSize size = badge.bounds.size;
    CGFloat diameter = MAX(18, MAX(size.width + 9, size.height + 6));
    badge.bounds = CGRectMake(0, 0, diameter, diameter);
    badge.layer.cornerRadius = diameter / 2;
    UIView *icon = QNotificationAppIcon(root);
    if (icon) {
        CGPoint anchor = [icon.superview convertPoint:CGPointMake(CGRectGetMaxX(icon.bounds) - 3, 3)
                                              toView:root];
        badge.center = anchor;
        if (badge.superview != root) [root addSubview:badge];
        [root bringSubviewToFront:badge];
    } else if (badge.superview) {
        [badge removeFromSuperview];
    }
}

// Declared for the compiler; guarded by respondsToSelector at runtime.
@interface UIView (QStackCountProbe)
- (NSArray *)notificationRequests;
@end

// A stack's identity from the data model: section + thread. Views come and
// go (the system detaches hidden cards' views when folded), but the identity
// is stable, so we can count the stack across every source that has it.
@interface UIViewController (QStackRequestProbe)
- (id)notificationRequest;
@end
@interface NSObject (QStackRequestIDsProbe)
- (NSString *)sectionIdentifier;
- (NSString *)threadIdentifier;
@end

static NSString *QStackKeyForRequest(id request) {
    if (!request) return nil;
    NSString *secHit = nil, *threadHit = nil;
    id section = QTryKVCKeys(request,
        (@[@"sectionIdentifier", @"sectionID", @"_sectionIdentifier"]), &secHit);
    id thread = QTryKVCKeys(request,
        (@[@"threadIdentifier", @"threadID", @"coalescingIdentifier", @"_threadIdentifier"]), &threadHit);
    if (![section isKindOfClass:NSString.class] || ![(NSString *)section length]) return nil;
    NSString *threadStr = [thread isKindOfClass:NSString.class] ? thread : @"";
    return [NSString stringWithFormat:@"%@|%@", section, threadStr];
}

// A section-only key (no thread identifier) merges different stacks of the
// same app, which over-counts (e.g. true 3 shows 4). Only trust the
// cross-view / model sources when the key carries a real thread.
static BOOL QStackKeyHasThread(NSString *key) {
    NSRange r = [key rangeOfString:@"|" options:NSBackwardsSearch];
    return r.location != NSNotFound && r.location + 1 < key.length;
}

static NSString *QStackKeyForView(UIView *view) {
    // The request itself is cached so both the stack key and the notification
    // identifier come from one probe.
    id cachedReq = objc_getAssociatedObject(view, QRequestKey);
    id request = nil;
    UIResponder *r = nil;
    NSString *reqHit = nil;
    if (cachedReq) {
        request = (cachedReq == (id)[NSNull null]) ? nil : cachedReq;
        // A cached miss is retried: the request may simply not have been set yet.
        if (!request) cachedReq = nil;
    }
    if (!cachedReq) {
        r = view.nextResponder;
        while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
        request = QTryKVCKeys(r,
            (@[@"notificationRequest", @"request", @"_notificationRequest"]), &reqHit);
        // Only cache hits; misses are re-probed next time.
        if (request) objc_setAssociatedObject(view, QRequestKey,
            request, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *key = QStackKeyForRequest(request);
    return key;
}

// Unique notification identifier, for deduplicating views that represent
// the same notification (e.g. a banner and its list card).
static NSString *QNotificationIDForView(UIView *view) {
    id cachedReq = objc_getAssociatedObject(view, QRequestKey);
    id request = (cachedReq == (id)[NSNull null]) ? nil : cachedReq;
    if (!request) { (void)QStackKeyForView(view); cachedReq = objc_getAssociatedObject(view, QRequestKey); request = (cachedReq == (id)[NSNull null]) ? nil : cachedReq; }
    if (!request) return nil;
    id nid = QTryKVCKeys(request, (@[@"notificationIdentifier", @"identifier"]), NULL);
    return [nid isKindOfClass:NSString.class] ? nid : nil;
}

// Every styled notification view we know, grouped by stack identity. Catches
// detached-but-alive card views that the overlap walk can no longer see.
// Only counts views inside the SAME NCNotificationListView as the stack:
// without this, banners and other lists (lock screen vs notification center)
// for the same app+thread pollute the count (true 3 showing 7).
// Deduplicates by notification identifier as a second line of defense.
static NSInteger QActiveTableStackCount(NSString *stackKey, UIView *listContainer) {
    if (!stackKey) return 0;
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];
    NSInteger n = 0;
    for (UIView *v in qActiveNotifications.allObjects) {
        if (![QStackKeyForView(v) isEqualToString:stackKey]) continue;
        if (listContainer && QStackContainer(v) != listContainer) continue;
        NSString *nid = QNotificationIDForView(v);
        if (nid.length) {
            if ([seenIDs containsObject:nid]) continue;
            [seenIDs addObject:nid];
        }
        n++;
    }
    return n;
}

// The list's data model: the only source that knows requests whose views
// were never created (a stack that arrived already folded).
static NSInteger QMasterListStackCount(NSString *stackKey, UIView *listContainer) {
    // Model-based count: NCNotificationGroupList._orderedRequests holds ALL
    // requests for the stack, even after folding destroys the card views.
    // Match by section+thread identifier; prefer the section list whose view
    // is the container we're in (lock screen vs notification center).
    if (!stackKey) return 0;
    id master = qMasterList;
    if (!master) return 0;
    id sections = QTryKVCKeys(master, (@[@"_notificationSections"]), NULL);
    NSUInteger sc = [sections respondsToSelector:@selector(count)] ? [sections count] : 0;
    NSInteger bestInContainer = 0, bestAnywhere = 0;
    for (NSUInteger i = 0; i < sc; i++) {
        id sl = [sections objectAtIndex:i];
        id slView = QTryKVCKeys(sl, (@[@"_sectionListView"]), NULL);
        BOOL isOurs = (listContainer && slView == listContainer);
        id groups = QTryKVCKeys(sl, (@[@"_notificationGroups"]), NULL);
        NSUInteger gc = [groups respondsToSelector:@selector(count)] ? [groups count] : 0;
        for (NSUInteger j = 0; j < gc; j++) {
            id g = [groups objectAtIndex:j];
            NSString *sid = QTryKVCKeys(g, (@[@"_sectionIdentifier"]), NULL);
            if (![sid isKindOfClass:NSString.class]) continue;
            NSString *tid = QTryKVCKeys(g, (@[@"_threadIdentifier"]), NULL);
            if (![tid isKindOfClass:NSString.class] || !tid.length)
                tid = [@"req-" stringByAppendingString:sid];
            NSString *gkey = [NSString stringWithFormat:@"%@|%@", sid, tid];
            if (![gkey isEqualToString:stackKey]) continue;
            id reqs = QTryKVCKeys(g, (@[@"_orderedRequests"]), NULL);
            NSInteger n = [reqs respondsToSelector:@selector(count)] ? (NSInteger)[reqs count] : 0;
            if (n > bestAnywhere) bestAnywhere = n;
            if (isOurs && n > bestInContainer) bestInContainer = n;
        }
    }
    return bestInContainer > 0 ? bestInContainer : bestAnywhere;
}

static UIView *QStackCellForView(UIView *view) {    for (UIView *a = view.superview; a && ![a isKindOfClass:UIWindow.class]; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:@"NCNotificationListCell"]) return a;
    }
    return nil;
}

// True stack size, from the data model rather than the views: after folding,
// the system detaches the hidden cards' views, so counting overlapping views
// under-reports (e.g. 5 becomes 3). Group the overlapping views by their
// cell and sum each cell's notificationRequests; fall back to the view count
// when the model is unavailable.
static NSInteger QStackCount(UIView *root, NSArray<UIView *> *siblings) {
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:root];
    [views addObjectsFromArray:siblings];
    NSMutableSet<UIView *> *cells = [NSMutableSet set];
    NSInteger extra = 0;
    for (UIView *v in views) {
        UIView *cell = QStackCellForView(v);
        if (cell) [cells addObject:cell];
        else extra++;
    }
    NSInteger count = extra;
    for (UIView *cell in cells) {
        NSInteger n = 0;
        NSString *cellHit = nil;
        id reqs = QTryKVCKeys(cell,
            (@[@"notificationRequests", @"requests", @"_notificationRequests", @"stackedNotificationRequests"]),
            &cellHit);
        if ([reqs isKindOfClass:NSArray.class]) n = (NSInteger)[(NSArray *)reqs count];
        if (n <= 0) {
            for (UIView *v in views) {
                if (QStackCellForView(v) == cell) n++;
            }
        }
        count += n;
    }
    return count;
}

static void QUpdateStackState(UIView *root) {
    NSArray<UIView *> *siblings = QStackSiblings(root);
    UIView *container = QStackContainer(root);
    CGRect rootFrame = container ? [root convertRect:root.bounds toView:container] : CGRectNull;
    CGFloat rootArea = CGRectIsNull(rootFrame) ? 0 : rootFrame.size.width * rootFrame.size.height;
    // The front card of a folded stack is full-size; the cards behind are
    // scaled down. Area decides, z-order breaks ties. Only used to place the
    BOOL front = YES;
    BOOL hasFoldedBehind = NO;  // 折叠堆叠：后面有缩小卡片；展开时所有卡片等大
    for (UIView *sibling in siblings) {
        CGRect f = [sibling convertRect:sibling.bounds toView:container];
        CGFloat area = f.size.width * f.size.height;
        // 后面有明显缩小的卡片（>5%）才算折叠状态，避免滚动动画误判
        if (area < rootArea * 0.95 && !QIsViewInFrontOf(sibling, root)) hasFoldedBehind = YES;
        // 兄弟卡片在视觉上位于本卡前面 → 本卡不是最上层
        if (QIsViewInFrontOf(sibling, root)) { front = NO; break; }
        // 兄弟卡片明显更大 → 本卡不是最上层（折叠堆叠的顶层卡）
        if (area > rootArea * 1.02) { front = NO; break; }
    }
    // 展开时不显示计数徽标：只有折叠堆叠（后面有缩小卡片）才显示
    if (!hasFoldedBehind) front = NO;
    // Only a real (overlapping) stack uses the model count; a lone card is
    // always 1 even if its cell hosts other requests.
    // 模型计数只在确认折叠时使用，展开时不用（避免展开后仍显示错误计数）。
    NSInteger count = 1;
    NSString *stackKey = nil;
    if (siblings.count && hasFoldedBehind) {
        // 计数优先级：数据模型 > 视图统计。数据模型（_orderedRequests）是唯一知道
        // 视图未创建请求（已折叠到达的堆叠）的来源。视图统计在折叠后会少算
        // （系统只渲染约3层），但可能因重复请求或跨列表数据而多算，因此只在
        // 模型不可用时作为回退，不再取多源最大值。
        stackKey = QStackKeyForView(root);
        NSInteger masterCount = 0;
        if (stackKey && QStackKeyHasThread(stackKey)) {
            masterCount = QMasterListStackCount(stackKey, container);
        }
        if (masterCount > 0) {
            count = masterCount;
        } else {
            // 模型不可用时的回退：用 cell 模型的请求数
            count = QStackCount(root, siblings);
            if (count < 1) count = 1;
        }
        if (stackKey && QStackKeyHasThread(stackKey)) {
            NSInteger tableCount = QActiveTableStackCount(stackKey, container);
            // 可见视图数 >= 模型总数 → 所有通知都可见 = 展开状态，不显示徽标
            // 折叠时系统只渲染约3层，可见数 < 总数，才显示计数
            if (masterCount > 0 && tableCount >= masterCount) {
                front = NO;
            }
        }
    }
    // 互斥：同一堆叠只允许最上层卡片显示徽标。如果本卡是 front，
    // 先清除所有兄弟卡片的徽标，防止时序问题导致徽标出现在第二张卡上。
    if (front && count > 1) {
        for (UIView *sibling in siblings) {
            UILabel *sibBadge = objc_getAssociatedObject(sibling, QCountBadgeKey);
            if (sibBadge) {
                [sibBadge removeFromSuperview];
                objc_setAssociatedObject(sibling, QCountBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    QUpdateCountBadge(root, count, front);
}

static BOOL qRefreshingStackStates = NO;
static BOOL qStackRefreshScheduled = NO;
static CFAbsoluteTime qLastStackRefresh = 0;

// Fold/unfold animations move the stacked cards via transforms, which do not
// trigger the card views' own layout passes, so the count badge can go stale
// (e.g. not appearing right after folding). Refresh the badge when the cell
// or the list lays out. Throttled: layout can fire many times per second
// during scrolling, and each refresh walks all notifications (O(n²) worst
// case on the main thread). 150ms is plenty for badge freshness.
static void QRefreshStackStatesIn(UIView *container) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (!container.window || qRefreshingStackStates) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - qLastStackRefresh < 0.15) {
        // Trailing pass: the last layout of a fold animation must still update the badge.
        if (qStackRefreshScheduled) return;
        qStackRefreshScheduled = YES;
        __weak UIView *weakContainer = container;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.16 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            qStackRefreshScheduled = NO;
            QRefreshStackStatesIn(weakContainer);
        });
        return;
    }
    qLastStackRefresh = now;
    qRefreshingStackStates = YES;
    for (UIView *root in qActiveNotifications.allObjects) {
        if (!root.window) continue;
        BOOL inside = NO;
        for (UIView *a = root; a && ![a isKindOfClass:UIWindow.class]; a = a.superview) {
            if (a == container) { inside = YES; break; }
        }
        if (inside) QUpdateStackState(root);
    }
    qRefreshingStackStates = NO;
}

static void QStyle(UIView *root) {
    if (!root) return;
    [qActiveNotifications addObject:root];
    QUpdateStackState(root);
}

@interface PLPlatterView : UIView
@end
@interface MTMaterialView : UIView
@end
extern "C" void QInstallNativeArtworkHooks(void);

%group QNotifications
%hook NCNotificationShortLookViewController

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    if (previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle)
        return;
    UIView *view = self.view;
    UIView *preview = [self respondsToSelector:@selector(viewForPreview)]
        ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(viewForPreview)) : nil;
    QStyle(preview ?: view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *preview = nil;
    if ([self respondsToSelector:@selector(viewForPreview)]) {
        preview = ((id (*)(id, SEL))objc_msgSend)(self, @selector(viewForPreview));
    }
    QStyle(preview ?: self.view);
    if (QIsDesktopBanner(self.view)) {
        UIView *surface = QBannerSurface(preview ?: self.view);
        if (surface) {
            [qActiveBanners addObject:surface];
            QApplyBannerScaling(surface);
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIView *view = self.view;
    UIView *preview = [self respondsToSelector:@selector(viewForPreview)]
        ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(viewForPreview)) : nil;
    if (QIsLockScreenNotification(preview ?: view)) QStyle(preview ?: view);
    if (!QIsDesktopBanner(view)) return;
    UIView *surface = QBannerSurface(view);
    if (!surface) return;
    [qActiveBanners addObject:surface];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        QApplyBannerScaling(surface);
    });
}

%end
%end

#pragma mark - 锁屏通知列表等比缩放

static CGFloat QShrinkScale(void) {
    if (![qSettings[@"masterEnabled"] boolValue] ||
        ![qSettings[@"enabled"] boolValue] ||
        [qSettings[@"disableListScaling"] boolValue]) return 1.0;
    id raw = qSettings[@"widthScale"];
    if (![raw isKindOfClass:NSNumber.class]) return 1.0;
    CGFloat scale = [raw doubleValue];
    return isfinite(scale) && scale > 0 ? MIN(1.0, MAX(0.7, scale)) : 1.0;
}

static void QApplyBannerScaling(UIView *banner) {
    if (!banner || !banner.window) return;
    CGFloat scale = [qSettings[@"scaleBanners"] boolValue] ? QShrinkScale() : 1.0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:banner];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        if ([NSStringFromClass(view.class) containsString:@"MTShadowView"]) {
            NSNumber *originalHidden = objc_getAssociatedObject(view, QBannerShadowHiddenKey);
            if (scale < 1.0) {
                if (!originalHidden)
                    objc_setAssociatedObject(view, QBannerShadowHiddenKey, @(view.hidden),
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                view.hidden = YES;
            } else if (originalHidden) {
                view.hidden = originalHidden.boolValue;
                objc_setAssociatedObject(view, QBannerShadowHiddenKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        [queue addObjectsFromArray:view.subviews];
    }
    NSValue *owned = objc_getAssociatedObject(banner, QBannerOwnedTransformKey);
    NSValue *original = objc_getAssociatedObject(banner, QBannerOriginalTransformKey);
    CATransform3D current = banner.layer.sublayerTransform;
    if (scale >= 1.0) {
        if (owned && original && CATransform3DEqualToTransform(current, owned.CATransform3DValue))
            banner.layer.sublayerTransform = original.CATransform3DValue;
        objc_setAssociatedObject(banner, QBannerOwnedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(banner, QBannerOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!owned) {
        if (!CATransform3DIsIdentity(current)) return;
        objc_setAssociatedObject(banner, QBannerOriginalTransformKey,
                                 [NSValue valueWithCATransform3D:current],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!CATransform3DEqualToTransform(current, owned.CATransform3DValue)) {
        return;
    }
    CATransform3D target = CATransform3DMakeScale(scale, scale, 1.0);
    if (CATransform3DEqualToTransform(current, target)) return;
    objc_setAssociatedObject(banner, QBannerOwnedTransformKey,
                             [NSValue valueWithCATransform3D:target],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    banner.layer.sublayerTransform = target;
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
// 返回 YES：已应用，或无需应用（非 SpringBoard / 非最外层列表 / 缩放关闭）。
// 返回 NO：系统正占用这一层的 sublayerTransform，调用方应稍后重试，而不是丢弃。
static BOOL QApplyListScaling(UIView *list) {
    if (!list || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return YES;
    QUpdateScrollIndicator(list);
    for (UIView *ancestor = list.superview; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) containsString:@"NCNotificationListView"]) {
            QClearOwnLayerTransform(list);
            return YES;
        }
    }
    CGFloat scale = QShrinkScale();
    if (scale >= 1.0) { QClearOwnLayerTransform(list); return YES; }
    NSValue *owned = objc_getAssociatedObject(list, QOwnLayerTransformKey);
    if (!owned) {
        CATransform3D original = list.layer.sublayerTransform;
        if (!CATransform3DIsIdentity(original)) return NO;
        objc_setAssociatedObject(list, QOriginalLayerTransformKey,
                                 [NSValue valueWithCATransform3D:original],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!CATransform3DEqualToTransform(list.layer.sublayerTransform,
                                              owned.CATransform3DValue)) {
        return NO; // 系统正在修改这一层，不覆盖系统的变换，稍后重试。
    }
    CATransform3D target = CATransform3DMakeScale(scale, scale, 1);
    if (CATransform3DEqualToTransform(list.layer.sublayerTransform, target)) return YES;
    objc_setAssociatedObject(list, QOwnLayerTransformKey,
                             [NSValue valueWithCATransform3D:target],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.layer.sublayerTransform = target;
    return YES;
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

static __attribute__((unused)) BOOL QIsRightCoverSheetPan(UIScrollView *scrollView) {
    if (![qSettings[@"masterEnabled"] boolValue] || !QIsCoverSheetScroll(scrollView) ||
        !scrollView.window) return NO;
    UIPanGestureRecognizer *pan = scrollView.panGestureRecognizer;
    CGPoint location = [pan locationInView:scrollView.window];
    CGPoint translation = [pan translationInView:scrollView.window];
    return location.x - translation.x >= CGRectGetMidX(scrollView.window.bounds);
}

static BOOL QScrollableNotificationsAtTop(UIWindow *window, BOOL *hasScrollableList) {
    BOOL scrollable = NO;
    for (UIView *list in qActiveLists.allObjects) {
        if (list.window != window || ![list isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *scroll = (UIScrollView *)list;
        CGFloat top = -scroll.adjustedContentInset.top;
        if (scroll.contentSize.height > scroll.bounds.size.height + 24) scrollable = YES;
        if (scroll.contentOffset.y > top + 8) {
            if (hasScrollableList) *hasScrollableList = scrollable;
            return NO;
        }
    }
    if (hasScrollableList) *hasScrollableList = scrollable;
    return YES;
}

static BOOL QTouchOnNotificationCell(UIWindow *window, CGPoint start) {
    UIView *hit = [window hitTest:start withEvent:nil];
    for (UIView *view = hit; view && view != window; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"NCNotificationListCell"] ||
            [name containsString:@"NCNotificationShortLookView"] ||
            [name containsString:@"CSActivityItem"]) return YES;
    }
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
    if (![qSettings[@"masterEnabled"] boolValue] || !QIsCoverSheetScroll(pan.view)) return;
    UIWindow *window = pan.view.window;
    if (!window) return;
    CGPoint delta = [pan translationInView:window];
    NSNumber *eligible = objc_getAssociatedObject(pan, QSearchPanEligibleKey);
    if (!eligible && (pan.state == UIGestureRecognizerStateBegan ||
                      pan.state == UIGestureRecognizerStateChanged)) {
        CGPoint start = [pan locationInView:window];
        start.x -= delta.x;
        start.y -= delta.y;
        BOOL scrollable = NO;
        BOOL atTop = QScrollableNotificationsAtTop(window, &scrollable);
        BOOL allowed = QIsLockScreenVisible() && [qSettings[@"clearAllEnabled"] boolValue] &&
            start.x >= CGRectGetMidX(window.bounds) && atTop &&
            (!scrollable || !QTouchOnNotificationCell(window, start));
        eligible = @(allowed);
        objc_setAssociatedObject(pan, QSearchPanEligibleKey, eligible, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!allowed) qLastRightSwipe = 0;
    }
    if (pan.state == UIGestureRecognizerStateChanged && eligible.boolValue) {
        if (delta.y >= 95 && delta.y > fabs(delta.x) * 1.5)
            objc_setAssociatedObject(pan, QSearchPanQualifiedKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded &&
        pan.state != UIGestureRecognizerStateCancelled &&
        pan.state != UIGestureRecognizerStateFailed) return;
    BOOL completed = pan.state == UIGestureRecognizerStateEnded && eligible.boolValue &&
        [objc_getAssociatedObject(pan, QSearchPanQualifiedKey) boolValue] &&
        QScrollableNotificationsAtTop(window, NULL);
    objc_setAssociatedObject(pan, QSearchPanEligibleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(pan, QSearchPanQualifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!completed) { qLastRightSwipe = 0; return; }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (qLastRightSwipe > 0 && now - qLastRightSwipe <= 1.8) {
        qLastRightSwipe = 0;
        if (QClearOrdinaryNotifications() &&
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
    if (QIsRightCoverSheetPan(scrollView)) {
        UIPanGestureRecognizer *pan = scrollView.panGestureRecognizer;
        if (!objc_getAssociatedObject(pan, QSearchPanInstalledKey)) {
            [pan addTarget:[QSearchPanHelper shared] action:@selector(track:)];
            objc_setAssociatedObject(pan, QSearchPanInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [[QSearchPanHelper shared] track:pan];
        return; // Right-half swipe is reserved for the clear gesture.
    }
    %orig;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (QIsRightCoverSheetPan(scrollView)) {
        [[QSearchPanHelper shared] track:scrollView.panGestureRecognizer];
        return;
    }
    %orig;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity {
    if (QIsRightCoverSheetPan(scrollView)) return;
    %orig;
}

- (BOOL)_canPresent {
    UIScrollView *tracked = [self respondsToSelector:@selector(trackingScrollView)]
        ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(trackingScrollView)) : nil;
    UIPanGestureRecognizer *pan = tracked.panGestureRecognizer;
    if ((pan.state == UIGestureRecognizerStateBegan ||
         pan.state == UIGestureRecognizerStateChanged) && QIsRightCoverSheetPan(tracked)) return NO;
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

@interface CSCombinedListViewController : UIViewController
@end

@interface CSCoverSheetView : UIView
@end

@interface NCNotificationStructuredSectionList : NSObject
@end

@interface UIView (QListAnchorProbe)
- (BOOL)layoutFromBottom;
- (void)setLayoutFromBottom:(BOOL)layoutFromBottom;
@end

static void *QListRequestedFromBottomKey = &QListRequestedFromBottomKey;
static void *QListInsetRefreshKey = &QListInsetRefreshKey;
static void *QListAnchorBottomKey = &QListAnchorBottomKey;
static void *QListInsetPendingKey = &QListInsetPendingKey;
static __weak UIView *qAnchorRootList;

// Only the cover-sheet root list (lock screen and Notification Center) is re-anchored; nested group lists keep theirs.
static BOOL QIsCoverSheetRootList(UIView *list) {
    if (!list.window || ![NSStringFromClass(list.class) isEqualToString:@"NCNotificationListView"]) return NO;
    for (UIView *ancestor = list.superview; ancestor; ancestor = ancestor.superview)
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"NCNotificationListView"]) return NO;
    return QHasAncestor(list, @"CSCoverSheetViewBase");
}

static BOOL QListAnchorEnabled(UIView *list) {
    return [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"notificationsFromTop"] boolValue] &&
           QIsCoverSheetRootList(list);
}

static id QListResponder(UIView *list, NSString *className) {
    for (UIResponder *responder = list.nextResponder; responder; responder = responder.nextResponder)
        if ([NSStringFromClass(responder.class) isEqualToString:className]) return responder;
    return nil;
}

static BOOL QSend(id target, SEL selector) {
    return [target respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
}

// Collapsed states keep the native layout: the incoming notifications folded into a stack sit at the
// bottom as usual, and a further swipe down hides them into the count. Only the expanded list starts
// under the clock and widgets.
static BOOL QListCollapsed(UIView *list) {
    id structured = QListResponder(list, @"NCNotificationStructuredListViewController");
    id master = [structured respondsToSelector:@selector(masterList)]
        ? ((id (*)(id, SEL))objc_msgSend)(structured, @selector(masterList)) : nil;
    id incoming = [master respondsToSelector:@selector(incomingSectionList)]
        ? ((id (*)(id, SEL))objc_msgSend)(master, @selector(incomingSectionList)) : nil;
    // With no incoming notifications (only the player or Live Activities) there is no stack to fold,
    // although the stack display style still reports the section as grouped: start under the widgets.
    SEL count = @selector(notificationCount);
    if ([incoming respondsToSelector:count] && ((NSUInteger (*)(id, SEL))objc_msgSend)(incoming, count) == 0) return NO;
    if (QSend(QListResponder(list, @"CSCombinedListViewController"), @selector(notificationListHidden))) return YES;
    return QSend(incoming, @selector(isSectionListCurrentlyGroupedWithContentShown)) ||
           QSend(incoming, @selector(isSectionListViewGroupedWithContentShown));
}

// MediaRemoteUI reports when the large artwork is expanded; the native layout then puts the player
// back at the bottom under the artwork, so the list leaves the top anchor until it collapses.
static BOOL qLargeArtworkExpanded;

static BOOL QListAnchoredToTop(UIView *list) {
    return QListAnchorEnabled(list) && !QListCollapsed(list) && !qLargeArtworkExpanded;
}

// Lowest visible clock, date or widget edge on the cover sheet, in the list's coordinates; NAN when it
// cannot be measured. Scrolling pushes the whole date view away (its frame and transform) and fades the
// rows, so it is only measured while the date view sits at its resting place; callers keep the last value.
static CGFloat QCoverSheetContentBottom(UIView *list) {
    CGFloat bottom = NAN;
    for (UIView *dateView in qLockClockViews.allObjects) {
        if (dateView.window != list.window) continue;
        if (!CGAffineTransformIsIdentity(dateView.transform) || fabs(dateView.frame.origin.y) > 0.5) return NAN;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:dateView];
        for (NSUInteger i = 0; i < queue.count && i < 120; i++) {
            UIView *node = queue[i];
            if (node.hidden) continue;
            // Only hidden subtrees are skipped: the widget row sits under a zero-alpha container
            // (the system renders it through vibrancy), so alpha only rules out the edge view itself.
            [queue addObjectsFromArray:node.subviews];
            if (node.alpha < 0.01 || CGRectIsEmpty(node.bounds)) continue;
            NSString *name = NSStringFromClass(node.class);
            UIView *edge = nil;
            if ([name isEqualToString:@"CSProminentEmptyElementView"] ||
                [name isEqualToString:@"CSProminentSubtitleDateView"]) edge = node;
            else if ([node isKindOfClass:UILabel.class] &&
                     ([NSStringFromClass(node.superview.class) isEqualToString:@"CSProminentTimeView"] ||
                      objc_getAssociatedObject(dateView, QLockClockLabelKey) == node)) edge = node;
            if (!edge) continue;
            CGFloat y = CGRectGetMaxY([edge convertRect:edge.bounds toView:list]) - list.bounds.origin.y;
            if (isfinite(y) && (isnan(bottom) || y > bottom)) bottom = y;
        }
    }
    return bottom;
}

static UIView *QCoverSheetRootListIn(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count && i < 40; i++) {
        if (QIsCoverSheetRootList(queue[i])) return queue[i];
        [queue addObjectsFromArray:queue[i].subviews];
    }
    return nil;
}

// The first row sits about 25pt below the inset, so this leaves roughly 18pt under the widgets.
// Uses the edge measured while the list was at rest: scrolling pushes the widgets up, and an
// inset that tracked their live position would feed back into the layout and make them jitter.
static CGFloat QAnchoredTopInset(UIView *list, CGFloat nativeTop) {
    NSNumber *bottom = objc_getAssociatedObject(list, QListAnchorBottomKey);
    if (!bottom) return nativeTop;
    return MAX(0, MIN(nativeTop, bottom.doubleValue - 8));
}

static BOOL QListAtRest(UIScrollView *scroll) {
    return scroll && !scroll.tracking && !scroll.dragging && !scroll.decelerating &&
           fabs(scroll.contentOffset.y + scroll.contentInset.top) < 1;
}

static UIViewController *QCombinedListController(UIView *list) {
    for (UIResponder *responder = list.nextResponder; responder; responder = responder.nextResponder)
        if ([NSStringFromClass(responder.class) isEqualToString:@"CSCombinedListViewController"])
            return (UIViewController *)responder;
    return nil;
}

// Anchored, the header (clock, date, widgets) is pushed from the first point of scroll. 1:1 it would
// still be half on screen when the list rests at the system's "date hidden" offset, so the push is
// scaled to finish exactly there: one continuous motion, never a partly hidden resting header.
static CGPoint QAnchoredDateOffset(UIView *coverSheet, CGPoint offset) {
    UIView *list = qAnchorRootList;
    if (offset.y <= 0 || !list || list.window != coverSheet.window || !QListAnchoredToTop(list) ||
        ![list isKindOfClass:UIScrollView.class]) return offset;
    NSNumber *bottom = objc_getAssociatedObject(list, QListAnchorBottomKey);
    UIViewController *controller = QCombinedListController(list);
    SEL resting = @selector(defaultRestingOffsetExcludingAdjunct);
    if (!bottom || ![controller respondsToSelector:resting]) return offset;
    CGFloat hiddenPush = ((CGFloat (*)(id, SEL))objc_msgSend)(controller, resting) +
                         ((UIScrollView *)list).contentInset.top;
    if (!isfinite(hiddenPush) || hiddenPush < 1) return offset;
    offset.y *= MAX(1, (bottom.doubleValue + 12) / hiddenPush);
    return offset;
}

static void QRefreshListInsets(UIView *list) {
    UIViewController *controller = QCombinedListController(list);
    SEL update = @selector(_updateListViewContentInset);
    if (![controller respondsToSelector:update]) return;
    ((void (*)(id, SEL))objc_msgSend)(controller, update);
    UIScrollView *scroll = [list isKindOfClass:UIScrollView.class] ? (UIScrollView *)list : nil;
    SEL settle = @selector(settleContentOffset);
    if (scroll && !scroll.tracking && !scroll.decelerating && [controller respondsToSelector:settle])
        ((void (*)(id, SEL))objc_msgSend)(controller, settle);
}

// Coalesced and run after the current layout pass, so it never re-enters the system's own layout.
static void QScheduleListInsetRefresh(UIView *list) {
    if (!list || objc_getAssociatedObject(list, QListInsetPendingKey)) return;
    objc_setAssociatedObject(list, QListInsetPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakList = list;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongList = weakList;
        if (!strongList) return;
        objc_setAssociatedObject(strongList, QListInsetPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QRefreshListInsets(strongList);
    });
}

// The system lays the cover-sheet list out from the bottom; the toggle starts it below the clock and widgets.
static void QApplyListAnchor(UIView *list) {
    if (!list || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] ||
        ![list respondsToSelector:@selector(setLayoutFromBottom:)]) return;
    NSNumber *requested = objc_getAssociatedObject(list, QListRequestedFromBottomKey);
    if (QListAnchoredToTop(list)) {
        if (list.layoutFromBottom) {
            [list setLayoutFromBottom:YES];
            [list setNeedsLayout];
            // Expanding out of the native stack: the list still rests at the native inset's offset, which
            // the smaller anchored inset reads as a pull-down (list low, clock pushed down). Re-inset now.
            QScheduleListInsetRefresh(list);
        }
        qAnchorRootList = list;
        // Re-measure only while nothing is being scrolled (and the date view is in place, see
        // QCoverSheetContentBottom), at most twice a second; this follows widget changes such as the
        // small clock or editing the Lock Screen without touching the inset mid-gesture.
        UIScrollView *scroll = [list isKindOfClass:UIScrollView.class] ? (UIScrollView *)list : nil;
        NSNumber *last = objc_getAssociatedObject(list, QListInsetRefreshKey);
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (QListAtRest(scroll) && now - last.doubleValue > 0.5) {
            objc_setAssociatedObject(list, QListInsetRefreshKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CGFloat bottom = QCoverSheetContentBottom(list);
            NSNumber *cached = objc_getAssociatedObject(list, QListAnchorBottomKey);
            if (!isnan(bottom) && (!cached || fabs(cached.doubleValue - bottom) > 1)) {
                objc_setAssociatedObject(list, QListAnchorBottomKey, @(bottom), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                QRefreshListInsets(list);
            }
        }
    } else if (requested) {
        // Collapsing into the stack keeps the measured edge, so expanding again lands in place at once.
        if (!QListAnchorEnabled(list))
            objc_setAssociatedObject(list, QListAnchorBottomKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(list, QListRequestedFromBottomKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (list.layoutFromBottom != requested.boolValue) {
            [list setLayoutFromBottom:requested.boolValue];
            [list setNeedsLayout];
        }
        QScheduleListInsetRefresh(list);
    }
}

static void QLargeArtworkChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                 const void *object, CFDictionaryRef userInfo) {
    BOOL expanded = CFEqual(name, CFSTR("com.gushi.quart17/nativeartworkexpanded"));
    dispatch_async(dispatch_get_main_queue(), ^{
        if (qLargeArtworkExpanded == expanded) return;
        qLargeArtworkExpanded = expanded;
        for (UIView *list in qActiveLists.allObjects) {
            if (!QListAnchorEnabled(list) || QListCollapsed(list)) continue;
            // Leaving the anchor restores the system's own request; the cover-sheet list lays out from the bottom.
            if (expanded && !objc_getAssociatedObject(list, QListRequestedFromBottomKey))
                objc_setAssociatedObject(list, QListRequestedFromBottomKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                QApplyListAnchor(list);
                QRefreshListInsets(list);
                [list layoutIfNeeded];
            } completion:nil];
        }
    });
}

static void QScheduleListScaling(UIView *list) {
    if (!list || objc_getAssociatedObject(list, QScalePendingKey)) return;
    objc_setAssociatedObject(list, QScalePendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(list, QScalePendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!list.window) return;
        if (QApplyListScaling(list)) {
            objc_setAssociatedObject(list, QScaleRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        // 系统正占用这一层的 sublayerTransform（通知插入 / 锁屏呈现动画期间）：
        // 推迟重试而不是直接丢弃，否则新通知要等到下一次滑动触发 layout 才有样式。
        // 重试有上限，避免在系统长期占用时与其打架；从不覆盖系统的变换，只等它用完。
        NSInteger retries = [objc_getAssociatedObject(list, QScaleRetryKey) integerValue];
        if (retries >= 10 || !list.window) return;
        objc_setAssociatedObject(list, QScaleRetryKey, @(retries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            QScheduleListScaling(list);
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
    QRefreshStackStatesIn((UIView *)self);
}

%end

%hook NCNotificationListView

- (void)setLayoutFromBottom:(BOOL)layoutFromBottom {
    if (!QListAnchoredToTop((UIView *)self)) {
        %orig;
        return;
    }
    // Keep the system's request so turning the option off restores it exactly.
    objc_setAssociatedObject(self, QListRequestedFromBottomKey, @(layoutFromBottom), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(NO);
}

- (void)didMoveToWindow {
    %orig;
    QApplyListAnchor((UIView *)self);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    UIScrollView *scroll = (UIScrollView *)self;
    if ([scroll isKindOfClass:UIScrollView.class] && gesture == scroll.panGestureRecognizer &&
        QPanBelongsToPlayer(scroll, scroll.panGestureRecognizer)) return NO;
    return %orig;
}

- (void)layoutSubviews {
    QApplyListAnchor((UIView *)self);
    %orig;
    QRefreshStackStatesIn((UIView *)self);
}

%end

%hook CSCombinedListViewController

// The native top inset reserves room for the full-size clock; an anchored list starts under the widgets instead.
- (UIEdgeInsets)_listViewDefaultContentInsets {
    UIEdgeInsets insets = %orig;
    // Called on scroll paths too, so it reads the cached root list and measured edge only.
    UIView *list = qAnchorRootList;
    if (!list || QCombinedListController(list) != (UIViewController *)self)
        list = QCoverSheetRootListIn(((UIViewController *)self).viewIfLoaded);
    if (list && QListAnchoredToTop(list)) insets.top = QAnchoredTopInset(list, insets.top);
    return insets;
}

- (void)_setNotificationListHidden:(BOOL)hidden forReason:(id)reason {
    %orig;
    for (UIView *list in qActiveLists.allObjects) QApplyListAnchor(list);
}

%end

%hook NCNotificationStructuredSectionList

// Folding into the stack or expanding out of it switches between native and anchored layout.
- (void)setSectionListViewGroupedWithContentShown:(BOOL)grouped {
    %orig;
    for (UIView *list in qActiveLists.allObjects) QApplyListAnchor(list);
}

%end

%hook CSCoverSheetView

- (void)setDateViewOffset:(CGPoint)offset scale:(CGFloat)scale {
    %orig(QAnchoredDateOffset((UIView *)self, offset), scale);
}

- (void)setDateViewOffset:(CGPoint)offset {
    %orig(QAnchoredDateOffset((UIView *)self, offset));
}

%end
%end
// iOS 17 renders Now Playing in MediaRemoteUI's activity scene, where QCompactPlayer draws the player.
// iOS 16 hosts the media controls inside SpringBoard, so the player is overlaid here instead.
static BOOL QUsesSpringBoardPlayer(void) {
    static BOOL value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        value = ![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}];
    });
    return value;
}

// Remote Now Playing and Live Activities share the same view containers.
// 1 = Now Playing, 0 = another activity, -1 = host or descriptor not attached yet.
static NSInteger QNowPlayingPlatterState(UIView *platter) {
    BOOL hasLocalMedia = QFind(platter, @"MRUNowPlayingLabelView") ||
                         QFind(platter, @"MRUNowPlayingTimeControlsView");
    // On iOS 16 the local media views are the only reliable signal (no activity descriptor chain).
    if (QUsesSpringBoardPlayer()) return hasLocalMedia ? 1 : 0;
    UIView *content = QFind(platter, @"CSActivityItemContentView");
    if (!content) return -1;
    id identity = content.nextResponder;
    SEL selectors[] = { @selector(activityHostViewController), @selector(activitySceneDescriptor),
                        @selector(activityDescriptor), @selector(platterTargetBundleIdentifier) };
    for (SEL selector : selectors) {
        if (!identity) return hasLocalMedia ? 1 : -1;
        // Older local MRU hosts do not expose the ActivityUI descriptor chain.
        if (![identity respondsToSelector:selector]) return hasLocalMedia ? 1 : 0;
        identity = ((id (*)(id, SEL))objc_msgSend)(identity, selector);
    }
    if (!identity) return -1;
    return [identity isKindOfClass:NSString.class] &&
           [identity isEqualToString:@"com.apple.MediaRemoteUI"] ? 1 : 0;
}

static void *QPlayerChromeAlphaKey = &QPlayerChromeAlphaKey;
static void *QPlayerChromeVisibilityKey = &QPlayerChromeVisibilityKey;
static void *QPlatterChromeHiddenKey = &QPlatterChromeHiddenKey;
static void *QPlatterRetryKey = &QPlatterRetryKey;

static BOOL QIsPlatterMaterial(UIView *view) {
    return [NSStringFromClass(view.class) isEqualToString:@"MTMaterialView"];
}

// Requested alpha and hidden state are kept on the material so SpringBoard's own writes survive
// suppression. Always-On Display changes the material's layer opacity directly, so alpha alone is not enough.
static BOOL QMaterialSuppressed(UIView *material) {
    UIView *platter = material.superview;
    return platter && [objc_getAssociatedObject(platter, QPlatterChromeHiddenKey) boolValue];
}

static void *QSpringBoardPlayerKey = &QSpringBoardPlayerKey;

// iOS 16: the player sits beside the native platter in its container. The platter is hidden through
// its layer's opacity so UIView alpha stays 1 and touches still reach the native controls.
static void QLayoutSpringBoardPlayer(UIView *platter, BOOL show) {
    QPlayerView *player = objc_getAssociatedObject(platter, QSpringBoardPlayerKey);
    UIView *container = platter.superview;
    if (!show || !container) {
        if (!player) return;
        [player removeFromSuperview];
        objc_setAssociatedObject(platter, QSpringBoardPlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        platter.layer.opacity = 1;
        return;
    }
    if (!player) {
        player = [[QPlayerView alloc] initWithFrame:CGRectZero];
        [player setSuppressSiblingViews:NO];
        [player setUsesNativeMetadataFallback:NO];
        objc_setAssociatedObject(platter, QSpringBoardPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (player.superview != container) [container addSubview:player];
    // Stay inside the cell; the cell's own transform scales the player with the list.
    UIView *cell = platter;
    while (cell && ![NSStringFromClass(cell.class) isEqualToString:@"NCNotificationListCell"]) cell = cell.superview;
    CGRect safeRect = cell ? [cell convertRect:cell.bounds toView:container] : container.bounds;
    CGSize size = platter.bounds.size;
    CGFloat height = MIN(88, MAX(50, safeRect.size.height - 8));
    CGRect frame = [platter convertRect:CGRectMake(0, (size.height - height) * 0.5, size.width, height)
                                 toView:container];
    if (!CGRectIsEmpty(safeRect)) {
        frame.origin.y = MIN(frame.origin.y, CGRectGetMaxY(safeRect) - frame.size.height - 4);
        frame.origin.y = MAX(frame.origin.y, CGRectGetMinY(safeRect) + 4);
    }
    CGFloat scale = UIScreen.mainScreen.scale;
    player.frame = CGRectMake(round(frame.origin.x * scale) / scale, round(frame.origin.y * scale) / scale,
                              round(frame.size.width * scale) / scale, round(frame.size.height * scale) / scale);
    [player applySettings:qSettings];
    [player seedFromNativePlayer:platter];
    [container bringSubviewToFront:player];
    player.hidden = NO;
    platter.alpha = 1;
    platter.layer.opacity = 0;
}

// The list's vertical pan and the player's seek pan race for the same touch. A few points of vertical
// drift let the list win first and cancel the player's touches (in MediaRemoteUI on iOS 17), so only
// perfectly horizontal drags could seek. Yield the list pan when it starts where the player would seek
// and moves the way the player accepts (QPlayerView's |dx| > |dy| / 2); steeper drags still scroll.
static BOOL QPanBelongsToPlayer(UIScrollView *scroll, UIPanGestureRecognizer *pan) {
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"playerEnabled"] boolValue] ||
        ![qSettings[@"showProgress"] boolValue] || !scroll.window) return NO;
    CGPoint moved = [pan translationInView:nil];
    if (!(fabs(moved.x) > fabs(moved.y) * 0.5)) return NO;
    CGPoint now = [pan locationInView:nil];
    CGPoint start = CGPointMake(now.x - moved.x, now.y - moved.y);
    for (UIView *platter in qActivePlatters.allObjects) {
        if (platter.window != scroll.window) continue;
        UIView *player = objc_getAssociatedObject(platter, QSpringBoardPlayerKey);
        CGRect rect;
        if (player) {
            rect = [player convertRect:player.bounds toView:nil];
        } else if ([objc_getAssociatedObject(platter, QPlatterChromeHiddenKey) boolValue]) {
            // Same placement as QCompactPlayer: up to 88pt tall, centred in the native host.
            CGSize size = platter.bounds.size;
            CGFloat height = MIN(88, MAX(0, size.height - 8));
            rect = [platter convertRect:CGRectMake(0, (size.height - height) / 2, size.width, height) toView:nil];
        } else {
            continue;
        }
        CGFloat c = rect.size.height / 88.0;
        // Playback buttons and the route picker keep their own touches.
        rect.size.width = MAX(0, rect.size.width - 118 * c);
        if ([qSettings[@"progressStyle"] integerValue] == 1) {
            // Bottom bar style seeks on the bar only.
            rect.origin.y = CGRectGetMaxY(rect) - 31 * c;
            rect.size.height = 31 * c;
        }
        if (CGRectContainsPoint(rect, start)) return YES;
    }
    return NO;
}

static void QApplyPlatterChrome(UIView *platter, NSUInteger attempt) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    BOOL candidate = QHasAncestor(platter, @"NCNotificationListCell") &&
                     QHasAncestor(platter, @"NCNotificationListSupplementaryHostingView");
    NSInteger state = candidate ? QNowPlayingPlatterState(platter) : 0;
    BOOL enabled = [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"playerEnabled"] boolValue];
    BOOL mediaPlatter = state == 1;
    if (mediaPlatter) [qActivePlatters addObject:platter];
    BOOL wasHidden = [objc_getAssociatedObject(platter, QPlatterChromeHiddenKey) boolValue];
    // A verified media platter keeps its state while the remote host is briefly detached.
    BOOL hideChrome = enabled && (mediaPlatter || (state < 0 && wasHidden && platter.window));
    if (QUsesSpringBoardPlayer()) {
        // The whole platter is hidden instead; the material guard must stay off so nothing is left at alpha 0.
        QLayoutSpringBoardPlayer(platter, hideChrome);
        return;
    }
    objc_setAssociatedObject(platter, QPlatterChromeHiddenKey, hideChrome ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *view in platter.subviews) {
        if (!QIsPlatterMaterial(view)) continue;
        NSNumber *original = objc_getAssociatedObject(view, QPlayerChromeAlphaKey);
        NSNumber *originalHidden = objc_getAssociatedObject(view, QPlayerChromeVisibilityKey);
        if (hideChrome) {
            [view setAlpha:original ? original.doubleValue : view.alpha];
            [view setHidden:originalHidden ? originalHidden.boolValue : view.hidden];
        } else {
            if (original) {
                objc_setAssociatedObject(view, QPlayerChromeAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                view.alpha = original.doubleValue;
            }
            if (originalHidden) {
                objc_setAssociatedObject(view, QPlayerChromeVisibilityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                view.hidden = originalHidden.boolValue;
            }
        }
    }
    // The activity descriptor chain is filled in after the first layout; re-check without waiting for one.
    if (state < 0 && platter.window && attempt < 8) {
        NSObject *token = [NSObject new];
        objc_setAssociatedObject(platter, QPlatterRetryKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakPlatter = platter;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * (attempt + 1) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *strongPlatter = weakPlatter;
            if (!strongPlatter || objc_getAssociatedObject(strongPlatter, QPlatterRetryKey) != token) return;
            QApplyPlatterChrome(strongPlatter, attempt + 1);
        });
    } else {
        objc_setAssociatedObject(platter, QPlatterRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%group QHostPlatter
%hook PLPlatterView

- (void)layoutSubviews {
    %orig;
    QApplyPlatterChrome(self, 0);
}

- (void)didMoveToWindow {
    %orig;
    QApplyPlatterChrome(self, 0);
}

- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (QIsPlatterMaterial(subview)) QApplyPlatterChrome(self, 0);
}

%end

%hook MTMaterialView

- (void)setAlpha:(CGFloat)alpha {
    if (!QMaterialSuppressed(self)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, QPlayerChromeAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(0);
}

- (void)setHidden:(BOOL)hidden {
    if (!QMaterialSuppressed(self)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, QPlayerChromeVisibilityKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(YES);
}

%end

%end

static void QPositionLockWidget(UIView *widget, CGFloat x, CGFloat width, BOOL enabled) {
    if (!widget) return;
    NSValue *saved = objc_getAssociatedObject(widget, QLockClockOriginalFrameKey);
    NSValue *savedTransform = objc_getAssociatedObject(widget, QLockClockOriginalTransformKey);
    // 远程日期组件首次挂载可能尚无尺寸，不能缓存零尺寸作为后续缩放基准。
    if (enabled && (widget.bounds.size.width <= 0 || widget.bounds.size.height <= 0 ||
        widget.frame.size.width <= 0 || widget.frame.size.height <= 0)) return;
    if (!saved && enabled) {
        saved = [NSValue valueWithCGRect:widget.frame];
        objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        savedTransform = [NSValue valueWithCGAffineTransform:widget.transform];
        objc_setAssociatedObject(widget, QLockClockOriginalTransformKey, savedTransform, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!saved) return;
    CGRect original = saved.CGRectValue;
    NSValue *appliedTransform = objc_getAssociatedObject(widget, QLockClockAppliedTransformKey);
    NSValue *appliedCenter = objc_getAssociatedObject(widget, QLockClockAppliedCenterKey);
    BOOL hasBounds = widget.bounds.size.width > 0 && widget.bounds.size.height > 0;
    CGAffineTransform nativeTransform = savedTransform ? savedTransform.CGAffineTransformValue : widget.transform;
    if (hasBounds && appliedTransform && !CGAffineTransformEqualToTransform(widget.transform, appliedTransform.CGAffineTransformValue))
        nativeTransform = widget.transform;
    CGPoint nativeCenter = CGPointMake(CGRectGetMidX(original) - savedTransform.CGAffineTransformValue.tx,
                                       CGRectGetMidY(original) - savedTransform.CGAffineTransformValue.ty);
    if (hasBounds && appliedCenter && !CGPointEqualToPoint(widget.center, appliedCenter.CGPointValue))
        nativeCenter = widget.center;
    // Remote widgets can change bounds without creating a new host view.
    CGSize nativeSize = hasBounds ? CGRectApplyAffineTransform(widget.bounds, nativeTransform).size : original.size;
    original = CGRectMake(nativeCenter.x + nativeTransform.tx - nativeSize.width / 2,
                          nativeCenter.y + nativeTransform.ty - nativeSize.height / 2,
                          nativeSize.width, nativeSize.height);
    saved = [NSValue valueWithCGRect:original];
    savedTransform = [NSValue valueWithCGAffineTransform:nativeTransform];
    objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(widget, QLockClockOriginalTransformKey, savedTransform, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!enabled) {
        widget.transform = savedTransform.CGAffineTransformValue;
        widget.frame = saved.CGRectValue;
        objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(widget, QLockClockOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(widget, QLockClockAppliedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(widget, QLockClockAppliedCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGFloat scale = width / MAX(1, original.size.width);
    CGAffineTransform target = CGAffineTransformScale(nativeTransform, scale, scale);
    CGPoint center = CGPointMake(x + width / 2 - target.tx, CGRectGetMidY(original) - target.ty);
    objc_setAssociatedObject(widget, QLockClockAppliedTransformKey,
        [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(widget, QLockClockAppliedCenterKey,
        [NSValue valueWithCGPoint:center], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!CGAffineTransformEqualToTransform(widget.transform, target)) widget.transform = target;
    if (!CGPointEqualToPoint(widget.center, center)) widget.center = center;
}

static void QPositionLowerWidgets(UIView *widget, BOOL enabled) {
    if (!widget) return;
    NSValue *saved = objc_getAssociatedObject(widget, QLockClockOriginalFrameKey);
    if (!enabled) {
        if (saved) { widget.frame = saved.CGRectValue; objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    CGRect original = saved ? saved.CGRectValue : widget.frame;
    if (!saved || !CGRectEqualToRect(widget.frame, CGRectOffset(original, 0, -90))) {
        original = widget.frame;
        saved = [NSValue valueWithCGRect:original];
        objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect target = CGRectOffset(original, 0, -90);
    if (!CGRectEqualToRect(widget.frame, target)) widget.frame = target;
}

// Lock-clock layout runs on every pass; formatters are rebuilt only when the locale changes.
static NSDateFormatter *QLockClockFormatter(NSString *pattern) {
    static NSMutableDictionary<NSString *, NSDateFormatter *> *formatters;
    static NSString *localeID;
    NSString *current = NSLocale.currentLocale.localeIdentifier;
    if (!formatters || ![localeID isEqualToString:current]) {
        formatters = [NSMutableDictionary dictionary];
        localeID = [current copy];
    }
    NSDateFormatter *formatter = formatters[pattern];
    if (!formatter) {
        formatter = [NSDateFormatter new];
        [formatter setLocalizedDateFormatFromTemplate:pattern];
        formatters[pattern] = formatter;
    }
    return formatter;
}

// The native clock remains in the hierarchy for layout and taps. The date
// comes from the user's existing top widget, so its format stays untouched.
static void QStyleLockClock(UIView *dateView) {
    if (qStylingLockClock || !dateView.window) return;
    qStylingLockClock = YES;
    @try {
        UIView *nativeText = nil;
        UIView *topWidget = nil;
        UIView *subtitle = nil;
        UILabel *subtitleText = nil;
        UIView *bottomWidgets = nil;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:dateView];
        for (NSUInteger i = 0; i < queue.count && i < 100; i++) {
            UIView *node = queue[i];
            NSString *name = NSStringFromClass(node.class);
            if ([name isEqualToString:@"CSProminentTimeView"]) {
                for (UIView *child in node.subviews)
                    if ([child isKindOfClass:UILabel.class]) { nativeText = child; break; }
            }
            if ([name isEqualToString:@"CSProminentEmptyElementView"] && !node.hidden) {
                CGRect visibleFrame = [node convertRect:node.bounds toView:dateView];
                if (node.alpha > 0.01 && node.bounds.size.height <= 50 &&
                    CGRectIntersectsRect(visibleFrame, dateView.bounds)) topWidget = node;
                // The row fades out while scrolling pushes the date away, and the system re-lays it out
                // at its native position meanwhile; it must still be moved up, or it returns 90pt too low.
                else if (node.bounds.size.height >= 60) bottomWidgets = node;
            }
            if ([name isEqualToString:@"CSProminentSubtitleDateView"] && !node.hidden) {
                subtitle = node;
                for (UIView *child in node.subviews)
                    if ([child isKindOfClass:UILabel.class]) { subtitleText = (UILabel *)child; break; }
            }
            [queue addObjectsFromArray:node.subviews];
        }
        if (!topWidget) topWidget = subtitle;
        UIView *topContent = topWidget;
        if (topWidget != subtitle) {
            NSMutableArray<UIView *> *widgetViews = [NSMutableArray arrayWithObject:topWidget];
            for (NSUInteger i = 0; i < widgetViews.count && i < 40; i++) {
                UIView *view = widgetViews[i];
                NSString *name = NSStringFromClass(view.class);
                if ([name isEqualToString:@"CHUISWidgetHostViewControllerView"])
                    topContent = view;
                if ([name isEqualToString:@"_UISceneLayerHostContainerView"]) {
                    topContent = view;
                    break;
                }
                [widgetViews addObjectsFromArray:view.subviews];
            }
        }
        UILabel *small = objc_getAssociatedObject(dateView, QLockClockLabelKey);
        UIView *previousContent = objc_getAssociatedObject(dateView, QLockClockTopContentKey);
        if (previousContent && previousContent != topContent)
            QPositionLockWidget(previousContent, 0, 0, NO);
        objc_setAssociatedObject(dateView, QLockClockTopContentKey, topContent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL enabled = [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"smallLockClock"] boolValue];
        if (!enabled || !nativeText || !topWidget) {
            if (small) { [small removeFromSuperview]; objc_setAssociatedObject(dateView, QLockClockLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            QPositionLockWidget(topContent, 0, 0, NO);
            objc_setAssociatedObject(dateView, QLockClockTopContentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            QPositionLowerWidgets(bottomWidgets, NO);
            if (nativeText) {
                NSNumber *original = objc_getAssociatedObject(nativeText, QLockClockOriginalHiddenKey);
                if (original) { nativeText.hidden = original.boolValue; objc_setAssociatedObject(nativeText, QLockClockOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            }
            if (subtitleText) {
                NSNumber *original = objc_getAssociatedObject(subtitleText, QLockClockOriginalHiddenKey);
                if (original) { subtitleText.hidden = original.boolValue; objc_setAssociatedObject(subtitleText, QLockClockOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            }
            return;
        }
        if (!objc_getAssociatedObject(nativeText, QLockClockOriginalHiddenKey))
            objc_setAssociatedObject(nativeText, QLockClockOriginalHiddenKey, @(nativeText.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        nativeText.hidden = YES;
        CGFloat fontSize = [qSettings[@"smallLockClockFontSize"] doubleValue];
        fontSize = isfinite(fontSize) ? MAX(18, MIN(30, fontSize)) : 23;
        NSString *clock = [QLockClockFormatter(@"jm") stringFromDate:NSDate.date];
        CGFloat clockWidth = ceil([clock sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold]}].width) + 4;
        CGFloat widgetWidth = MIN(300, MAX(180, dateView.bounds.size.width - 30 - clockWidth - 12));
        CGFloat rowLeft = (dateView.bounds.size.width - clockWidth - 12 - widgetWidth) / 2;
        if (topWidget != subtitle) {
            CGFloat parentX = [topContent.superview convertPoint:CGPointMake(rowLeft + clockWidth + 32, 0)
                                                       fromView:dateView].x;
            QPositionLockWidget(topContent, parentX, widgetWidth, YES);
        }
        QPositionLowerWidgets(bottomWidgets, YES);
        UIView *textHost = nativeText.superview.superview ?: nativeText.superview;
        if (!small) {
            small = [[UILabel alloc] initWithFrame:CGRectZero];
            small.userInteractionEnabled = NO;
            small.textAlignment = NSTextAlignmentCenter;
            small.adjustsFontSizeToFitWidth = YES;
            small.minimumScaleFactor = 0.8;
            objc_setAssociatedObject(dateView, QLockClockLabelKey, small, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (small.superview != textHost) [textHost addSubview:small];
        CGRect topFrame = [topWidget convertRect:topWidget.bounds toView:dateView];
        CGRect frameInDate = topWidget == subtitle
            ? CGRectMake(0, CGRectGetMidY(topFrame) - 21, dateView.bounds.size.width, 42)
            : CGRectMake(rowLeft + 68, CGRectGetMidY(topFrame) - 21, clockWidth, 42);
        small.frame = [textHost convertRect:frameInDate fromView:dateView];
        UIColor *color = ((UILabel *)nativeText).textColor ?: UIColor.whiteColor;
        small.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
        small.textColor = color;
        if (topWidget == subtitle && subtitleText) {
            if (!objc_getAssociatedObject(subtitleText, QLockClockOriginalHiddenKey))
                objc_setAssociatedObject(subtitleText, QLockClockOriginalHiddenKey, @(subtitleText.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSString *date = subtitleText.text;
            NSString *normalDate = objc_getAssociatedObject(subtitleText, QLockClockNormalDateKey);
            NSDate *normalDay = objc_getAssociatedObject(subtitleText, QLockClockNormalDateDayKey);
            if (date.length && (!normalDate || (normalDay && ![NSCalendar.currentCalendar isDate:normalDay inSameDayAsDate:NSDate.date]))) {
                normalDate = date;
                objc_setAssociatedObject(subtitleText, QLockClockNormalDateKey, date, OBJC_ASSOCIATION_COPY_NONATOMIC);
                objc_setAssociatedObject(subtitleText, QLockClockNormalDateDayKey, NSDate.date, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            BOOL temporaryText = normalDate.length && date.length && ![date isEqualToString:normalDate];
            if (!date.length) {
                date = [QLockClockFormatter(@"MMMdEEEE") stringFromDate:NSDate.date];
            }
            // 临时提示期间日期副本会透明，必须同时显示原生文字。
            subtitleText.hidden = !temporaryText;
            NSString *shownDate = normalDate.length ? normalDate : date;
            NSMutableAttributedString *line = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@   %@", clock, shownDate]];
            [line addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium]
                         range:NSMakeRange(clock.length + 3, shownDate.length)];
            if (temporaryText)
                [line addAttribute:NSForegroundColorAttributeName value:UIColor.clearColor
                             range:NSMakeRange(clock.length + 3, shownDate.length)];
            small.attributedText = line;
        } else small.text = clock;
    } @finally { qStylingLockClock = NO; }
}

static void QRestyleLockClockForWidget(UIView *widget) {
    for (UIView *view = widget.superview; view; view = view.superview) {
        if ([view isKindOfClass:objc_getClass("SBFLockScreenDateView")]) {
            QStyleLockClock(view);
            return;
        }
    }
}

%group QSmallLockClock
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    [qLockClockViews addObject:self];
    QStyleLockClock(self);
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) { [qLockClockViews addObject:self]; QStyleLockClock(self); }
}
%end
%hook CSProminentEmptyElementView
- (void)setFrame:(CGRect)frame {
    %orig;
    if (!self.window || frame.size.height < 60) return;
    if (!qStylingLockClock) {
        QRestyleLockClockForWidget(self);
        return;
    }
    // A native relayout during our own pass would otherwise leave the row at its native position.
    // One coalesced, rate-limited retry: if the system keeps resetting the frame, this must never
    // turn into a main-thread loop.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (qLockClockRetryPending || now - qLockClockRetryAt < 0.3) return;
    qLockClockRetryPending = YES;
    __weak UIView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        qLockClockRetryPending = NO;
        qLockClockRetryAt = CFAbsoluteTimeGetCurrent();
        QRestyleLockClockForWidget(weakSelf);
    });
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) QRestyleLockClockForWidget(self);
}
- (void)layoutSubviews {
    %orig;
    QRestyleLockClockForWidget(self);
}
%end
%hook CSProminentSubtitleDateView
- (void)layoutSubviews {
    %orig;
    if (self.window && !qStylingLockClock) QRestyleLockClockForWidget(self);
}
%end
%hook _UIAnimatingLabel
- (void)setHidden:(BOOL)hidden {
    UIView *parent = self.superview;
    NSString *normalDate = objc_getAssociatedObject(self, QLockClockNormalDateKey);
    BOOL isLockDate = [parent isKindOfClass:objc_getClass("CSProminentSubtitleDateView")];
    if (!qStylingLockClock && isLockDate && normalDate.length &&
        [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"smallLockClock"] boolValue]) {
        if ([self.text isEqualToString:normalDate]) hidden = YES;
        %orig(hidden);
        QRestyleLockClockForWidget(self);
        return;
    }
    %orig(hidden);
}
%end
%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) {
            QInstallNativeArtworkHooks();
            QInstallCompactPlayerHooks();
            return;
        }
        qActivePlatters = [NSHashTable weakObjectsHashTable];
        qActiveNotifications = [NSHashTable weakObjectsHashTable];
        qActiveLists = [NSHashTable weakObjectsHashTable];
        qActiveBanners = [NSHashTable weakObjectsHashTable];
        qLockClockViews = [NSHashTable weakObjectsHashTable];
        QLoadSettings();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.quart17/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.aura/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QLargeArtworkChanged, CFSTR("com.gushi.quart17/nativeartworkexpanded"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QLargeArtworkChanged, CFSTR("com.gushi.quart17/nativeartworkcollapsed"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // Vela posts this after its icon theme changes; the player buttons follow that theme.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.vela/changed"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    QLoadSettings();
                    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                        CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
                }];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QOpenPlayingApp, CFSTR("com.gushi.quart17/openplayingapp"),
                                            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        if (objc_getClass("NCNotificationShortLookViewController")) %init(QNotifications);
        // 以下已迁至 Aura（%group 已用 #if 0 禁用，此处保留调用占位）
        // QSystemAlerts 已移至 Quart17UIKit dylib（应用进程）
        // QHeaderButtons 已迁至 Aura
        if (objc_getClass("PLPlatterView")) %init(QHostPlatter);
        if (objc_getClass("NCNotificationListCell")) %init(QScale);
        if (objc_getClass("NCNotificationMasterList")) %init(QMasterGesture);
        if (objc_getClass("SBSearchPresenter")) %init(QSearchGesture);
        if (objc_getClass("SBFLockScreenDateView")) {
            %init(QSmallLockClock);
            // Fire just after each minute boundary so the small clock never lags the system clock.
            NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
            NSDate *nextMinute = [NSDate dateWithTimeIntervalSinceReferenceDate:floor(now / 60) * 60 + 60.05];
            NSTimer *clockTimer = [[NSTimer alloc] initWithFireDate:nextMinute interval:60 repeats:YES
                block:^(__unused NSTimer *timer) {
                    for (UIView *dateView in qLockClockViews.allObjects) QStyleLockClock(dateView);
                }];
            clockTimer.tolerance = 0.2;
            [NSRunLoop.mainRunLoop addTimer:clockTimer forMode:NSRunLoopCommonModes];
        }
    }
}
