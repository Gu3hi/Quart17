#import "../shared/QGlassCore.h"

static void *QSearchPillMaterialsKey = &QSearchPillMaterialsKey;
static void *QSearchPillUpdatingKey = &QSearchPillUpdatingKey;
static NSHashTable<UIView *> *qSearchPillHosts;

// Temporary diagnostic: sample only the search accessory during its transitions.
@interface QSearchPillTrace : NSObject
@property(nonatomic, weak) UIView *host;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic) NSInteger frames;
@property(nonatomic, copy) NSString *last;
@end

@implementation QSearchPillTrace
- (void)tick:(CADisplayLink *)link {
    UIView *host = self.host;
    if (!host || --self.frames < 0) {
        [link invalidate]; self.link = nil; return;
    }
    NSMutableString *snapshot = [NSMutableString string];
    NSMutableArray *pending = [NSMutableArray arrayWithObject:host];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        CALayer *layer = view.layer;
        CALayer *presentation = layer.presentationLayer;
        [snapshot appendFormat:@"%p %@ parent=%p frame=%@ hidden=%d alpha=%.3f bg=%@ layerBG=%@ radius=%.2f mask=%@ filters=%@ presentation={opacity=%.3f bounds=%@ position=%@ radius=%.2f bg=%@}\n",
            view, NSStringFromClass(view.class), view.superview, NSStringFromCGRect(view.frame),
            view.hidden, view.alpha, view.backgroundColor, layer.backgroundColor,
            layer.cornerRadius, layer.mask, layer.filters,
            presentation ? presentation.opacity : layer.opacity,
            NSStringFromCGRect(presentation ? presentation.bounds : layer.bounds),
            NSStringFromCGPoint(presentation ? presentation.position : layer.position),
            presentation ? presentation.cornerRadius : layer.cornerRadius,
            presentation ? presentation.backgroundColor : layer.backgroundColor];
        [pending addObjectsFromArray:view.subviews];
    }
    if ([snapshot isEqualToString:self.last]) return;
    self.last = snapshot;
    NSString *entry = [NSString stringWithFormat:@"\ntime=%.6f remaining=%ld window=%p hostParent=%p\n%@",
        link.timestamp, (long)self.frames, host.window, host.superview, snapshot];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Documents/com.gushi.quart17-searchdiag.log"];
    @try { [file seekToEndOfFile]; [file writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]]; }
    @catch (NSException *exception) { NSLog(@"Quart17 search trace: %@", exception.name); }
    @finally { [file closeFile]; }
}
@end

