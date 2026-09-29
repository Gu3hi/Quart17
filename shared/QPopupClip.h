#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static void *QPopupClipStateKey = &QPopupClipStateKey;

static void QRestorePopupClip(UIView *material) {
    NSArray *state = objc_getAssociatedObject(material, QPopupClipStateKey);
    for (NSArray *entry in state) {
        UIView *host = [(NSHashTable *)entry.firstObject anyObject];
        if (!host) continue;
        host.layer.cornerRadius = [entry[1] doubleValue];
        host.layer.cornerCurve = entry[2];
        host.clipsToBounds = [entry[3] boolValue];
    }
    objc_setAssociatedObject(material, QPopupClipStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QSyncPopupClip(UIView *material, CGFloat radius) {
    // UIKit puts content and backdrop in separate sibling carriers.
    // Restore first so layout changes cannot leave a previously matched carrier altered.
    UIView *carrier = material.superview;
    if (!carrier) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    QRestorePopupClip(material);
    UIView *scope = [NSStringFromClass(carrier.class) isEqualToString:@"_UIDimmingKnockoutBackdropView"] ?
        carrier.superview : carrier;
    CGRect surface = [material convertRect:material.bounds toView:scope];
    NSMutableArray *states = [NSMutableArray array];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:scope];
    while (pending.count) {
        UIView *host = pending.lastObject;
        [pending removeLastObject];
        if (host == material || [host isKindOfClass:UIVisualEffectView.class]) continue;
        CGRect rect = [host convertRect:host.bounds toView:scope];
        BOOL sameSurface = fabs(rect.origin.x - surface.origin.x) <= 1 &&
            fabs(rect.origin.y - surface.origin.y) <= 1 &&
            fabs(rect.size.width - surface.size.width) <= 1 &&
            fabs(rect.size.height - surface.size.height) <= 1;
        if (sameSurface && host.layer.cornerRadius > 0) {
            NSHashTable *hosts = [NSHashTable weakObjectsHashTable];
            [hosts addObject:host];
            [states addObject:@[hosts, @(host.layer.cornerRadius),
                host.layer.cornerCurve ?: kCACornerCurveCircular, @(host.clipsToBounds)]];
            host.layer.cornerRadius = radius;
            host.layer.cornerCurve = kCACornerCurveContinuous;
            host.clipsToBounds = YES;
        }
        // Only descend along the surface's carriers, not through buttons or row content.
        if (host == scope || sameSurface) [pending addObjectsFromArray:host.subviews];
    }
    objc_setAssociatedObject(material, QPopupClipStateKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction commit];
}
