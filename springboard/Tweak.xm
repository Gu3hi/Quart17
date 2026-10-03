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
static BOOL qNativeArtworkExpanded;
static NSHashTable<QPlayerView *> *qActivePlayers;

static NSHashTable<UIView *> *qActivePlatters;
static NSHashTable<UIView *> *qActiveNotifications;
static NSHashTable<UIView *> *qActiveLists;
static NSHashTable<UIView *> *qActiveBanners;
static NSHashTable<UIView *> *qLockClockViews;
static void *QLockClockLabelKey = &QLockClockLabelKey;
static void *QLockClockOriginalHiddenKey = &QLockClockOriginalHiddenKey;
static void *QLockClockOriginalFrameKey = &QLockClockOriginalFrameKey;
static void *QLockClockOriginalTransformKey = &QLockClockOriginalTransformKey;
static void *QLockClockTopContentKey = &QLockClockTopContentKey;
static void *QLockClockNormalDateKey = &QLockClockNormalDateKey;
static void *QLockClockNormalDateDayKey = &QLockClockNormalDateDayKey;
static BOOL qStylingLockClock;
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
static void *QNotificationCornerOriginalKey = &QNotificationCornerOriginalKey;

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
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    qSettings = [@{ @"masterEnabled": @YES, @"enabled": @YES,
                    @"smallLockClock": @NO,
                    @"smallLockClockFontSize": @23,
                    @"playerEnabled": @YES, @"disableListScaling": @NO,
                     @"scaleBanners": @NO,
                    @"showNotificationCount": @YES,
                    @"largeArtworkOffsetY": @0,
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
    if (!qSettings[@"largeArtworkRoundness"])
        qSettings[@"largeArtworkRoundness"] = qSettings[@"playerCornerRoundness"];
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
    int offsetToken = -1;
    if (notify_register_check("com.gushi.quart17/artworkoffset", &offsetToken) == NOTIFY_STATUS_OK) {
        double offset = [qSettings[@"largeArtworkOffsetY"] doubleValue];
        offset = isfinite(offset) ? MAX(-200, MIN(200, offset)) : 0;
        notify_set_state(offsetToken, (uint64_t)llround((offset + 200) * 100) + 1);
        notify_cancel(offsetToken);
    }
    int flagsToken = -1;
    if (notify_register_check("com.gushi.quart17/artworkflags", &flagsToken) == NOTIFY_STATUS_OK) {
        notify_set_state(flagsToken, 0x51710000ULL |
            ([qSettings[@"masterEnabled"] boolValue] ? 1ULL : 0) |
            ([qSettings[@"playerEnabled"] boolValue] ? 2ULL : 0) |
            ([qSettings[@"showProgress"] boolValue] ? 4ULL : 0));
        notify_cancel(flagsToken);
    }
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
        for (QPlayerView *player in qActivePlayers.allObjects) {
            [player applySettings:qSettings];
            [player refresh];
            [player setNeedsLayout];
            [player layoutIfNeeded];
        }
        for (UIView *platter in qActivePlatters.allObjects) {
            [platter setNeedsLayout];
            [platter layoutIfNeeded];
        }
        for (UIView *notification in qActiveNotifications.allObjects) QStyle(notification);
        for (UIView *list in qActiveLists.allObjects) QScheduleListScaling(list);
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

static void QNativeArtworkVisibilityChanged(CFNotificationCenterRef center, void *observer,
                                             CFStringRef name, const void *object,
                                             CFDictionaryRef userInfo) {
    BOOL expanded = CFEqual(name, CFSTR("com.gushi.quart17/nativeartworkexpanded"));
    dispatch_async(dispatch_get_main_queue(), ^{
        qNativeArtworkExpanded = expanded;
        for (QPlayerView *player in qActivePlayers.allObjects)
            [player setExpandedArtwork:expanded];
    });
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
    if (now - qLastStackRefresh < 0.15) return;
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
    static BOOL auraLoaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *path = _dyld_get_image_name(i);
            const char *name = path ? strrchr(path, '/') : NULL;
            if (name && strcmp(name + 1, "Aura.dylib") == 0) {
                auraLoaded = YES;
                break;
            }
        }
    });
    BOOL ownsCorner = !auraLoaded && [qSettings[@"masterEnabled"] boolValue];
    CGFloat roundness = [qSettings[@"playerCornerRoundness"] doubleValue];
    roundness = isfinite(roundness) ? MAX(0, MIN(1, roundness)) : 1;
    for (UIView *view in @[root, QFind(root, @"MTMaterialView") ?: root]) {
        NSArray *original = objc_getAssociatedObject(view, QNotificationCornerOriginalKey);
        if (!ownsCorner) {
            if (original) {
                view.layer.cornerRadius = [original[0] doubleValue];
                view.clipsToBounds = [original[1] boolValue];
                view.layer.cornerCurve = original[2];
                objc_setAssociatedObject(view, QNotificationCornerOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            continue;
        }
        if (view.bounds.size.height <= 0) continue;
        if (!original)
            objc_setAssociatedObject(view, QNotificationCornerOriginalKey,
                @[@(view.layer.cornerRadius), @(view.clipsToBounds), view.layer.cornerCurve ?: kCACornerCurveCircular],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.layer.cornerRadius = view.bounds.size.height * roundness / 2;
        view.layer.cornerCurve = kCACornerCurveCircular;
        view.clipsToBounds = YES;
    }
    QUpdateStackState(root);
}

@interface PLPlatterView : UIView
@end
static void *QSpringBoardPlayerKey = &QSpringBoardPlayerKey;
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

- (void)layoutSubviews {
    %orig;
    QRefreshStackStatesIn((UIView *)self);
}

%end
%end
%group QHostPlatter
%hook PLPlatterView

- (void)layoutSubviews {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    CGSize size = self.bounds.size;
    if (size.width < 340 || size.width > 500 || size.height < 65 || size.height > 195) return;
    if (!QHasAncestor(self, @"NCNotificationListCell")) return;
    if (!QFind(self, @"CSActivityItemContentView")) return;
    QPlayerView *player = objc_getAssociatedObject(self, QSpringBoardPlayerKey);
    // 播放器识别：MRUNowPlayingLabelView / MRUNowPlayingTimeControlsView 是
    // MediaRemoteUI 原生视图，为强信号；_UISceneLayerHostContainerView 为弱
    // 信号（远程进程承载，不一定在层级里）。任一命中即视为媒体播放器。
    // QPlayerView 建出后会自验是否真有媒体在播，无媒体时自行隐藏。
    BOOL mediaPlatter = size.height >= 145 &&
                        (QFind(self, @"MRUNowPlayingLabelView") ||
                         QFind(self, @"MRUNowPlayingTimeControlsView") ||
                         QFind(self, @"_UISceneLayerHostContainerView"));
    if (!mediaPlatter && !player) {
        self.alpha = 1;
        self.layer.opacity = 1;
        return;
    }
    BOOL enabled = [qSettings[@"masterEnabled"] boolValue] && [qSettings[@"playerEnabled"] boolValue];
    if (!enabled) {
        self.alpha = 1;
        self.layer.opacity = 1;
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
        [player setExpandedArtwork:qNativeArtworkExpanded];
    }
    for (UIView *sibling in [container.subviews copy]) {
        if (sibling != player && [sibling isKindOfClass:QPlayerView.class]) [sibling removeFromSuperview];
    }
    if (player.superview != container) [container addSubview:player];
    // 播放器不再单独缩放：它位于 cell 的 contentView 之内，随 contentView 的
    // transform 一起等比缩小。若这里再乘一次 s 会得到 s²（78% 会变成约 61%）。
    // 内部度量由 QPlayerView 的 sizeFactor 按自身 bounds 推出，bounds 未受
    // transform 影响，因此内部仍按设计尺寸布局，再整体被 transform 缩下去。
    UIView *cell = self;
    while (cell && ![NSStringFromClass(cell.class) isEqualToString:@"NCNotificationListCell"])
        cell = cell.superview;
    CGRect safeRect = cell ? [cell convertRect:cell.bounds toView:container] : container.bounds;
    CGFloat height = MIN(88, MAX(50, safeRect.size.height - 8));
    // The native activity cell is taller than the compact player. Keep the
    // player inside that cell, but halve the empty space below it so the next
    // notification visually sits closer without changing list geometry.
    CGRect frame = [self convertRect:CGRectMake(0, (size.height - height) * 0.75,
                                               size.width, height) toView:container];
    if (!CGRectIsEmpty(safeRect)) {
        frame.origin.y = MIN(frame.origin.y, CGRectGetMaxY(safeRect) - frame.size.height - 4);
        frame.origin.y = MAX(frame.origin.y, CGRectGetMinY(safeRect) + 4);
    }
    CGFloat scale = UIScreen.mainScreen.scale;
    player.frame = CGRectMake(round(frame.origin.x * scale) / scale,
                              round(frame.origin.y * scale) / scale,
                              round(frame.size.width * scale) / scale,
                              round(frame.size.height * scale) / scale);
    [player applySettings:qSettings];
    [player seedFromNativePlayer:self];
    [container bringSubviewToFront:player];
    player.hidden = NO;
    // CALayer opacity hides the original platter visually while UIView alpha
    // stays at 1, so UIKit can still deliver artwork taps to its native view.
    self.alpha = 1;
    self.layer.opacity = 0;
}

%end

%end

static void QPositionLockWidget(UIView *widget, CGFloat x, CGFloat width, BOOL enabled) {
    if (!widget) return;
    NSValue *saved = objc_getAssociatedObject(widget, QLockClockOriginalFrameKey);
    NSValue *savedTransform = objc_getAssociatedObject(widget, QLockClockOriginalTransformKey);
    if (!enabled) {
        if (saved) {
            if (savedTransform) widget.transform = savedTransform.CGAffineTransformValue;
            widget.frame = saved.CGRectValue;
            objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(widget, QLockClockOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!saved) {
        saved = [NSValue valueWithCGRect:widget.frame];
        objc_setAssociatedObject(widget, QLockClockOriginalFrameKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        savedTransform = [NSValue valueWithCGAffineTransform:widget.transform];
        objc_setAssociatedObject(widget, QLockClockOriginalTransformKey, savedTransform, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect original = saved.CGRectValue;
    CGFloat scale = width / MAX(1, original.size.width);
    CGAffineTransform target = CGAffineTransformScale(savedTransform.CGAffineTransformValue, scale, scale);
    if (!CGAffineTransformEqualToTransform(widget.transform, target)) widget.transform = target;
    CGPoint center = CGPointMake(x + width / 2, CGRectGetMidY(original));
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
            if ([name isEqualToString:@"CSProminentEmptyElementView"] && !node.hidden && node.alpha > 0.01) {
                CGRect visibleFrame = [node convertRect:node.bounds toView:dateView];
                if (node.bounds.size.height <= 50 && CGRectIntersectsRect(visibleFrame, dateView.bounds)) topWidget = node;
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
        NSDateFormatter *time = [NSDateFormatter new];
        [time setLocalizedDateFormatFromTemplate:@"jm"];
        NSString *clock = [time stringFromDate:NSDate.date];
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
                NSDateFormatter *format = [NSDateFormatter new];
                [format setLocalizedDateFormatFromTemplate:@"MMMdEEEE"];
                date = [format stringFromDate:NSDate.date];
            }
            if (!temporaryText) subtitleText.hidden = YES;
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
    if (self.window && frame.size.height >= 60 && !qStylingLockClock)
        QRestyleLockClockForWidget(self);
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
            return;
        }
        qActivePlayers = [NSHashTable weakObjectsHashTable];
        qActivePlatters = [NSHashTable weakObjectsHashTable];
        qActiveNotifications = [NSHashTable weakObjectsHashTable];
        qActiveLists = [NSHashTable weakObjectsHashTable];
        qActiveBanners = [NSHashTable weakObjectsHashTable];
        qLockClockViews = [NSHashTable weakObjectsHashTable];
        QLoadSettings();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.quart17/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
                    QLoadSettings();
                    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                        CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
                }];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QNativeArtworkVisibilityChanged,
                                            CFSTR("com.gushi.quart17/nativeartworkexpanded"), NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QNativeArtworkVisibilityChanged,
                                            CFSTR("com.gushi.quart17/nativeartworkcollapsed"), NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
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
            [NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(__unused NSTimer *timer) {
                for (UIView *dateView in qLockClockViews.allObjects) QStyleLockClock(dateView);
            }];
        }
    }
}
