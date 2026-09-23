#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreFoundation/CoreFoundation.h>
#import <stdlib.h>
#import "QPlayerView.h"

static NSString *const QPrefs = @"com.gushi.quart17";
static NSMutableDictionary *qSettings;
static NSHashTable<QPlayerView *> *qActivePlayers;
static NSHashTable<UIView *> *qActivePlatters;
static NSHashTable<UIView *> *qActiveNotifications;
static NSHashTable<UIView *> *qActiveLists;
static NSHashTable<UIView *> *qActiveBanners;
static UIWindow *qTestBannerWindow;
static UIView *qTestBannerMaterial;
static UILabel *qTestBannerTitle;
static UILabel *qTestBannerMessage;
static NSTimer *qTestBannerVisibilityTimer;
static void *QOriginalStyleKey = &QOriginalStyleKey;
static void *QOwnLayerTransformKey = &QOwnLayerTransformKey;
static void *QOriginalLayerTransformKey = &QOriginalLayerTransformKey;
static void *QScalePendingKey = &QScalePendingKey;
static void *QOriginalIndicatorKey = &QOriginalIndicatorKey;
static void *QBannerOriginalTransformKey = &QBannerOriginalTransformKey;
static void *QBannerOwnedTransformKey = &QBannerOwnedTransformKey;
static void *QBannerShadowHiddenKey = &QBannerShadowHiddenKey;
static void *QBannerGlassKey = &QBannerGlassKey;
static void *QBannerGlassSheenKey = &QBannerGlassSheenKey;
static void *QBannerGlassBackdropKey = &QBannerGlassBackdropKey;
static void *QBannerGlassBlurKey = &QBannerGlassBlurKey;
static void *QBannerGlassMeshKey = &QBannerGlassMeshKey;
static void *QBannerGlassStyleKey = &QBannerGlassStyleKey;
static void *QBannerGlassCompatibilityKey = &QBannerGlassCompatibilityKey;
static void *QLockGlassShadowHiddenKey = &QLockGlassShadowHiddenKey;
static void *QLockOriginalInterfaceStyleKey = &QLockOriginalInterfaceStyleKey;
static __weak id qMasterList;
static CFAbsoluteTime qLastRightSwipe;
static void *QSearchPanInstalledKey = &QSearchPanInstalledKey;
static void *QSearchPanEligibleKey = &QSearchPanEligibleKey;
static void *QSearchPanQualifiedKey = &QSearchPanQualifiedKey;



static void QStyle(UIView *root);
static CGFloat QShrinkScale(void);
static void QApplyListScaling(UIView *list);
static void QScheduleListScaling(UIView *list);
static void QClearOwnLayerTransform(UIView *list);
static void QApplyBannerScaling(UIView *banner);
static void QRefreshTestBanner(void);
static void QShowTestBanner(void);
static void QHideTestBanner(void);

@interface NCNotificationShortLookViewController : UIViewController
- (UIView *)viewForPreview;
@end

