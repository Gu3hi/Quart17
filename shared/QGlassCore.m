// QGlassCore.m - Quart17 共享玻璃核心实现
// 精简版：只含弹窗玻璃所需的设置、渲染、恢复逻辑。

#import "QGlassCore.h"
#import "QPopupClip.h"
#import <objc/message.h>
#import <math.h>

// MARK: - 设置

NSString *const QPrefsBundleID = @"com.gushi.quart17";
static NSMutableDictionary *qGlassSettingsDict = nil;

NSMutableDictionary *QGlassSettings(void) {
    return qGlassSettingsDict;
}

void QGlassLoadSettings(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    // Sandboxed applications may not be able to open the shared plist directly.
    if (![saved isKindOfClass:NSDictionary.class]) {
        CFPreferencesSynchronize((__bridge CFStringRef)QPrefsBundleID,
                                kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        saved = CFBridgingRelease(CFPreferencesCopyMultiple(
            (__bridge CFArrayRef)@[@"masterEnabled", @"alertGlassBlur", @"alertGlassRefraction",
                                  @"alertGlassHighlight", @"alertVeil", @"alertForceDark",
                                  @"appTabBarGlass", @"appNavigationBarGlass", @"appButtonGlass"],
            (__bridge CFStringRef)QPrefsBundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    }
    NSMutableDictionary *defaults = [@{
        @"masterEnabled": @YES,
        @"alertGlassBlur": @8, @"alertGlassRefraction": @12, @"alertGlassHighlight": @0.5,
        @"alertVeil": @28, @"alertForceDark": @YES,
        @"appTabBarGlass": @NO, @"appNavigationBarGlass": @NO, @"appButtonGlass": @NO,
    } mutableCopy];
    if ([saved isKindOfClass:NSDictionary.class]) [defaults addEntriesFromDictionary:saved];
    qGlassSettingsDict = defaults;
}

id QGlassReadPref(NSString *key, id defaultValue) {
    id v = qGlassSettingsDict[key];
    return v ?: defaultValue;
}

void QGlassWritePref(NSString *key, id value) {
    if (!qGlassSettingsDict) QGlassLoadSettings();
    qGlassSettingsDict[key] = value;
    [qGlassSettingsDict writeToFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"
                         atomically:YES];
}

// MARK: - 关联键

void *QGlassViewKey = &QGlassViewKey;
void *QGlassCompatKey = &QGlassCompatKey;
void *QGlassSheenKey = &QGlassSheenKey;
void *QGlassRimKey = &QGlassRimKey;
void *QGlassRimMaskKey = &QGlassRimMaskKey;
void *QGlassBackdropKey = &QGlassBackdropKey;
void *QGlassBlurFilterKey = &QGlassBlurFilterKey;
void *QGlassStyleKey = &QGlassStyleKey;
void *QGlassOriginalStateKey = &QGlassOriginalStateKey;

// 弹窗外观恢复跟踪
static NSMapTable<UIView *, NSNumber *> *qAlertOriginalStyles = nil;
static NSMapTable<UIView *, NSHashTable<UIView *> *> *qAlertMaterials;
static NSHashTable<UIView *> *qTrackedAlerts;
static NSMapTable<UIView *, NSMapTable<UIView *, NSNumber *> *> *qPopupShadows;
static void *QAlertStylingKey = &QAlertStylingKey;

static void QRestorePopupShadows(UIView *root) {
    NSMapTable *shadows = [qPopupShadows objectForKey:root];
    for (UIView *shadow in shadows.keyEnumerator.allObjects)
        shadow.hidden = [[shadows objectForKey:shadow] boolValue];
    [qPopupShadows removeObjectForKey:root];
}

static void QHidePopupShadows(UIView *root) {
    UIView *scope = root;
    if ([NSStringFromClass(root.class) isEqualToString:@"_UIContextMenuListView"]) {
        for (UIView *parent = root.superview; parent; parent = parent.superview) {
            if ([NSStringFromClass(parent.class) isEqualToString:@"_UIContextMenuView"]) {
                scope = parent;
                break;
            }
        }
    }
    if (!qPopupShadows) qPopupShadows = [NSMapTable weakToStrongObjectsMapTable];
    NSMapTable *shadows = [qPopupShadows objectForKey:root];
    if (!shadows) {
        shadows = [NSMapTable weakToStrongObjectsMapTable];
        [qPopupShadows setObject:shadows forKey:root];
    }
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:scope];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (objc_getAssociatedObject(view, QGlassCompatKey)) continue;
        if ([NSStringFromClass(view.class) isEqualToString:@"_UICutoutShadowView"]) {
            if (![shadows objectForKey:view]) [shadows setObject:@(view.hidden) forKey:view];
            view.hidden = YES;
            continue;
        }
        [pending addObjectsFromArray:view.subviews];
    }
}

void QGlassRefreshAlerts(void) {
    for (UIView *alert in qTrackedAlerts.allObjects)
        QGlassStyleSystemAlert(alert);
}

void QGlassRestoreSystemAlert(UIView *alert) {
    NSNumber *styling = objc_getAssociatedObject(alert, QAlertStylingKey);
    objc_setAssociatedObject(alert, QAlertStylingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        QRestorePopupShadows(alert);
        for (UIView *material in [qAlertMaterials objectForKey:alert].allObjects)
            QGlassRemovePopup(material);
        [qAlertMaterials removeObjectForKey:alert];
        NSNumber *originalStyle = [qAlertOriginalStyles objectForKey:alert];
        if (originalStyle) {
            [qAlertOriginalStyles removeObjectForKey:alert];
            alert.overrideUserInterfaceStyle = (UIUserInterfaceStyle)originalStyle.integerValue;
        }
    } @finally {
        objc_setAssociatedObject(alert, QAlertStylingKey, styling, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - 基础工具

BOOL QGlassHasAncestor(UIView *view, NSString *className) {
    for (UIView *a = view.superview; a; a = a.superview) {
        if ([NSStringFromClass(a.class) isEqualToString:className]) return YES;
    }
    return NO;
}

UIView *QGlassFind(UIView *root, NSString *className) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = QGlassFind(sub, className);
        if (found) return found;
    }
    return nil;
}

// MARK: - 弹窗玻璃参数

QPopupGlassParams QPopupGlassParamsFromSettings(void) {
    QPopupGlassParams p;
    p.blur = [QGlassReadPref(@"alertGlassBlur", @8) doubleValue];
    p.refraction = [QGlassReadPref(@"alertGlassRefraction", @12) doubleValue];
    p.highlight = [QGlassReadPref(@"alertGlassHighlight", @0.5) doubleValue];
    p.veil = [QGlassReadPref(@"alertVeil", @28) doubleValue];
    p.forceDark = [QGlassReadPref(@"alertForceDark", @YES) boolValue];
    p.cornerRadius = 24;
    // 钳制
    if (!isfinite(p.blur)) p.blur = 8; p.blur = MAX(0, MIN(18, p.blur));
    if (!isfinite(p.refraction)) p.refraction = 12; p.refraction = MAX(0, MIN(24, p.refraction));
    if (!isfinite(p.highlight)) p.highlight = 0.5; p.highlight = MAX(0, MIN(1, p.highlight));
    if (!isfinite(p.veil)) p.veil = 28; p.veil = MAX(0, MIN(30, p.veil));
    return p;
}

// MARK: - 弹窗玻璃渲染

UIVisualEffectView *QGlassRenderPopup(UIView *material, QPopupGlassParams params, BOOL dark) {
    if (!material || !material.superview) return nil;
    // UIKit rejects direct insertion into an effect view (confirmed by crash logs).
    if ([material.superview isKindOfClass:UIVisualEffectView.class]) return nil;

    // 保存原始状态（首次）
    if (!objc_getAssociatedObject(material, QGlassOriginalStateKey)) {
        objc_setAssociatedObject(material, QGlassOriginalStateKey,
            @[@(material.hidden), @(material.layer.cornerRadius),
              material.layer.cornerCurve ?: kCACornerCurveContinuous, @(material.clipsToBounds)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIVisualEffectView *glass = objc_getAssociatedObject(material, QGlassViewKey);
    if (!glass) {
        glass = [[UIVisualEffectView alloc] initWithEffect:nil];
        objc_setAssociatedObject(glass, QGlassCompatKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glass.userInteractionEnabled = NO;
        glass.clipsToBounds = YES;
        glass.layer.cornerCurve = kCACornerCurveContinuous;

        // 实时背景模糊层
        Class backdropClass = NSClassFromString(@"CABackdropLayer");
        Class filterClass = NSClassFromString(@"CAFilter");
        SEL filterSelector = NSSelectorFromString(@"filterWithName:");
        if (backdropClass && filterClass && [filterClass respondsToSelector:filterSelector]) {
            @try {
                CALayer *backdrop = ((id (*)(id, SEL))objc_msgSend)(backdropClass, @selector(layer));
                id blur = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, filterSelector, @"gaussianBlur");
                if (backdrop && blur) {
                    [blur setValue:@(params.blur) forKey:@"inputRadius"];
                    [backdrop setValue:@[blur] forKey:@"filters"];
                    [backdrop setValue:@1 forKey:@"scale"];
                    backdrop.rasterizationScale = UIScreen.mainScreen.scale;
                    [glass.layer insertSublayer:backdrop atIndex:0];
                    objc_setAssociatedObject(glass, QGlassBackdropKey, backdrop,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(glass, QGlassBlurFilterKey, blur,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } @catch (NSException *e) {}
        }

        // 高光 sheen
        CAGradientLayer *sheen = [CAGradientLayer layer];
        sheen.locations = @[@0, @0.16, @0.56, @1];
        [glass.contentView.layer addSublayer:sheen];
        objc_setAssociatedObject(glass, QGlassSheenKey, sheen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 边缘 rim
        CAGradientLayer *rim = [CAGradientLayer layer];
        rim.locations = @[@0, @0.22, @0.7, @1];
        CALayer *rimMask = [CALayer layer];
        rimMask.borderColor = UIColor.whiteColor.CGColor;
        rimMask.borderWidth = 0.9;
        rimMask.cornerCurve = kCACornerCurveContinuous;
        rim.mask = rimMask;
        [glass.contentView.layer addSublayer:rim];
        objc_setAssociatedObject(glass, QGlassRimKey, rim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(glass, QGlassRimMaskKey, rimMask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(material, QGlassViewKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 更新模糊
    UIBlurEffectStyle style = dark ? UIBlurEffectStyleSystemUltraThinMaterialDark :
                                     UIBlurEffectStyleSystemUltraThinMaterialLight;
    NSNumber *styleNumber = @(style);
    NSNumber *oldStyle = objc_getAssociatedObject(glass, QGlassStyleKey);
    CALayer *backdrop = objc_getAssociatedObject(glass, QGlassBackdropKey);
    if (!backdrop && (![oldStyle isEqualToNumber:styleNumber] ||
        glass.overrideUserInterfaceStyle != (dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight))) {
        glass.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        glass.effect = [UIBlurEffect effectWithStyle:style];
        objc_setAssociatedObject(glass, QGlassStyleKey, styleNumber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id blurFilter = objc_getAssociatedObject(glass, QGlassBlurFilterKey);
    if (blurFilter) [blurFilter setValue:@(params.blur) forKey:@"inputRadius"];

    // 底色浓度
    CGFloat veil = params.veil / 100.0;
    glass.contentView.backgroundColor = dark ? [UIColor colorWithWhite:0 alpha:veil] :
                                               [UIColor colorWithWhite:1 alpha:veil];

    // 定位与圆角
    CGFloat shortSide = MIN(material.bounds.size.width, material.bounds.size.height);
    CGFloat cardRadius = MIN(params.cornerRadius, shortSide / 2);
    // Do not modify UIVisualEffectView's private child hierarchy or effect.
    // Only content-free backgrounds are replaced. Preserve full layer geometry
    // and reassert ordering on every layout, including menu transitions.
    glass.bounds = material.bounds;
    glass.layer.anchorPoint = material.layer.anchorPoint;
    glass.layer.position = material.layer.position;
    glass.layer.transform = material.layer.transform;
    glass.layer.zPosition = material.layer.zPosition;
    glass.autoresizingMask = material.autoresizingMask;
    [material.superview insertSubview:glass belowSubview:material];
    material.hidden = YES;
    glass.layer.cornerRadius = cardRadius;
    QSyncPopupClip(material, cardRadius);
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 0;

    if (backdrop) backdrop.frame = glass.bounds;
    QUpdateGlassRefraction(backdrop, glass.bounds.size, cardRadius,
                          params.refraction * 0.65, glass);

    CAGradientLayer *sheen = objc_getAssociatedObject(glass, QGlassSheenKey);
    sheen.frame = glass.bounds;
    CGFloat hl = params.highlight;
    sheen.colors = dark ? @[(id)[UIColor colorWithWhite:1 alpha:0.22 * hl].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.07 * hl].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.01].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.11].CGColor]
                        : @[(id)[UIColor colorWithWhite:1 alpha:0.34 * hl].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.12 * hl].CGColor,
                             (id)[UIColor colorWithWhite:1 alpha:0.01].CGColor,
                             (id)[UIColor colorWithWhite:0 alpha:0.07].CGColor];

    CAGradientLayer *rim = objc_getAssociatedObject(glass, QGlassRimKey);
    CALayer *rimMask = objc_getAssociatedObject(glass, QGlassRimMaskKey);
    rim.frame = glass.bounds;
    CGFloat inset = rimMask.borderWidth / 2;
    rimMask.frame = CGRectInset(rim.bounds, inset, inset);
    rimMask.cornerRadius = MAX(0, cardRadius - inset);
    rimMask.cornerCurve = kCACornerCurveContinuous;
    rim.colors = dark ? @[(id)[UIColor colorWithWhite:1 alpha:0.34 * hl].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.12 * hl].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.04 * hl].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.16 * hl].CGColor]
                      : @[(id)[UIColor colorWithWhite:1 alpha:0.52 * hl].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.18 * hl].CGColor,
                          (id)[UIColor colorWithWhite:0 alpha:0.08 * hl].CGColor,
                          (id)[UIColor colorWithWhite:1 alpha:0.28 * hl].CGColor];

    return glass;
}

void QGlassRemovePopup(UIView *material) {
    if (!material) return;
    QRestorePopupClip(material);
    UIVisualEffectView *glass = objc_getAssociatedObject(material, QGlassViewKey);
    [glass removeFromSuperview];
    objc_setAssociatedObject(material, QGlassViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 恢复原始状态
    NSArray *original = objc_getAssociatedObject(material, QGlassOriginalStateKey);
    if (original) {
        material.hidden = [original[0] boolValue];
        material.layer.cornerRadius = [original[1] doubleValue];
        material.layer.cornerCurve = original[2];
        material.clipsToBounds = [original[3] boolValue];
        objc_setAssociatedObject(material, QGlassOriginalStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// MARK: - 系统弹窗样式

// Replacing a material that contains text or controls would hide the content.
BOOL QGlassMaterialIsBackground(UIView *material) {
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:material.subviews];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIControl.class] ||
            [view isKindOfClass:UITextView.class] || [view isKindOfClass:UIImageView.class] ||
            [view isKindOfClass:UIScrollView.class] || view.gestureRecognizers.count)
            return NO;
        [pending addObjectsFromArray:view.subviews];
    }
    return YES;
}

void QGlassStyleSystemAlert(UIView *alert) {
    if (!alert || [objc_getAssociatedObject(alert, QAlertStylingKey) boolValue]) return;
    objc_setAssociatedObject(alert, QAlertStylingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if (!qTrackedAlerts) qTrackedAlerts = [NSHashTable weakObjectsHashTable];
        [qTrackedAlerts addObject:alert];
        if (!alert.window || ![QGlassReadPref(@"masterEnabled", @YES) boolValue]) {
            QGlassRestoreSystemAlert(alert);
            return;
        }

        // Work only inside the alert or menu list, never the application window.
        NSMutableArray<UIView *> *materials = [NSMutableArray array];
        NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:alert.subviews];
        CGFloat windowArea = alert.window.bounds.size.width * alert.window.bounds.size.height;
        while (pending.count) {
            UIView *view = pending.lastObject;
            [pending removeLastObject];
            if (objc_getAssociatedObject(view, QGlassCompatKey)) continue;
            NSString *name = NSStringFromClass(view.class);
            BOOL candidate = [view isKindOfClass:UIVisualEffectView.class] ||
                             [name isEqualToString:@"MTMaterialView"];
            if (candidate) {
                CGSize size = view.bounds.size;
                if (size.width >= 80 && size.height >= 30 &&
                    size.width * size.height < windowArea * 0.85 &&
                    ![view.superview isKindOfClass:UIVisualEffectView.class] &&
                    QGlassMaterialIsBackground(view))
                    [materials addObject:view];
                // Nested materials belong to the same surface; never double-style it.
                continue;
            }
            [pending addObjectsFromArray:view.subviews];
        }
        NSHashTable<UIView *> *previous = [qAlertMaterials objectForKey:alert];
        for (UIView *material in previous.allObjects)
            if (![materials containsObject:material]) QGlassRemovePopup(material);
        if (!materials.count) {
            QGlassRestoreSystemAlert(alert);
            return;
        }

        if (!qAlertOriginalStyles) qAlertOriginalStyles = [NSMapTable weakToStrongObjectsMapTable];
        NSNumber *originalStyle = [qAlertOriginalStyles objectForKey:alert];
        if (!originalStyle) {
            originalStyle = @(alert.overrideUserInterfaceStyle);
            [qAlertOriginalStyles setObject:originalStyle forKey:alert];
        }
        QPopupGlassParams params = QPopupGlassParamsFromSettings();
        UIUserInterfaceStyle forcedStyle = params.forceDark ? UIUserInterfaceStyleDark :
            (UIUserInterfaceStyle)originalStyle.integerValue;
        if (alert.overrideUserInterfaceStyle != forcedStyle)
            alert.overrideUserInterfaceStyle = forcedStyle;
        BOOL dark = params.forceDark ||
            alert.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;

        if (!qAlertMaterials) qAlertMaterials = [NSMapTable weakToStrongObjectsMapTable];
        NSHashTable<UIView *> *current = [NSHashTable weakObjectsHashTable];
        [qAlertMaterials setObject:current forKey:alert];
        for (UIView *material in materials) {
            [current addObject:material];
            QGlassRenderPopup(material, params, dark);
        }
        // Cutout shadows use a separate native silhouette, independent of cornerRadius.
        QHidePopupShadows(alert);
    } @finally {
        objc_setAssociatedObject(alert, QAlertStylingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