static void QTraceSearchPill(UIView *view) {
    UIView *host = view;
    while (host && ![NSStringFromClass(host.class) isEqualToString:@"SBFolderScrollAccessoryView"])
        host = host.superview;
    if (!host) return;
    static QSearchPillTrace *trace;
    if (!trace) trace = [QSearchPillTrace new];
    trace.host = host;
    trace.frames = 90;
    if (!trace.link) {
        trace.last = nil;
        trace.link = [CADisplayLink displayLinkWithTarget:trace selector:@selector(tick:)];
        trace.link.preferredFramesPerSecond = 60;
        [trace.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

static void QUpdateSearchPill(UIView *host) {
    if (!qSearchPillHosts) qSearchPillHosts = [NSHashTable weakObjectsHashTable];
    [qSearchPillHosts addObject:host];
    NSArray<UIView *> *previous = objc_getAssociatedObject(host, QSearchPillMaterialsKey);
    NSMutableArray<UIView *> *materials = [NSMutableArray array];
    UIView *pill = QGlassFind(host, @"SBHSearchPillView");
    // Search presentation fades the pill; keep its material styled during that transition.
    if (host.window && pill &&
        [QGlassReadPref(@"masterEnabled", @YES) boolValue]) {
        UIView *page = QGlassFind(host, @"SBIconListPageControl");
        UIView *content = QGlassFind(page, @"_UIPageControlContentView");
        for (UIView *material in content.subviews.copy) {
            if (![NSStringFromClass(material.class) isEqualToString:@"MTMaterialView"] ||
                !QGlassMaterialIsBackground(material) || CGRectIsEmpty(material.bounds) ||
                (material.hidden && ![previous containsObject:material])) continue;
            [materials addObject:material];
        }
    }
    for (UIView *material in previous)
        if (![materials containsObject:material]) QGlassRemovePopup(material);
    for (UIView *material in materials) {
        QPopupGlassParams params = QPopupGlassParamsFromSettings();
        // The screenshot confirms a 62 x 30 capsule; follow its native mask.
        NSArray *original = objc_getAssociatedObject(material, QGlassOriginalStateKey);
        CGFloat radius = original ? [original[1] doubleValue] : material.layer.cornerRadius;
        params.cornerRadius = radius > 0 ? radius : material.superview.layer.cornerRadius;
        if (params.cornerRadius <= 0) params.cornerRadius = MIN(material.bounds.size.width, material.bounds.size.height) / 2;
        params.veil = 6;
        UIVisualEffectView *glass = QGlassRenderPopup(material, params,
            host.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        glass.alpha = material.alpha;
    }
    objc_setAssociatedObject(host, QSearchPillMaterialsKey, materials, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void QStyleSearchPill(UIView *host) {
    if ([objc_getAssociatedObject(host, QSearchPillUpdatingKey) boolValue]) return;
    objc_setAssociatedObject(host, QSearchPillUpdatingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { QUpdateSearchPill(host); }
    @finally { objc_setAssociatedObject(host, QSearchPillUpdatingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

void QRefreshSearchPills(void) {
    for (UIView *host in qSearchPillHosts.allObjects) QStyleSearchPill(host);
}

static void QStyleSearchPillContent(UIView *content) {
    for (UIView *host = content.superview; host; host = host.superview) {
        if ([NSStringFromClass(host.class) isEqualToString:@"SBFolderScrollAccessoryView"]) {
            QStyleSearchPill(host);
            break;
        }
    }
}

static UIView *QSearchPillMaterialHost(UIView *material) {
    if (![NSStringFromClass(material.superview.class) isEqualToString:@"_UIPageControlContentView"]) return nil;
    for (UIView *host = material.superview; host; host = host.superview)
        if ([NSStringFromClass(host.class) isEqualToString:@"SBFolderScrollAccessoryView"]) {
            NSArray *materials = objc_getAssociatedObject(host, QSearchPillMaterialsKey);
            return [materials containsObject:material] ? host : nil;
        }
    return nil;
}

BOOL QSearchPillMaterialHidden(UIView *material, BOOL hidden) {
    UIView *host = QSearchPillMaterialHost(material);
    UIVisualEffectView *glass = objc_getAssociatedObject(material, QGlassViewKey);
    if (!host || !glass.superview || ![QGlassReadPref(@"masterEnabled", @YES) boolValue]) return hidden;
    // Forward system visibility to our replacement in the same animation transaction.
    // Ignore the renderer's own hidden=YES write; that only suppresses the native material.
    if (![objc_getAssociatedObject(host, QSearchPillUpdatingKey) boolValue]) glass.hidden = hidden;
    return YES;
}

void QSearchPillMaterialAlphaChanged(UIView *material) {
    if (!QSearchPillMaterialHost(material)) return;
    UIVisualEffectView *glass = objc_getAssociatedObject(material, QGlassViewKey);
    if (glass.superview) glass.alpha = material.alpha;
}

%group QSearchPillGlass
%hook SBFolderScrollAccessoryView
- (void)layoutSubviews { %orig; QStyleSearchPill((UIView *)self); }
- (void)didMoveToWindow { %orig; QStyleSearchPill((UIView *)self); }
- (void)setAlpha:(CGFloat)alpha { %orig; QTraceSearchPill((UIView *)self); }
- (void)setHidden:(BOOL)hidden { %orig; QTraceSearchPill((UIView *)self); }
%end
%hook SBHSearchPillView
- (void)setAlpha:(CGFloat)alpha { %orig; QTraceSearchPill((UIView *)self); }
- (void)setHidden:(BOOL)hidden { %orig; QTraceSearchPill((UIView *)self); }
- (void)didMoveToWindow { %orig; QTraceSearchPill((UIView *)self); }
%end
%hook _UIPageControlContentView
- (void)layoutSubviews { %orig; QStyleSearchPillContent((UIView *)self); }
- (void)didMoveToWindow { %orig; QStyleSearchPillContent((UIView *)self); }
- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (!objc_getAssociatedObject(subview, QGlassCompatKey))
        QStyleSearchPillContent((UIView *)self);
}
%end
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] &&
        NSClassFromString(@"SBFolderScrollAccessoryView")) {
        [@"Quart17 2.7.34 search transition diagnostics\n" writeToFile:
            @"/var/mobile/Documents/com.gushi.quart17-searchdiag.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        %init(QSearchPillGlass);
    }
}