static void QLoadSettings(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    qSettings = [@{ @"masterEnabled": @YES, @"enabled": @YES, @"darkCards": @NO,
                    @"roundIcons": @YES, @"radius": @24,
                    @"playerEnabled": @YES, @"disableListScaling": @NO,
                    @"scaleBanners": @NO, @"glassBanners": @NO,
                    @"glassBlur": @8, @"glassRefraction": @12, @"glassHighlight": @0.5,
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

static void QUpdateGlassRefraction(CALayer *backdrop, CGSize size, CGFloat radius,
                                   CGFloat magnitude, UIVisualEffectView *glass) {
    Class meshClass = NSClassFromString(@"CAMutableMeshTransform");
    SEL create = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    if (!backdrop || !meshClass || ![meshClass respondsToSelector:create] ||
        size.width < 30 || size.height < 30) return;
    NSString *signature = [NSString stringWithFormat:@"%.1f:%.1f:%.1f:%.1f",
                           size.width, size.height, radius, magnitude];
    if ([signature isEqual:objc_getAssociatedObject(glass, QBannerGlassMeshKey)]) return;
    NSArray<NSNumber *> *xs = QGlassGrid(size.width);
    NSArray<NSNumber *> *ys = QGlassGrid(size.height);
    NSUInteger columns = xs.count, rows = ys.count;
    NSUInteger vertexCount = columns * rows;
    NSUInteger faceCount = (columns - 1) * (rows - 1);
    QGlassVertex *vertices = (QGlassVertex *)calloc(vertexCount, sizeof(QGlassVertex));
    QGlassFace *faces = (QGlassFace *)calloc(faceCount, sizeof(QGlassFace));
    if (!vertices || !faces) { free(vertices); free(faces); return; }
    CGFloat edgeDistance = 13;
    for (NSUInteger row = 0; row < rows; row++) {
        CGFloat y = ys[row].doubleValue;
        for (NSUInteger column = 0; column < columns; column++) {
            CGFloat x = xs[column].doubleValue;
            CGFloat distance = -QGlassSDF(x, y, size, radius);
            CGFloat weight = MAX(0, MIN(1, 1 - distance / edgeDistance));
            weight *= weight * (3 - 2 * weight);
            CGFloat nx = QGlassSDF(x + 0.5, y, size, radius) - QGlassSDF(x - 0.5, y, size, radius);
            CGFloat ny = QGlassSDF(x, y + 0.5, size, radius) - QGlassSDF(x, y - 0.5, size, radius);
            CGFloat norm = hypot(nx, ny);
            if (norm > 0) { nx /= norm; ny /= norm; }
            NSUInteger index = row * columns + column;
            vertices[index].from = CGPointMake(MAX(0, MIN(1, (x - nx * weight * magnitude) / size.width)),
                                                MAX(0, MIN(1, (y - ny * weight * magnitude) / size.height)));
            vertices[index].to = (QGlassPoint3D){x / size.width, y / size.height, 0};
        }
    }
    for (NSUInteger row = 0; row + 1 < rows; row++) {
        for (NSUInteger column = 0; column + 1 < columns; column++) {
            QGlassFace *face = &faces[row * (columns - 1) + column];
            uint32_t top = (uint32_t)(row * columns + column);
            face->indices[0] = top;
            face->indices[1] = top + 1;
            face->indices[2] = top + (uint32_t)columns + 1;
            face->indices[3] = top + (uint32_t)columns;
        }
    }
    @try {
        IMP imp = [meshClass methodForSelector:create];
        id (*makeMesh)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id) =
            (id (*)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id))imp;
        id mesh = makeMesh(meshClass, create, vertexCount, vertices, faceCount, faces, @"none");
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
    free(vertices);
    free(faces);
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

static void QApplyBannerGlass(UIView *root, UIView *material) {
    if (!material) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(material, QBannerGlassKey);
    BOOL enabled = [qSettings[@"masterEnabled"] boolValue] &&
        [qSettings[@"enabled"] boolValue] && [qSettings[@"glassBanners"] boolValue] &&
        (QIsDesktopBanner(root) || QIsLockScreenNotification(root));
    if (!enabled || !material.superview) {
        [glass removeFromSuperview];
        objc_setAssociatedObject(material, QBannerGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        QSetLockGlassShadowHidden(material, NO);
        return;
    }
    BOOL lockNotification = QIsLockScreenNotification(root);
    QSetLockGlassShadowHidden(material, lockNotification);
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
        glass.layer.cornerCurve = kCACornerCurveContinuous;
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
        sheen.locations = @[@0, @0.48, @1];
        [glass.contentView.layer addSublayer:sheen];
        objc_setAssociatedObject(glass, QBannerGlassSheenKey, sheen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(material, QBannerGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITraitCollection *systemTraits = lockNotification ? root.window.traitCollection : root.traitCollection;
    BOOL systemDark = systemTraits.userInterfaceStyle == UIUserInterfaceStyleDark;
    // The Lock Screen cell must stay in dark appearance to avoid black
    // collapsed-stack materials in light system appearance. Match the banner's
    // glass treatment while keeping that independent appearance choice.
    BOOL dark = lockNotification || systemDark;
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
    glass.contentView.backgroundColor = nil;
    glass.frame = material.frame;
    glass.autoresizingMask = material.autoresizingMask;
    CALayer *backdrop = objc_getAssociatedObject(glass, QBannerGlassBackdropKey);
    backdrop.frame = glass.bounds;
    id blurFilter = objc_getAssociatedObject(glass, QBannerGlassBlurKey);
    if (blurFilter) [blurFilter setValue:@(blurRadius) forKey:@"inputRadius"];
    QUpdateGlassRefraction(backdrop, glass.bounds.size, glass.layer.cornerRadius,
                           refraction, glass);
    glass.layer.cornerRadius = material.layer.cornerRadius;
    glass.layer.borderWidth = compatibleLockGlass ? 0 : 0.75;
    // A white rim disappears against bright apps. Use a faint dark outline in
    // light mode while retaining the specular top edge inside the material.
    glass.layer.borderColor = (dark ? [UIColor colorWithWhite:1 alpha:0.26] :
                                    [UIColor colorWithWhite:0 alpha:0.16]).CGColor;
    CAGradientLayer *sheen = objc_getAssociatedObject(glass, QBannerGlassSheenKey);
    sheen.frame = glass.bounds;
    sheen.colors = dark ? @[(id)[UIColor colorWithWhite:1 alpha:0.26 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.04 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.13].CGColor]
                        : @[(id)[UIColor colorWithWhite:1 alpha:0.52 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.05 * highlight].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.08].CGColor];
    sheen.opacity = 1;
    if (glass.superview != material.superview)
        [material.superview insertSubview:glass aboveSubview:material];
    material.hidden = YES;
}

// A persistent SpringBoard preview uses the exact desktop glass renderer.
// It is deliberately separate from BulletinBoard, so testing never adds a
// real notification to Notification Center or changes app alert settings.
static void QRefreshTestBanner(void) {
    if (!qTestBannerWindow || !qTestBannerMaterial) return;
    UIView *root = qTestBannerWindow.rootViewController.view;
    CGFloat radius = MAX(8, MIN(40, [qSettings[@"radius"] doubleValue]));
    root.layer.cornerRadius = radius;
    root.layer.cornerCurve = kCACornerCurveContinuous;
    root.clipsToBounds = YES;
    qTestBannerMaterial.frame = root.bounds;
    qTestBannerMaterial.layer.cornerRadius = radius;
    qTestBannerMaterial.layer.cornerCurve = kCACornerCurveContinuous;
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
    QSetLockNotificationAppearance(appearanceRoot,
        stylingEnabled && lockNotification ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified);
    [qActiveNotifications addObject:root];
    QRestoreStyle(root);
    UIView *material = QFind(root, @"MTMaterialView");
    if (![qSettings[@"masterEnabled"] boolValue] || ![qSettings[@"enabled"] boolValue]) {
        QApplyBannerGlass(root, material);
        return;
    }
    CGFloat radius = MAX(8, MIN(40, [qSettings[@"radius"] doubleValue]));
    QRememberStyle(root);
    root.layer.cornerRadius = radius;
    root.layer.cornerCurve = kCACornerCurveContinuous;
    root.clipsToBounds = YES;

    if (material) {
        QRememberStyle(material);
        material.layer.cornerRadius = radius;
        material.layer.cornerCurve = kCACornerCurveContinuous;
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
            UILabel *label = (UILabel *)view;
            QRememberStyle(label);
            // The glass replaces Apple's material, so its labels must follow
            // the current appearance even for notifications already on screen.
            if ([qSettings[@"darkCards"] boolValue] || lockNotification) {
                label.textColor = UIColor.whiteColor;
            } else if ([qSettings[@"glassBanners"] boolValue] &&
                       (QIsLockScreenNotification(root) || QIsDesktopBanner(root))) {
                label.textColor = QAdaptiveGlassTextColor();
            }
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
        QApplyListScaling(list);
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
        qActiveBanners = [NSHashTable weakObjectsHashTable];
        QLoadSettings();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        QChanged, CFSTR("com.gushi.quart17/preferenceschanged"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
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
