#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <stdlib.h>
#import <notify.h>
#import <math.h>
#include <algorithm>
#include <vector>
#import "QPlayerView.h"

static NSString *const QPrefs = @"com.gushi.quart17";
static NSMutableDictionary *qSettings;
static int qCornerStateToken = -1;
static BOOL qNativeArtworkExpanded;
static NSHashTable<QPlayerView *> *qActivePlayers;

static NSHashTable<UIView *> *qActivePlatters;
static NSHashTable<UIView *> *qActiveNotifications;
static NSHashTable<UIView *> *qActiveLists;
static NSHashTable<UIView *> *qActiveBanners;
static NSHashTable<UIView *> *qActiveQuickActionButtons;
static UIWindow *qTestBannerWindow;
static UIView *qTestBannerMaterial;
static UILabel *qTestBannerTitle;
static UILabel *qTestBannerMessage;
static NSTimer *qTestBannerVisibilityTimer;
static void *QOriginalStyleKey = &QOriginalStyleKey;
static void *QOwnLayerTransformKey = &QOwnLayerTransformKey;
static void *QOriginalLayerTransformKey = &QOriginalLayerTransformKey;
static void *QScalePendingKey = &QScalePendingKey;
static void *QScaleRetryKey = &QScaleRetryKey;
static void *QOriginalIndicatorKey = &QOriginalIndicatorKey;
static void *QBannerOriginalTransformKey = &QBannerOriginalTransformKey;
static void *QBannerOwnedTransformKey = &QBannerOwnedTransformKey;
static void *QBannerShadowHiddenKey = &QBannerShadowHiddenKey;
static void *QBannerGlassKey = &QBannerGlassKey;
static void *QToggleGlassProxyKey = &QToggleGlassProxyKey;
static void *QBannerGlassSheenKey = &QBannerGlassSheenKey;
static void *QBannerGlassRimKey = &QBannerGlassRimKey;
static void *QBannerGlassRimMaskKey = &QBannerGlassRimMaskKey;
static void *QBannerGlassBackdropKey = &QBannerGlassBackdropKey;
static void *QBannerGlassBlurKey = &QBannerGlassBlurKey;
static void *QBannerGlassMeshKey = &QBannerGlassMeshKey;
static void *QBannerGlassStyleKey = &QBannerGlassStyleKey;
static void *QBannerGlassCompatibilityKey = &QBannerGlassCompatibilityKey;
static void *QLockGlassShadowHiddenKey = &QLockGlassShadowHiddenKey;
static void *QLockOriginalInterfaceStyleKey = &QLockOriginalInterfaceStyleKey;
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
static void QStyleQuickActionButton(UIView *button);
static CGFloat QSharedCornerRadius(CGFloat height) {
    CGFloat roundness = [qSettings[@"playerCornerRoundness"] doubleValue];
    roundness = isfinite(roundness) ? MAX(0, MIN(1, roundness)) : 1;
    return MAX(0, height) * roundness / 2;
}
static CGFloat QShrinkScale(void);
static BOOL QApplyListScaling(UIView *list);
static void QScheduleListScaling(UIView *list);
static void QClearOwnLayerTransform(UIView *list);
static void QApplyBannerScaling(UIView *banner);
static void QRefreshTestBanner(void);
static void QShowTestBanner(void);
static void QHideTestBanner(void);

@interface NCNotificationShortLookViewController : UIViewController
- (UIView *)viewForPreview;
@end

@interface CSQuickActionsButton : UIView
@end


static void QLoadSettings(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    qSettings = [@{ @"masterEnabled": @YES, @"enabled": @YES, @"darkCards": @NO,
                    @"autoContrastText": @YES,
                    @"roundIcons": @YES,
                    @"playerEnabled": @YES, @"disableListScaling": @NO,
                    @"scaleBanners": @NO, @"glassBanners": @NO,
                    @"showNotificationCount": @YES,
                    @"playerAppearance": @0,
                    @"glassBlur": @8, @"glassRefraction": @12, @"glassHighlight": @0.5,
                    @"desktopVeil": @28, @"lockVeil": @28,
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
        }
        for (UIView *platter in qActivePlatters.allObjects) {
            [platter setNeedsLayout];
            [platter layoutIfNeeded];
        }
        for (UIView *notification in qActiveNotifications.allObjects) QStyle(notification);
        for (UIView *button in qActiveQuickActionButtons.allObjects) QStyleQuickActionButton(button);
        for (UIView *list in qActiveLists.allObjects) QScheduleListScaling(list);
        for (UIView *banner in qActiveBanners.allObjects) QApplyBannerScaling(banner);
        QRefreshTestBanner();
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

static UIColor *QAdaptiveGlassTextColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? UIColor.whiteColor : UIColor.blackColor;
        }];
    });
    return color;
}

static const void *QNativeLumKey = &QNativeLumKey;

