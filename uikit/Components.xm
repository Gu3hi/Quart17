#import "../shared/QGlassCore.h"
#import <notify.h>

static void *QComponentStateKey = &QComponentStateKey;
static void *QComponentUpdatingKey = &QComponentUpdatingKey;
static NSHashTable<UIView *> *qComponents;
static int qComponentSettingsToken = -1;

static BOOL QComponentEnabled(UIView *view, NSString *key) {
    uint64_t state = 0;
    if (qComponentSettingsToken >= 0 &&
        notify_get_state(qComponentSettingsToken, &state) == NOTIFY_STATUS_OK &&
        (state & ~0xFULL) == 0x51430000ULL) {
        NSUInteger bit = [@[@"masterEnabled", @"appTabBarGlass", @"appNavigationBarGlass", @"appButtonGlass"] indexOfObject:key];
        if (bit != NSNotFound) return view.window && (state & 1) && (state & (1ULL << bit));
    }
    return view.window && [QGlassReadPref(@"masterEnabled", @YES) boolValue] &&
        [QGlassReadPref(key, @NO) boolValue];
}

static UIBlurEffect *QComponentBlur(UIView *view) {
    return [UIBlurEffect effectWithStyle:
        view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ?
            UIBlurEffectStyleSystemUltraThinMaterialDark : UIBlurEffectStyleSystemUltraThinMaterialLight];
}

static void QStyleBar(UIView *bar, NSString *key) {
    NSArray<UIView *> *previous = objc_getAssociatedObject(bar, QComponentStateKey);
    NSMutableArray<UIView *> *materials = [NSMutableArray array];
    BOOL enabled = QComponentEnabled(bar, key);
    if (enabled) {
        // Only UIKit's dedicated bar background: never traverse bar items or content.
        for (UIView *background in bar.subviews) {
            if (![NSStringFromClass(background.class) isEqualToString:@"_UIBarBackground"]) continue;
            for (UIView *material in background.subviews.copy) {
                if (![material isKindOfClass:UIVisualEffectView.class] ||
                    objc_getAssociatedObject(material, QGlassCompatKey) ||
                    (material.hidden && ![previous containsObject:material]) ||
                    !QGlassMaterialIsBackground(material) ||
                    CGRectIsEmpty(material.bounds)) continue;
                [materials addObject:material];
            }
        }
    }
    for (UIView *material in previous)
        if (![materials containsObject:material]) QGlassRemovePopup(material);
    for (UIView *material in materials) {
        QPopupGlassParams params = QPopupGlassParamsFromSettings();
        NSArray *original = objc_getAssociatedObject(material, QGlassOriginalStateKey);
        params.cornerRadius = original ? [original[1] doubleValue] : material.layer.cornerRadius;
        if (params.cornerRadius == 0) params.cornerRadius = material.superview.layer.cornerRadius;
        params.veil = 6;
        QGlassRenderPopup(material, params,
            bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    objc_setAssociatedObject(bar, QComponentStateKey, materials, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL QButtonIsPopupContent(UIView *view) {
    Class alertClass = NSClassFromString(@"_UIAlertControllerView");
    for (UIView *parent = view.superview; parent; parent = parent.superview)
        if ((alertClass && [parent isKindOfClass:alertClass]) ||
            [NSStringFromClass(parent.class) hasPrefix:@"_UIContextMenu"]) return YES;
    return NO;
}

static void QStyleButton(UIButton *button) {
    NSArray *state = objc_getAssociatedObject(button, QComponentStateKey);
    UIButtonConfiguration *current = button.configuration;
    BOOL enabled = QComponentEnabled(button, @"appButtonGlass") && !QButtonIsPopupContent(button);
    if (!enabled) {
        if (state && current == state[1]) button.configuration = state[0];
        objc_setAssociatedObject(button, QComponentStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSNumber *dark = @(button.traitCollection.userInterfaceStyle);
    if (state && current == state[1] && [state[2] isEqual:dark]) return;
    UIButtonConfiguration *original = state && current == state[1] ? state[0] : current;
    UIColor *color = original.background.backgroundColor;
    // Limit the first release to configured system buttons with an actual background.
    if (button.buttonType != UIButtonTypeSystem || !original ||
        (!original.background.visualEffect && (!color ||
         CGColorGetAlpha([color resolvedColorWithTraitCollection:button.traitCollection].CGColor) <= 0))) {
        objc_setAssociatedObject(button, QComponentStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIButtonConfiguration *configuration = [original copy];
    UIBackgroundConfiguration *background = [configuration.background copy];
    background.visualEffect = QComponentBlur(button);
    background.backgroundColor = [color colorWithAlphaComponent:0.12];
    configuration.background = background;
    button.configuration = configuration;
    objc_setAssociatedObject(button, QComponentStateKey,
        @[original, button.configuration, dark], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QStyleComponent(UIView *view) {
    if ([objc_getAssociatedObject(view, QComponentUpdatingKey) boolValue]) return;
    objc_setAssociatedObject(view, QComponentUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if (!qComponents) qComponents = [NSHashTable weakObjectsHashTable];
        [qComponents addObject:view];
        if ([view isKindOfClass:UITabBar.class])
            QStyleBar(view, @"appTabBarGlass");
        else if ([view isKindOfClass:UINavigationBar.class])
            QStyleBar(view, @"appNavigationBarGlass");
        else if ([view isKindOfClass:UIButton.class]) QStyleButton((UIButton *)view);
    } @finally {
        objc_setAssociatedObject(view, QComponentUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void QRefreshComponents(void) {
    for (UIView *view in qComponents.allObjects) QStyleComponent(view);
}

%group QAppComponents
%hook UITabBar
- (void)layoutSubviews { %orig; QStyleComponent((UIView *)self); }
- (void)didMoveToWindow { %orig; QStyleComponent((UIView *)self); }
%end
%hook UINavigationBar
- (void)layoutSubviews { %orig; QStyleComponent((UIView *)self); }
- (void)didMoveToWindow { %orig; QStyleComponent((UIView *)self); }
%end
%hook UIButton
- (void)layoutSubviews { %orig; QStyleComponent((UIView *)self); }
- (void)didMoveToWindow { %orig; QStyleComponent((UIView *)self); }
%end
%end

%ctor {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if ([bundle isEqualToString:@"com.apple.springboard"] ||
        [bundle isEqualToString:@"com.apple.MediaRemoteUI"]) return;
    notify_register_check("com.gushi.quart17/components", &qComponentSettingsToken);
    %init(QAppComponents);
}