static CGFloat QColorLuminance(UIColor *color) {
    if (!color) return -1;
    // Resolve dynamic colors (native label colors are often dynamic).
    @try {
        if ([color respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
            color = [color resolvedColorWithTraitCollection:UIScreen.mainScreen.traitCollection];
        }
    } @catch (...) {}
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    CGFloat w = 0;
    if ([color getWhite:&w alpha:&a]) return w;
    return -1;
}

static UIColor *QContrastTextColor(UIView *root) {
    for (UIView *ancestor = root; ancestor; ancestor = ancestor.superview) {
        id settings = nil;
        for (NSString *name in @[@"_legibilitySettings", @"legibilitySettings"]) {
            SEL selector = NSSelectorFromString(name);
            if (![ancestor respondsToSelector:selector]) continue;
            settings = ((id (*)(id, SEL))objc_msgSend)(ancestor, selector);
            if (settings) break;
        }
        if (![settings isKindOfClass:NSObject.class]) continue;
        for (NSString *key in @[@"contentColor", @"primaryColor", @"secondaryColor"]) {
            id value = nil;
            @try { value = [settings valueForKey:key]; }
            @catch (NSException *exception) { value = nil; }
            if (![value isKindOfClass:UIColor.class]) continue;
            CGFloat luminance = QColorLuminance(value);
            if (luminance < 0) continue;
            return luminance > 0.5 ? UIColor.whiteColor : UIColor.blackColor;
        }
    }
    return nil;
}

// Sample the status bar window's actual pixels. The status bar shows
// text/icons in white (dark bg) or black (light bg). Returns the matching
// banner style, or Unspecified if unknown.
static void QSetLockNotificationAppearance(UIView *root, UIUserInterfaceStyle style) {
    NSNumber *original = objc_getAssociatedObject(root, QLockOriginalInterfaceStyleKey);
    if (style != UIUserInterfaceStyleUnspecified) {
        if (!original)
            objc_setAssociatedObject(root, QLockOriginalInterfaceStyleKey,
                                     @(root.overrideUserInterfaceStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (root.overrideUserInterfaceStyle != style)
            root.overrideUserInterfaceStyle = style;
    } else if (original) {
        root.overrideUserInterfaceStyle = (UIUserInterfaceStyle)original.integerValue;
        objc_setAssociatedObject(root, QLockOriginalInterfaceStyleKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// CAMutableMeshTransform uses these C layouts on arm64, as in Burger Swift's
// iOS 17 glass surface. The mesh displaces backdrop sampling toward the
// middle of the rounded edge while leaving the card content untouched.
typedef struct { CGFloat x, y, z; } QGlassPoint3D;
typedef struct { CGPoint from; QGlassPoint3D to; } QGlassVertex;
typedef struct { uint32_t indices[4]; float weights[4]; } QGlassFace;

static NSArray<NSNumber *> *QGlassGrid(CGFloat length) {
    NSMutableSet<NSNumber *> *values = [NSMutableSet setWithObjects:@0, @(length), nil];
    const CGFloat edge[] = {2, 5, 8, 12, 18, 25, 34};
    for (NSUInteger i = 0; i < sizeof(edge) / sizeof(edge[0]); i++) {
        if (edge[i] < length / 2) {
            [values addObject:@(edge[i])];
            [values addObject:@(length - edge[i])];
        }
    }
    for (CGFloat point = 48; point < length - 40; point += 32)
        [values addObject:@(point)];
    return [[values allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

static CGFloat QGlassSDF(CGFloat x, CGFloat y, CGSize size, CGFloat radius) {
    CGFloat qx = fabs(x - size.width / 2) - size.width / 2 + radius;
    CGFloat qy = fabs(y - size.height / 2) - size.height / 2 + radius;
    return hypot(MAX(qx, 0), MAX(qy, 0)) + MIN(MAX(qx, qy), 0) - radius;
}

static CGFloat QGlassBezier(CGFloat value) {
    const CGFloat x1 = 0.816137566137566, y1 = 0.20502645502645533;
    const CGFloat x2 = 0.5806878306878306, y2 = 0.873015873015873;
    CGFloat t = MAX(0, MIN(1, value));
    for (int i = 0; i < 4; i++) {
        CGFloat inverse = 1 - t;
        CGFloat x = 3 * inverse * inverse * t * x1 + 3 * inverse * t * t * x2 + t * t * t;
        CGFloat slope = 3 * inverse * inverse * x1 + 6 * inverse * t * (x2 - x1) + 3 * t * t * (1 - x2);
        if (fabs(slope) < 0.0001) break;
        t = MAX(0, MIN(1, t - (x - value) / slope));
    }
    CGFloat inverse = 1 - t;
    CGFloat result = 3 * inverse * inverse * t * y1 + 3 * inverse * t * t * y2 + t * t * t;
    return result >= 0.997 ? 1 : result;
}

extern "C" void QUpdateGlassRefraction(CALayer *backdrop, CGSize size, CGFloat radius,
                                        CGFloat magnitude, UIVisualEffectView *glass) {
    Class meshClass = NSClassFromString(@"CAMutableMeshTransform");
    SEL create = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    if (!backdrop || !meshClass || ![meshClass respondsToSelector:create] ||
        size.width < 30 || size.height < 30) return;
    NSString *signature = [NSString stringWithFormat:@"rounded-v2:%.1f:%.1f:%.1f:%.1f",
                           size.width, size.height, radius, magnitude];
    if ([signature isEqual:objc_getAssociatedObject(glass, QBannerGlassMeshKey)]) return;
    CGFloat r = MAX(0, MIN(radius, MIN(size.width, size.height) / 2));
    CGFloat edgeDistance = MIN(12, MAX(r, 1));
    std::vector<QGlassVertex> vertices;
    std::vector<QGlassFace> faces;
    auto addVertex = [&](CGFloat x, CGFloat y, CGFloat depth = 0) -> uint32_t {
        CGFloat px = x - size.width / 2, py = y - size.height / 2;
        CGFloat qx = fabs(px) - size.width / 2 + r;
        CGFloat qy = fabs(py) - size.height / 2 + r;
        CGFloat nx = 0, ny = 0;
        if (qx > 0 && qy > 0) {
            CGFloat length = hypot(qx, qy);
            if (length > 0) { nx = qx / length; ny = qy / length; }
        } else if (qx > qy) nx = 1;
        else ny = 1;
        if (px < 0) nx = -nx;
        if (py < 0) ny = -ny;
        CGFloat distance = MAX(0, -QGlassSDF(x, y, size, r));
        CGFloat weight = QGlassBezier(MAX(0, MIN(1, 1 - distance / edgeDistance)));
        CGFloat edgeBand = MIN(2, r);
        if (edgeBand > 0) {
            CGFloat boost = MAX(0, MIN(1, (edgeBand - distance) / edgeBand));
            weight *= 1 + 0.5 * boost * boost * (3 - 2 * boost);
        }
        QGlassVertex vertex = {};
        vertex.from = CGPointMake(MAX(0, MIN(1, (x - nx * weight * magnitude) / size.width)),
                                  MAX(0, MIN(1, (y - ny * weight * magnitude) / size.height)));
        vertex.to = (QGlassPoint3D){x / size.width, y / size.height, depth};
        vertices.push_back(vertex);
        return (uint32_t)(vertices.size() - 1);
    };
    auto addFace = [&](uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
        QGlassFace face = {};
        face.indices[0] = a; face.indices[1] = b;
        face.indices[2] = c; face.indices[3] = d;
        faces.push_back(face);
    };
    auto addGrid = [&](const std::vector<CGFloat> &xs, const std::vector<CGFloat> &ys) {
        if (xs.size() < 2 || ys.size() < 2 ||
            xs.back() - xs.front() < 0.01 || ys.back() - ys.front() < 0.01) return;
        std::vector<uint32_t> indices;
        for (CGFloat y : ys) for (CGFloat x : xs) indices.push_back(addVertex(x, y));
        for (size_t row = 0; row + 1 < ys.size(); row++) {
            for (size_t column = 0; column + 1 < xs.size(); column++) {
                size_t top = row * xs.size() + column;
                addFace(indices[top], indices[top + 1],
                        indices[top + xs.size() + 1], indices[top + xs.size()]);
            }
        }
    };
    if (r < 1) {
        NSArray<NSNumber *> *oldX = QGlassGrid(size.width), *oldY = QGlassGrid(size.height);
        std::vector<CGFloat> xs, ys;
        for (NSNumber *number in oldX) xs.push_back(number.doubleValue);
        for (NSNumber *number in oldY) ys.push_back(number.doubleValue);
        addGrid(xs, ys);
    } else {
        std::vector<CGFloat> depths = {0};
        for (int i = 1; i < 12; i++) depths.push_back(r * i / 12);
        depths.push_back(r);
        if (r > 2) depths.push_back(2);
        std::sort(depths.begin(), depths.end());
        depths.erase(std::unique(depths.begin(), depths.end(), [](CGFloat a, CGFloat b) {
            return fabs(a - b) < 0.01;
        }), depths.end());
        std::vector<CGFloat> topY, bottomY, leftX, rightX, radii;
        for (CGFloat depth : depths) {
            topY.push_back(depth);
            bottomY.push_back(size.height - r + depth);
            leftX.push_back(depth);
            rightX.push_back(size.width - r + depth);
            if (depth < r - 0.01) radii.push_back(r - depth);
        }
        std::vector<CGFloat> middleX, middleY;
        for (int i = 0; i <= 7; i++) middleX.push_back(r + (size.width - 2 * r) * i / 7);
        for (int i = 0; i <= 7; i++) middleY.push_back(r + (size.height - 2 * r) * i / 7);
        addGrid(middleX, topY);
        addGrid(middleX, bottomY);
        addGrid(leftX, middleY);
        addGrid(rightX, middleY);
        addGrid(middleX, middleY);
        auto addCorner = [&](CGFloat cx, CGFloat cy, CGFloat start, CGFloat end) {
            std::vector<std::vector<uint32_t>> rings;
            for (CGFloat ringRadius : radii) {
                std::vector<uint32_t> ring;
                for (int i = 0; i <= 12; i++) {
                    CGFloat angle = start + (end - start) * i / 12;
                    ring.push_back(addVertex(cx + ringRadius * cos(angle),
                                             cy + ringRadius * sin(angle)));
                }
                rings.push_back(std::move(ring));
            }
            for (size_t row = 0; row + 1 < rings.size(); row++)
                for (size_t column = 0; column < 12; column++)
                    addFace(rings[row][column], rings[row][column + 1],
                            rings[row + 1][column + 1], rings[row + 1][column]);
            uint32_t center = addVertex(cx, cy, -0.02);
            const std::vector<uint32_t> &inner = rings.back();
            for (int i = 0; i < 12; i += 2)
                addFace(center, inner[i], inner[i + 1], inner[i + 2]);
        };
        addCorner(r, r, M_PI, 1.5 * M_PI);
        addCorner(size.width - r, r, 1.5 * M_PI, 2 * M_PI);
        addCorner(size.width - r, size.height - r, 0, 0.5 * M_PI);
        addCorner(r, size.height - r, 0.5 * M_PI, M_PI);
    }
    if (vertices.empty() || faces.empty()) return;
    @try {
        IMP imp = [meshClass methodForSelector:create];
        id (*makeMesh)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id) =
            (id (*)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id))imp;
        id mesh = makeMesh(meshClass, create, vertices.size(), vertices.data(),
                           faces.size(), faces.data(), @"none");
        if (mesh) {
            SEL steps = NSSelectorFromString(@"setSubdivisionSteps:");
            if ([mesh respondsToSelector:steps])
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(mesh, steps, 0);
            [backdrop setValue:mesh forKey:@"meshTransform"];
            objc_setAssociatedObject(glass, QBannerGlassMeshKey, signature,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @catch (NSException *exception) {
        // Keep the undistorted live backdrop if the private mesh API differs.
    }
}

// Keep the glass behind Apple's content and actions. Use the same surface for
// desktop banners and ordinary Lock Screen notifications, never Live Activities.
static void QSetLockGlassShadowHidden(UIView *material, BOOL hidden) {
    for (UIView *sibling in material.superview.subviews) {
        if (![NSStringFromClass(sibling.class) containsString:@"MTShadowView"]) continue;
        NSNumber *original = objc_getAssociatedObject(sibling, QLockGlassShadowHiddenKey);
        if (hidden) {
            if (!original)
                objc_setAssociatedObject(sibling, QLockGlassShadowHiddenKey, @(sibling.hidden),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            sibling.hidden = YES;
        } else if (original) {
            sibling.hidden = original.boolValue;
            objc_setAssociatedObject(sibling, QLockGlassShadowHiddenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void QApplyGlassSurface(UIView *root, UIView *material, BOOL quickAction) {
    if (!material) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(material, QBannerGlassKey);
    BOOL enabled = [qSettings[@"masterEnabled"] boolValue] &&
        [qSettings[@"enabled"] boolValue] && [qSettings[@"glassBanners"] boolValue] &&
        (quickAction || QIsDesktopBanner(root) || QIsLockScreenNotification(root));
    if (!enabled || !material.superview) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(material, QBannerGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        material.hidden = NO;
        if (!quickAction) QSetLockGlassShadowHidden(material, NO);
        return;
    }
    BOOL lockNotification = QIsLockScreenNotification(root);
    if (!quickAction) QSetLockGlassShadowHidden(material, lockNotification);
    // Both banner locations use the same live backdrop renderer. The lock
    // cell's appearance is fixed separately so its folded material is dark.
    BOOL compatibleLockGlass = NO;
    if (glass && [objc_getAssociatedObject(glass, QBannerGlassCompatibilityKey) boolValue] != compatibleLockGlass) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(material, QBannerGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glass = nil;
    }
    if (!glass) {
        glass = [[UIVisualEffectView alloc] initWithEffect:nil];
        objc_setAssociatedObject(glass, QBannerGlassCompatibilityKey, @(compatibleLockGlass),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glass.userInteractionEnabled = NO;
        glass.clipsToBounds = YES;
        glass.layer.cornerCurve = kCACornerCurveCircular;
        // iOS 17's stock material adds a gray tint. A live backdrop layer lets
        // the banner sample the app underneath with much less color wash.
        // Keep the public blur effect as a fallback if that layer is missing.
        Class backdropClass = NSClassFromString(@"CABackdropLayer");
        Class filterClass = NSClassFromString(@"CAFilter");
        SEL filterSelector = NSSelectorFromString(@"filterWithName:");
        if (!compatibleLockGlass && backdropClass && filterClass &&
            [filterClass respondsToSelector:filterSelector]) {
            @try {
                CALayer *backdrop = ((id (*)(id, SEL))objc_msgSend)(backdropClass, @selector(layer));
                id blur = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, filterSelector, @"gaussianBlur");
                if (backdrop && blur) {
                    [blur setValue:@8 forKey:@"inputRadius"];
                    [backdrop setValue:@[blur] forKey:@"filters"];
                    [backdrop setValue:@1 forKey:@"scale"];
                    backdrop.rasterizationScale = UIScreen.mainScreen.scale;
                    [glass.layer insertSublayer:backdrop atIndex:0];
                    objc_setAssociatedObject(glass, QBannerGlassBackdropKey, backdrop,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(glass, QBannerGlassBlurKey, blur,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } @catch (NSException *exception) {
                // Unsupported SpringBoard composition falls back to UIKit.
            }
        }
        CAGradientLayer *sheen = [CAGradientLayer layer];
        sheen.locations = @[@0, @0.16, @0.56, @1];
        [glass.contentView.layer addSublayer:sheen];
        objc_setAssociatedObject(glass, QBannerGlassSheenKey, sheen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Keep the reflected light on the rounded edge instead of washing
        // out notification text across the whole card.
        CAGradientLayer *rim = [CAGradientLayer layer];
        rim.locations = @[@0, @0.22, @0.7, @1];
        CALayer *rimMask = [CALayer layer];
        rimMask.borderColor = UIColor.whiteColor.CGColor;
        rimMask.borderWidth = 0.9;
        rimMask.cornerCurve = kCACornerCurveCircular;
        rim.mask = rimMask;
        [glass.contentView.layer addSublayer:rim];
        objc_setAssociatedObject(glass, QBannerGlassRimKey, rim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(glass, QBannerGlassRimMaskKey, rimMask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(material, QBannerGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITraitCollection *systemTraits = lockNotification ? root.window.traitCollection : root.traitCollection;
    BOOL systemDark = systemTraits.userInterfaceStyle == UIUserInterfaceStyleDark;
    // The Lock Screen cell must stay in dark appearance to avoid black
    // collapsed-stack materials in light system appearance. Match the banner's
    // glass treatment while keeping that independent appearance choice.
    // Match the Lock Screen notification's dark glass. A separate light veil
    // made the native shortcut disks much more opaque than the cards.
    BOOL dark = quickAction || lockNotification || systemDark;
    if (compatibleLockGlass) {
        CALayer *oldBackdrop = objc_getAssociatedObject(glass, QBannerGlassBackdropKey);
        [oldBackdrop removeFromSuperlayer];
        objc_setAssociatedObject(glass, QBannerGlassBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(glass, QBannerGlassBlurKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat blurRadius = [qSettings[@"glassBlur"] doubleValue];
    CGFloat refraction = [qSettings[@"glassRefraction"] doubleValue];
    CGFloat highlight = [qSettings[@"glassHighlight"] doubleValue];
    blurRadius = isfinite(blurRadius) ? MAX(0, MIN(18, blurRadius)) : 8;
    refraction = isfinite(refraction) ? MAX(0, MIN(24, refraction)) : 12;
    highlight = isfinite(highlight) ? MAX(0, MIN(1, highlight)) : 0.5;
    // The same blur radius and mesh displacement drive both locations.
    UIBlurEffectStyle style = dark ? UIBlurEffectStyleSystemUltraThinMaterialDark :
                                     UIBlurEffectStyleSystemUltraThinMaterialLight;
    if (compatibleLockGlass && blurRadius > 8)
        style = dark ? UIBlurEffectStyleSystemThinMaterialDark : UIBlurEffectStyleSystemThinMaterialLight;
    if (compatibleLockGlass && blurRadius >= 14)
        style = dark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
    if (compatibleLockGlass && blurRadius >= 17)
        style = dark ? UIBlurEffectStyleSystemThickMaterialDark : UIBlurEffectStyleSystemThickMaterialLight;
    NSNumber *styleNumber = blurRadius < 0.5 && compatibleLockGlass ? @(-1) : @(style);
    NSNumber *oldStyle = objc_getAssociatedObject(glass, QBannerGlassStyleKey);
    if (!objc_getAssociatedObject(glass, QBannerGlassBackdropKey) &&
        (![oldStyle isEqualToNumber:styleNumber] ||
         glass.overrideUserInterfaceStyle != (dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight))) {
        glass.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        glass.effect = styleNumber.integerValue < 0 ? nil : [UIBlurEffect effectWithStyle:style];
        objc_setAssociatedObject(glass, QBannerGlassStyleKey, styleNumber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glass.alpha = 1;
    // The veil ensures text readability on any background. It follows the
    // mode (dark veil in dark mode, light veil in light mode) with enough
    // opacity to guarantee contrast, while still showing the blurred
    // background through. This is how system materials stay legible.
    // Desktop and lock screen veils are user-adjustable separately
    // (desktopVeil / lockVeil, 0-30, real-time).
    CGFloat veilPct = lockNotification ? [qSettings[@"lockVeil"] doubleValue]
                                       : [qSettings[@"desktopVeil"] doubleValue];
    veilPct = isfinite(veilPct) ? MAX(0, MIN(30, veilPct)) : 28;
    CGFloat veil = veilPct / 100.0;
    glass.contentView.backgroundColor = dark ? [UIColor colorWithWhite:0 alpha:veil] :
        [UIColor colorWithWhite:1 alpha:veil];
    glass.frame = material.frame;
    glass.autoresizingMask = material.autoresizingMask;
    CALayer *backdrop = objc_getAssociatedObject(glass, QBannerGlassBackdropKey);
    backdrop.frame = glass.bounds;
    id blurFilter = objc_getAssociatedObject(glass, QBannerGlassBlurKey);
    if (blurFilter) [blurFilter setValue:@(blurRadius) forKey:@"inputRadius"];
    CGFloat cardRadius = quickAction ? MIN(glass.bounds.size.width, glass.bounds.size.height) / 2 :
        MIN(root.layer.cornerRadius, MIN(glass.bounds.size.width, glass.bounds.size.height) / 2);
    if (!quickAction) material.layer.cornerRadius = cardRadius;
    glass.layer.cornerRadius = cardRadius;
    QUpdateGlassRefraction(backdrop, glass.bounds.size, glass.layer.cornerRadius,
                           refraction * 0.65, glass);
    // The gradient rim supplies the only outline. A second layer border made
    // the Lock Screen cards look like concentric strokes.
    glass.layer.borderWidth = 0;
    CAGradientLayer *sheen = objc_getAssociatedObject(glass, QBannerGlassSheenKey);
    sheen.frame = glass.bounds;
    sheen.colors = dark ? @[(id)[UIColor colorWithWhite:1 alpha:0.22 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.07 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.01].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.11].CGColor]
                        : @[(id)[UIColor colorWithWhite:1 alpha:0.34 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.12 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.01].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.07].CGColor];
    sheen.opacity = 1;
    CAGradientLayer *rim = objc_getAssociatedObject(glass, QBannerGlassRimKey);
    CALayer *rimMask = objc_getAssociatedObject(glass, QBannerGlassRimMaskKey);
    rim.frame = glass.bounds;
    CGFloat inset = rimMask.borderWidth / 2;
    rimMask.frame = CGRectInset(rim.bounds, inset, inset);
    rimMask.cornerRadius = MAX(0, cardRadius - inset);
    rim.colors = dark ? @[(id)[UIColor colorWithWhite:1 alpha:0.34 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.12 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.04 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.16 * highlight].CGColor]
                      : @[(id)[UIColor colorWithWhite:1 alpha:0.52 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.18 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.08 * highlight].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.28 * highlight].CGColor];
    if (glass.superview != material.superview)
        [material.superview insertSubview:glass aboveSubview:material];
    material.hidden = YES;
}

// Folded-stack support for the count badge: find the notification views that
// belong to the same stack by overlap. Scope is the nearest
// NCNotificationListView: stacked cards may live in one shared cell or in
// separate cells under the same list view. Overlap is the real filter, so
// widening the scope cannot merge unrelated cards. (The front-only glass
// experiment was rolled back: every card gets glass, as before 2.2.6.)
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
    for (UIView *other in qActiveNotifications) {
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
    // count badge on the top card; the glass effect itself is no longer
    // gated by it (rolled back to pre-2.2.6: every card gets glass).
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
    NSInteger cellCount = 0, tableCount = 0, masterCount = 0;
    NSString *stackKey = nil;
    if (siblings.count && hasFoldedBehind) {
        cellCount = QStackCount(root, siblings);
        count = cellCount;
        // The overlap walk under-reports once the system detaches hidden
        // cards' views (folded stacks render ~3 layers). Take the max across
        // every source that knows the stack: cell model, all styled views
        // grouped by stack identity, and the list's data model.
        stackKey = QStackKeyForView(root);
        if (stackKey && QStackKeyHasThread(stackKey)) {
            tableCount = QActiveTableStackCount(stackKey, container);
            if (tableCount > count) count = tableCount;
            masterCount = QMasterListStackCount(stackKey, container);
            if (masterCount > count) count = masterCount;
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

// Fold/unfold animations move the stacked cards via transforms, which do not
// trigger the card views' own layout passes, so the count badge can go stale
// (e.g. not appearing right after folding). Refresh the badge when the cell
// or the list lays out; the update itself is cheap and idempotent.
static void QRefreshStackStatesIn(UIView *container) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (!container.window || qRefreshingStackStates) return;
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

static void QApplyBannerGlass(UIView *root, UIView *material) {
    QApplyGlassSurface(root, material, NO);
}

static void QStyleQuickActionButton(UIView *button) {
    // The visible disk is the 50-point effect view nested inside Apple's
    // 86-point CSQuickActionsButton. Replace only that disk and leave its
    // native glyph, hit target, and press animation in place.
    UIVisualEffectView *material = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:button];
    while (queue.count && !material) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIVisualEffectView.class] && view != button &&
            view.bounds.size.width >= 40 && view.bounds.size.width <= 60 &&
            view.bounds.size.height >= 40 && view.bounds.size.height <= 60 &&
            !objc_getAssociatedObject(view, QBannerGlassCompatibilityKey)) {
            material = (UIVisualEffectView *)view;
        } else {
            [queue addObjectsFromArray:view.subviews];
        }
    }
    if (material) QApplyGlassSurface(button, material, YES);
}

static void QStyleToggleControl(UIView *button) {
    // The coalescing header's collapse pill and clear disk keep their native
    // label/glyph and hit handling. Only their backdrop gets the liquid
    // glass treatment, reusing the quick-action renderer.
    if (!button || !button.superview) return;
    // Hooking the toggle itself (not its container) guarantees the backdrop
    // already has its final frame when we style it.
    // The per-app coalesced header (collapse pill + clear disk) and the
    // Notification Center section header (clear button) both host toggles.
    if (!QHasAncestor(button, @"NCNotificationListCoalescingControlsView") &&
        !QHasAncestor(button, @"NCNotificationListSectionHeaderView")) return;
    // Clean slate: the toggle rebuilds its backdrop across states (fold /
    // clear confirmation). Remove our previous glass, restore any backdrop
    // we hid, so exactly one glass ends up installed per pass.
    for (UIView *subview in [button.subviews copy]) {
        if (objc_getAssociatedObject(subview, QBannerGlassCompatibilityKey)) {
            [subview removeFromSuperview];
        } else if (subview.hidden && objc_getAssociatedObject(subview, QBannerGlassKey)) {
            subview.hidden = NO;
        }
    }
    UIView *material = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:button];
    while (queue.count && !material) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view != button) {
            NSString *name = NSStringFromClass(view.class);
            // MTMaterialView is the pill/circle backdrop. Never the label or glyph itself.
            if ([name containsString:@"MaterialView"] ||
                [name containsString:@"VisualEffectView"] ||
                [name containsString:@"BackdropView"]) {
                material = view;
                break;
            }
        }
        [queue addObjectsFromArray:view.subviews];
    }
    UIView *proxy = objc_getAssociatedObject(button, QToggleGlassProxyKey);
    if (material) {
        if (proxy) {
            [proxy removeFromSuperview];
            objc_setAssociatedObject(button, QToggleGlassProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        QApplyGlassSurface(button, material, YES);
    } else {
        // No native backdrop (the clear disk only hosts a glyph): glass a
        // transparent proxy instead, circular like the native disk and
        // centered on the glyph.
        if (!proxy) {
            proxy = [[UIView alloc] init];
            proxy.userInteractionEnabled = NO;
            proxy.backgroundColor = UIColor.clearColor;
            objc_setAssociatedObject(button, QToggleGlassProxyKey, proxy,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIView *glyph = nil;
        NSMutableArray<UIView *> *gqueue = [NSMutableArray arrayWithObject:button];
        while (gqueue.count && !glyph) {
            UIView *view = gqueue.firstObject;
            [gqueue removeObjectAtIndex:0];
            if (view != button && view != proxy &&
                ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class])) {
                glyph = view;
                break;
            }
            [gqueue addObjectsFromArray:view.subviews];
        }
        CGFloat d = MIN(button.bounds.size.width, button.bounds.size.height);
        CGPoint center = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
        if (glyph) center = [glyph.superview convertPoint:glyph.center toView:button];
        if (proxy.superview != button) [button insertSubview:proxy atIndex:0];
        proxy.frame = CGRectMake(center.x - d / 2, center.y - d / 2, d, d);
        proxy.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        QApplyGlassSurface(button, proxy, YES);
    }
    // Keep the native label/glyph above the glass.
    for (UIView *subview in button.subviews) {
        if ([subview isKindOfClass:UILabel.class] || [subview isKindOfClass:UIImageView.class])
            [button bringSubviewToFront:subview];
    }
    // Force dark mode like the notification banners: the collapse pill,
    // the clear disk, and the Notification Center section header buttons
    // must render white content even when the system is in light mode.
    // (Direct textColor/tintColor forcing alone doesn't stick; the system
    // resets it. overrideUserInterfaceStyle is what the banners use.)
    if (button.overrideUserInterfaceStyle != UIUserInterfaceStyleDark)
        button.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    // Force white text/icons like the notification banners: the collapse
    // pill, the clear disk, and the Notification Center section header
    // buttons all sit on glass and must stay legible.
    NSMutableArray<UIView *> *wqueue = [NSMutableArray arrayWithObject:button];
    while (wqueue.count) {
        UIView *view = wqueue.lastObject;
        [wqueue removeLastObject];
        if ([view isKindOfClass:UILabel.class]) {
            ((UILabel *)view).textColor = UIColor.whiteColor;
        } else if ([view isKindOfClass:UIImageView.class]) {
            ((UIImageView *)view).tintColor = UIColor.whiteColor;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *b = (UIButton *)view;
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.tintColor = UIColor.whiteColor;
        }
        [wqueue addObjectsFromArray:view.subviews];
    }
}

static void QStyleActionButton(UIView *button) {
    // Left-swipe notification actions ("选项" / "清除", PLPlatterActionButton).
    // Keep the native title and tap handling; only the MTMaterialView
    // backdrop becomes liquid glass.
    if (!button || !button.superview) return;
    // Clean slate: the buttons animate in while swiping and rebuild their
    // backdrop. Exactly one glass per button per pass.
    for (UIView *subview in [button.subviews copy]) {
        if (objc_getAssociatedObject(subview, QBannerGlassCompatibilityKey)) {
            [subview removeFromSuperview];
        } else if (subview.hidden && objc_getAssociatedObject(subview, QBannerGlassKey)) {
            subview.hidden = NO;
        }
    }
    UIView *material = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:button];
    while (queue.count && !material) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view != button) {
            NSString *name = NSStringFromClass(view.class);
            if ([name containsString:@"MaterialView"] ||
                [name containsString:@"VisualEffectView"] ||
                [name containsString:@"BackdropView"]) {
                material = view;
                break;
            }
        }
        [queue addObjectsFromArray:view.subviews];
    }
    if (!material) return;
    // The title may live inside the material view; hiding the material must
    // not take the label with it. Hoist such labels up to the button,
    // preserving their on-screen frame.
    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    NSMutableArray<UIView *> *lqueue = [NSMutableArray arrayWithObject:button];
    while (lqueue.count) {
        UIView *view = lqueue.firstObject;
        [lqueue removeObjectAtIndex:0];
        if (view != button && !objc_getAssociatedObject(view, QBannerGlassCompatibilityKey) &&
            ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class])) {
            BOOL insideMaterial = NO;
            for (UIView *p = view.superview; p && p != button; p = p.superview) {
                if (p == material) { insideMaterial = YES; break; }
            }
            if (insideMaterial) {
                CGRect f = [view.superview convertRect:view.frame toView:button];
                [button addSubview:view];
                view.frame = f;
            }
            [labels addObject:view];
        }
        [lqueue addObjectsFromArray:view.subviews];
    }
    QApplyGlassSurface(button, material, YES);
    // The "选项" / "清除" pills follow the notification corner radius slider.
    // (The lock screen quick actions and X buttons keep their native shape.)
    UIVisualEffectView *actionGlass = objc_getAssociatedObject(material, QBannerGlassKey);
    if (actionGlass) {
        CGFloat actionRadius = QSharedCornerRadius(MIN(button.bounds.size.width, button.bounds.size.height));
        // Sync the button itself so its clipping matches the glass.
        button.layer.cornerRadius = actionRadius;
        button.layer.cornerCurve = kCACornerCurveCircular;
        button.clipsToBounds = YES;
        actionGlass.layer.cornerRadius = actionRadius;
        // Clip the glass so the veil/sheen don't overflow the rounded corners.
        actionGlass.clipsToBounds = YES;
        CALayer *actionRimMask = objc_getAssociatedObject(actionGlass, QBannerGlassRimMaskKey);
        if (actionRimMask) {
            CGFloat actionInset = actionRimMask.borderWidth / 2;
            actionRimMask.frame = CGRectInset(actionGlass.bounds, actionInset, actionInset);
            actionRimMask.cornerRadius = MAX(0, actionRadius - actionInset);
        }
        // Rebuild the edge refraction with the new radius.
        CALayer *actionBackdrop = objc_getAssociatedObject(actionGlass, QBannerGlassBackdropKey);
        if (actionBackdrop) {
            CGFloat actionRefraction = [qSettings[@"glassRefraction"] doubleValue];
            actionRefraction = isfinite(actionRefraction) ? MAX(0, MIN(24, actionRefraction)) : 12;
            QUpdateGlassRefraction(actionBackdrop, actionGlass.bounds.size, actionRadius,
                                   actionRefraction * 0.65, actionGlass);
        }
    }
    for (UIView *label in labels) [button bringSubviewToFront:label];
}

// A persistent SpringBoard preview uses the exact desktop glass renderer.
// It is deliberately separate from BulletinBoard, so testing never adds a
// real notification to Notification Center or changes app alert settings.
static void QRefreshTestBanner(void) {
    if (!qTestBannerWindow || !qTestBannerMaterial) return;
    UIView *root = qTestBannerWindow.rootViewController.view;
    CGFloat radius = QSharedCornerRadius(root.bounds.size.height);
    root.layer.cornerRadius = radius;
    root.layer.cornerCurve = kCACornerCurveCircular;
    root.clipsToBounds = YES;
    qTestBannerMaterial.frame = root.bounds;
    qTestBannerMaterial.layer.cornerRadius = radius;
    qTestBannerMaterial.layer.cornerCurve = kCACornerCurveCircular;
    qTestBannerMaterial.clipsToBounds = YES;
    UIVisualEffectView *previousGlass = objc_getAssociatedObject(qTestBannerMaterial, QBannerGlassKey);
    [previousGlass removeFromSuperview];
    objc_setAssociatedObject(qTestBannerMaterial, QBannerGlassKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    qTestBannerMaterial.hidden = NO;
    QApplyBannerGlass(root, qTestBannerMaterial);
    BOOL dark = root.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    qTestBannerTitle.textColor = dark ? UIColor.whiteColor : UIColor.blackColor;
    qTestBannerMessage.textColor = dark ? UIColor.whiteColor : UIColor.blackColor;
}

static void QHideTestBanner(void) {
    [qTestBannerVisibilityTimer invalidate];
    qTestBannerVisibilityTimer = nil;
    qTestBannerWindow.hidden = YES;
    qTestBannerWindow.rootViewController = nil;
    qTestBannerWindow = nil;
    qTestBannerMaterial = nil;
    qTestBannerTitle = nil;
    qTestBannerMessage = nil;
}

static void QShowTestBanner(void) {
    QHideTestBanner();
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    CGRect screen = UIScreen.mainScreen.bounds;
    UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                             : [[UIWindow alloc] initWithFrame:screen];
    window.frame = CGRectMake(14, MAX(54, screen.size.height * 0.065), screen.size.width - 28, 82);
    window.windowLevel = UIWindowLevelAlert + 2;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *controller = [UIViewController new];
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, window.bounds.size.width, 82)];
    root.backgroundColor = UIColor.clearColor;
    controller.view = root;
    window.rootViewController = controller;

    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    material.frame = root.bounds;
    material.userInteractionEnabled = NO;
    [root addSubview:material];
    qTestBannerMaterial = material;

    UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(16, 17, 48, 48)];
    icon.backgroundColor = [UIColor colorWithRed:0.78 green:0.23 blue:0.17 alpha:1];
    icon.layer.cornerRadius = 24;
    [root addSubview:icon];
    UIImageView *symbol = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"bell.fill"]];
    symbol.tintColor = UIColor.whiteColor;
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.frame = CGRectMake(13, 13, 22, 22);
    [icon addSubview:symbol];

    CGFloat textWidth = MAX(100, root.bounds.size.width - 130);
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(78, 17, textWidth, 23)];
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    title.text = @"Quart17";
    [root addSubview:title];
    qTestBannerTitle = title;
    UILabel *message = [[UILabel alloc] initWithFrame:CGRectMake(78, 40, textWidth, 24)];
    message.font = [UIFont systemFontOfSize:14];
    BOOL chinese = [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
    message.text = chinese ? @"常驻测试通知 · 调节玻璃效果" : @"Persistent test · adjust the glass";
    message.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addSubview:message];
    qTestBannerMessage = message;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(root.bounds.size.width - 42, 23, 32, 32);
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = UIColor.secondaryLabelColor;
    [close addTarget:controller action:@selector(q_quartHideTestBanner) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:close];

    qTestBannerWindow = window;
    window.hidden = QIsLockScreenVisible();
    QRefreshTestBanner();
    qTestBannerVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
        qTestBannerWindow.hidden = QIsLockScreenVisible();
    }];
}

@interface UIViewController (QuartTestBanner)
- (void)q_quartHideTestBanner;
@end
@implementation UIViewController (QuartTestBanner)
- (void)q_quartHideTestBanner { QHideTestBanner(); }
@end

static void QTestBannerChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                               const void *object, CFDictionaryRef userInfo) {
    BOOL show = CFEqual(name, CFSTR("com.gushi.quart17/showtestnotification"));
    dispatch_async(dispatch_get_main_queue(), ^{ if (show) QShowTestBanner(); else QHideTestBanner(); });
}

static void QStyle(UIView *root) {
    if (!root) return;
    BOOL lockNotification = QIsLockScreenNotification(root);
    BOOL stylingEnabled = [qSettings[@"masterEnabled"] boolValue] &&
                          [qSettings[@"enabled"] boolValue];
    // Keep the entire folded cell dark, including its outer dimming material.
    UIView *appearanceRoot = root;
    for (UIView *ancestor = root.superview; ancestor && ![ancestor isKindOfClass:UIWindow.class];
         ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"NCNotificationListCell"]) {
            appearanceRoot = ancestor;
            break;
        }
    }
    UIUserInterfaceStyle bannerStyle = UIUserInterfaceStyleUnspecified;
    if (stylingEnabled && lockNotification) {
        bannerStyle = UIUserInterfaceStyleDark;
    }
    // Desktop banners: text color is set explicitly from the status bar
    // (see explicitDesktopTextColor above), so no appearance override.
    QSetLockNotificationAppearance(appearanceRoot, bannerStyle);
    [qActiveNotifications addObject:root];
    QUpdateStackState(root);
    QRestoreStyle(root);
    UIView *material = QFind(root, @"MTMaterialView");
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"enabled"] boolValue]) {
        QApplyBannerGlass(root, material);
        return;
    }
    CGFloat radius = QSharedCornerRadius(root.bounds.size.height);
    QRememberStyle(root);
    root.layer.cornerRadius = radius;
    root.layer.cornerCurve = kCACornerCurveCircular;
    root.clipsToBounds = YES;

    if (material) {
        QRememberStyle(material);
        material.layer.cornerRadius = radius;
        material.layer.cornerCurve = kCACornerCurveCircular;
        material.clipsToBounds = YES;
        if ([qSettings[@"darkCards"] boolValue] || lockNotification) {
            material.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.82];
        }
        QApplyBannerGlass(root, material);
    }

    // Keep Apple's notification actions, privacy rules, and accessibility hierarchy.
    // Only the visible labels and containers receive styling.
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        if ([view isKindOfClass:UILabel.class]) {
            if (objc_getAssociatedObject(view, QCountBadgeKey)) continue; // our count badge
            UILabel *label = (UILabel *)view;
            QRememberStyle(label);
            // The glass replaces Apple's material, so its labels must follow
            // the current appearance even for notifications already on screen.
            if ([qSettings[@"darkCards"] boolValue] || lockNotification) {
                label.textColor = UIColor.whiteColor;
            } else if ([qSettings[@"glassBanners"] boolValue] &&
                       (QIsLockScreenNotification(root) || QIsDesktopBanner(root))) {
                // Follow the native text color: the system already chose it
                // for the current context (light mode = black text, dark
                // mode = white text). Cache the native luminance so
                // re-styling doesn't read back our own override.
                NSNumber *saved = objc_getAssociatedObject(label, QNativeLumKey);
                CGFloat nativeLum = saved ? saved.doubleValue : -1;
                if (!saved) {
                    nativeLum = QColorLuminance(label.textColor);
                    objc_setAssociatedObject(label, QNativeLumKey, @(nativeLum),
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (nativeLum >= 0) {
                    label.textColor = nativeLum > 0.5 ? UIColor.whiteColor
                                                     : UIColor.blackColor;
                } else {
                    label.textColor = QAdaptiveGlassTextColor();
                }
            }
            if ([qSettings[@"autoContrastText"] boolValue] && material &&
                objc_getAssociatedObject(material, QBannerGlassKey)) {
                UIColor *contrast = QContrastTextColor(root);
                if (contrast) label.textColor = contrast;
            }
            // Clear any shadow left over from earlier builds.
            label.layer.shadowOpacity = 0;
        }
        NSString *name = NSStringFromClass(view.class);
        BOOL iconClass = [name containsString:@"IconView"];
        BOOL smallImage = [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image != nil;
        CGSize size = view.bounds.size;
        // A badged icon wraps the app image and its lower-right overlay.
        // Clipping that wrapper to a circle cuts the overlay off; round only
        // the leaf image, or an icon view with no child overlays.
        BOOL canClipIcon = smallImage || (iconClass && view.subviews.count == 0 &&
            ![name containsString:@"Badged"]);
        if (canClipIcon && size.width >= 24 && size.width <= 80 &&
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

#pragma mark - 锁屏快捷按钮玻璃

%group QQuickActions
%hook CSQuickActionsButton

- (void)layoutSubviews {
    %orig;
    [qActiveQuickActionButtons addObject:self];
    QStyleQuickActionButton(self);
}

%end
%end

%group QHeaderButtons
%hook NCToggleControl

- (void)layoutSubviews {
    %orig;
    // The collapse pill and the clear disk in the per-app coalesced header.
    // Styling here (not on the container) means the backdrop frame is final.
    QStyleToggleControl((UIView *)self);
}

%end

%hook PLPlatterActionButton

- (void)layoutSubviews {
    %orig;
    // The "选项" / "清除" buttons revealed by swiping a notification left.
    QStyleActionButton((UIView *)self);
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

static BOOL QIsRightCoverSheetPan(UIScrollView *scrollView) {
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
    BOOL mediaPlatter = size.height >= 145 &&
                        QFind(self, @"_UISceneLayerHostContainerView");
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
        qActiveQuickActionButtons = [NSHashTable weakObjectsHashTable];
        QLoadSettings();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.quart17/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
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
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QTestBannerChanged, CFSTR("com.gushi.quart17/showtestnotification"),
                                            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                            QTestBannerChanged, CFSTR("com.gushi.quart17/hidetestnotification"),
                                            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        if (objc_getClass("NCNotificationShortLookViewController")) %init(QNotifications);
        if (objc_getClass("CSQuickActionsButton")) %init(QQuickActions);
        if (objc_getClass("NCToggleControl")) %init(QHeaderButtons);
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
