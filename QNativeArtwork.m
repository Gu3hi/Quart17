#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <float.h>
#import <notify.h>

extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);

static NSHashTable<UIView *> *qArtworkViews;
static NSDictionary *qArtworkSettings;
static CADisplayLink *qProgressLink;
static CFTimeInterval qLastInfoRequest;
static CFTimeInterval qProgressAnchorTime;
static NSTimeInterval qProgressAnchorElapsed;
static NSTimeInterval qDuration;
static double qPlaybackRate;
static NSString *qProgressIdentity;
static NSUInteger qBackwardSamples;
static NSUInteger qForwardSamples;
static NSUInteger qProgressRequest, qProgressAcceptedRequest;
static int qCornerStateToken = -1;
static int qSeekStateToken = -1;
static BOOL qSeekDragging;
static CGFloat qSeekFraction;
static CFTimeInterval qSeekHoldUntil;
static BOOL qNativeArtworkExpanded;
static CFTimeInterval qNativeArtworkExpandedAt;
static void *qMediaRemote;
static void (*qGetNowPlayingInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
static CFStringRef *qDurationKey, *qElapsedKey, *qRateKey, *qTitleKey, *qArtistKey;
static const void *qTrackKey = &qTrackKey, *qRingKey = &qRingKey;
static const void *qShadowWasHiddenKey = &qShadowWasHiddenKey;
static const void *qArtworkTapKey = &qArtworkTapKey;
static const void *qAccentImageKey = &qAccentImageKey, *qAccentColorKey = &qAccentColorKey;

static id QInfoValue(NSDictionary *info, CFStringRef *key, NSString *fallback) {
    return info[key && *key ? (__bridge NSString *)*key : fallback];
}

static NSDictionary *QReadArtworkSettings(void) {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    if (settings) return settings;
    CFPreferencesAppSynchronize(CFSTR("com.gushi.quart17"));
    CFArrayRef keys = CFPreferencesCopyKeyList(CFSTR("com.gushi.quart17"),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!keys) return @{};
    CFDictionaryRef values = CFPreferencesCopyMultiple(keys, CFSTR("com.gushi.quart17"),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(keys);
    return CFBridgingRelease(values) ?: @{};
}

static CGFloat QArtworkRoundness(void) {
    uint64_t state = 0;
    if (qCornerStateToken >= 0 && notify_get_state(qCornerStateToken, &state) == NOTIFY_STATUS_OK &&
        (state & 0xffff0000ULL) == 0x51700000ULL) {
        uint64_t expanded = (state >> 48) & 0xffffULL;
        return MIN(1, (expanded <= 10000 ? expanded : (state & 0xffffULL)) / 10000.0);
    }
    id saved = qArtworkSettings[@"largeArtworkRoundness"] ?: qArtworkSettings[@"playerCornerRoundness"];
    CGFloat value = saved ? [saved doubleValue] : 1;
    return isfinite(value) ? MIN(1, MAX(0, value)) : 1;
}

static CGFloat QArtworkScale(void) {
    uint64_t state = 0;
    if (qCornerStateToken >= 0 && notify_get_state(qCornerStateToken, &state) == NOTIFY_STATUS_OK &&
        (state & 0xffff0000ULL) == 0x51700000ULL) {
        uint64_t scaled = (state >> 32) & 0xffffULL;
        if (scaled >= 6000 && scaled <= 10000) return scaled / 10000.0;
    }
    CGFloat value = qArtworkSettings[@"largeArtworkScale"] ?
        [qArtworkSettings[@"largeArtworkScale"] doubleValue] : 1;
    return isfinite(value) ? MIN(1, MAX(0.6, value)) : 1;
}

static void QApplyArtworkScale(UIView *image) {
    CGFloat scale = QArtworkScale();
    UIView *container = image.superview;
    if (!container) return;
    // Scale the native image and our sibling ring from their shared parent.
    // MediaRemoteUI remains free to animate the artwork view for lyrics.
    CGPoint center = CGPointMake(CGRectGetMidX(image.frame), CGRectGetMidY(image.frame));
    CATransform3D current = container.layer.sublayerTransform;
    CGFloat oldScale = current.m11;
    if (!isfinite(oldScale) || oldScale < 0.1 || oldScale > 2) oldScale = 1;
    CGPoint offset = CGPointMake(current.m41 - center.x * (1 - oldScale),
                                 current.m42 - center.y * (1 - oldScale));
    if (container.window) {
        // CALayer conversion includes sublayerTransform; UIView conversion
        // does not reliably reflect the rendered artwork position here.
        CGPoint visible = [image.layer convertPoint:CGPointMake(CGRectGetMidX(image.bounds),
            CGRectGetMidY(image.bounds)) toLayer:container.window.layer];
        CGFloat deltaX = CGRectGetMidX(container.window.bounds) - visible.x;
        if (isfinite(deltaX) && fabs(deltaX) > 0.5) {
            CGPoint a = [container.layer convertPoint:CGPointZero fromLayer:container.window.layer];
            CGPoint b = [container.layer convertPoint:CGPointMake(deltaX, 0)
                fromLayer:container.window.layer];
            offset.x += b.x - a.x;
            offset.y += b.y - a.y;
        }
    }
    CATransform3D scaled = CATransform3DMakeAffineTransform(
        CGAffineTransformMake(scale, 0, 0, scale,
                              center.x * (1 - scale) + offset.x,
                              center.y * (1 - scale) + offset.y));
    if (CATransform3DEqualToTransform(container.layer.sublayerTransform, scaled)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    container.layer.sublayerTransform = scaled;
    [CATransaction commit];
}

static void QRefreshNativeProgress(void) {
    if (!qGetNowPlayingInfo) return;
    NSUInteger request = ++qProgressRequest;
    qGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef data) {
        if (request < qProgressAcceptedRequest) return;
        qProgressAcceptedRequest = request;
        NSDictionary *info = (__bridge NSDictionary *)data;
        if (![info isKindOfClass:NSDictionary.class]) return;
        if (qSeekDragging || CACurrentMediaTime() < qSeekHoldUntil) return;
        id durationValue = QInfoValue(info, qDurationKey, @"kMRMediaRemoteNowPlayingInfoDuration");
        id elapsedValue = QInfoValue(info, qElapsedKey, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
        if (!durationValue || !elapsedValue) return;
        NSTimeInterval duration = [durationValue doubleValue];
        NSTimeInterval elapsed = [elapsedValue doubleValue];
        if (!isfinite(duration) || duration <= 0 || !isfinite(elapsed) || elapsed < 0) return;
        id rateValue = QInfoValue(info, qRateKey, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
        double rate = rateValue ? [rateValue doubleValue] : qPlaybackRate;
        id title = QInfoValue(info, qTitleKey, @"kMRMediaRemoteNowPlayingInfoTitle");
        id artist = QInfoValue(info, qArtistKey, @"kMRMediaRemoteNowPlayingInfoArtist");
        NSString *identity = title ? [NSString stringWithFormat:@"%@|%@", title, artist ?: @""] : nil;
        CFTimeInterval now = CACurrentMediaTime();
        NSTimeInterval reported = isfinite(elapsed) ? MAX(0, elapsed) : 0;
        NSTimeInterval predicted = qProgressAnchorElapsed +
            MAX(0, now - qProgressAnchorTime) * qPlaybackRate;
        BOOL newTrack = (identity && qProgressIdentity && ![identity isEqualToString:qProgressIdentity]) ||
            (qDuration > 0 && duration > 0 && fabs(duration - qDuration) > 5);
        if (newTrack) qBackwardSamples = qForwardSamples = 0;
        BOOL seekedBack = NO;
        BOOL seekedForward = NO;
        // MediaRemote can return an older elapsed time on successive polls.
        // Keep the displayed position monotonic until a track change or a real seek.
        if (qProgressAnchorTime > 0 && !newTrack) {
            if (reported < predicted - 5) {
                // A single stale MediaRemote sample is common. A real backward
                // seek persists across polls, so require three confirmations.
                seekedBack = ++qBackwardSamples >= 3;
                if (!seekedBack) reported = predicted;
                qForwardSamples = 0;
            } else if (reported > predicted + 5) {
                seekedForward = ++qForwardSamples >= 3;
                if (!seekedForward) reported = predicted;
                qBackwardSamples = 0;
            } else {
                qBackwardSamples = qForwardSamples = 0;
                // Small clock differences should not cause visible jumps.
                reported = predicted;
            }
        }
        if (seekedBack || seekedForward) qBackwardSamples = qForwardSamples = 0;
        if (identity) qProgressIdentity = [identity copy];
        qDuration = isfinite(duration) && duration > 0 ? duration : 0;
        qPlaybackRate = isfinite(rate) && rate > 0 ? rate : 0;
        NSTimeInterval position = newTrack || seekedBack || seekedForward ? reported : predicted;
        qProgressAnchorElapsed = MIN(qDuration > 0 ? qDuration : DBL_MAX, position);
        qProgressAnchorTime = now;
    });
}

static void QTickNativeProgress(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - qLastInfoRequest >= 1) {
        qLastInfoRequest = now;
        QRefreshNativeProgress();
    }
    CGFloat fraction = qDuration > 0 ? MIN(1, MAX(0, (qProgressAnchorElapsed +
        MAX(0, now - qProgressAnchorTime) * qPlaybackRate) / qDuration)) : 0;
    if (qSeekDragging || now < qSeekHoldUntil) fraction = qSeekFraction;
    BOOL anyVisible = NO;
    BOOL artworkVisible = NO;
    for (UIView *view in qArtworkViews.allObjects) {
        CAShapeLayer *ring = objc_getAssociatedObject(view, qRingKey);
        if (!view.window || view.hidden || view.alpha < 0.05 ||
            view.bounds.size.width < 150) continue;
        CGRect screenFrame = [view convertRect:view.bounds toView:nil];
        if (!CGRectIntersectsRect(screenFrame, UIScreen.mainScreen.bounds)) continue;
        artworkVisible = YES;
        if (!ring || ring.hidden) continue;
        anyVisible = YES;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ring.strokeEnd = fraction;
        [CATransaction commit];
    }
    if (qNativeArtworkExpanded && !artworkVisible &&
        now - qNativeArtworkExpandedAt > 0.8) {
        qNativeArtworkExpanded = NO;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.gushi.quart17/nativeartworkcollapsed"), NULL, NULL, YES);
    }
    if (!anyVisible) {
        [qProgressLink invalidate];
        qProgressLink = nil;
    }
}

@interface QNativeArtworkTicker : NSObject
@end
@implementation QNativeArtworkTicker
- (void)tick:(CADisplayLink *)link { QTickNativeProgress(); }
@end
static QNativeArtworkTicker *qTicker;

@interface QNativeArtworkTapObserver : NSObject <UIGestureRecognizerDelegate>
@end
@implementation QNativeArtworkTapObserver
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
- (void)tapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !qNativeArtworkExpanded) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!qNativeArtworkExpanded) return;
        qNativeArtworkExpanded = NO;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.gushi.quart17/nativeartworkcollapsed"), NULL, NULL, YES);
    });
}
@end
static QNativeArtworkTapObserver *qArtworkTapObserver;

static UIColor *QArtworkAccent(UIImage *artwork) {
    if (!artwork.CGImage) return UIColor.whiteColor;
    unsigned char pixels[20 * 20 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 20, 20, 8, 20 * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return UIColor.whiteColor;
    CGContextDrawImage(context, CGRectMake(0, 0, 20, 20), artwork.CGImage);
    CGContextRelease(context);
    double r = 0, g = 0, b = 0, total = 0;
    for (NSUInteger i = 0; i < 400; i++) {
        double alpha = pixels[i * 4 + 3] / 255.0;
        if (alpha < 0.3) continue;
        double pr = pixels[i * 4] / 255.0, pg = pixels[i * 4 + 1] / 255.0;
        double pb = pixels[i * 4 + 2] / 255.0;
        double saturation = MAX(pr, MAX(pg, pb)) - MIN(pr, MIN(pg, pb));
        double weight = alpha * (0.25 + saturation * 1.5);
        r += pr * weight; g += pg * weight; b += pb * weight; total += weight;
    }
    if (total <= 0) return UIColor.whiteColor;
    r /= total; g /= total; b /= total;
    double luminance = r * 0.2126 + g * 0.7152 + b * 0.0722;
    if (luminance < 0.4) {
        r = r * 0.55 + 0.45; g = g * 0.55 + 0.45; b = b * 0.55 + 0.45;
    } else if (luminance > 0.8) {
        r *= 0.72; g *= 0.72; b *= 0.72;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

static void QRoundArtworkLayers(CALayer *layer, CGSize imageSize, CGFloat radius,
                                NSUInteger depth) {
    if (!layer || depth > 3) return;
    if ([layer isKindOfClass:CAShapeLayer.class]) return;
    CGSize size = layer.bounds.size;
    if (fabs(size.width - imageSize.width) < 40 &&
        fabs(size.height - imageSize.height) < 40 &&
        fabs(size.width - size.height) < 40) {
        if (layer.mask) layer.mask = nil;
        if (fabs(layer.cornerRadius - radius) > 0.1) layer.cornerRadius = radius;
        if (![layer.cornerCurve isEqualToString:kCACornerCurveCircular])
            layer.cornerCurve = kCACornerCurveCircular;
        if (!layer.masksToBounds) layer.masksToBounds = YES;
    }
    for (CALayer *child in layer.sublayers) {
        QRoundArtworkLayers(child, imageSize, radius, depth + 1);
    }
}

static void QStyleNativeArtwork(UIView *view) {
    if (view.bounds.size.width < 150 || view.bounds.size.height < 150) return;
    SEL imageSelector = @selector(artworkImageView);
    if (![view respondsToSelector:imageSelector]) return;
    UIView *image = ((id (*)(id, SEL))objc_msgSend)(view, imageSelector);
    if (![image isKindOfClass:UIView.class] || CGRectIsEmpty(image.bounds)) return;
    UIView *ringHost = image.superview ?: view;
    QApplyArtworkScale(image);
    CGFloat roundness = QArtworkRoundness();
    CGFloat radius = MIN(image.bounds.size.width, image.bounds.size.height) * roundness / 2;
    // MRUArtworkView also masks a square wrapper around the image. Styling
    // only artworkImageView leaves that wrapper circular at every slider value.
    for (UIView *part = image; part; part = part.superview) {
        CGSize size = part.bounds.size;
        if (fabs(size.width - image.bounds.size.width) < 40 &&
            fabs(size.height - image.bounds.size.height) < 40 &&
            fabs(size.width - size.height) < 40) {
            QRoundArtworkLayers(part.layer, image.bounds.size, radius, 0);
        }
        if (part == view) break;
    }
    // The progress stroke sits outside the artwork, so ancestor clipping must
    // not cut it back to the image's original square bounds.
    for (UIView *part = image.superview; part; part = part.superview) {
        CGSize size = part.bounds.size;
        if (fabs(size.width - image.bounds.size.width) < 40 &&
            fabs(size.height - image.bounds.size.height) < 40)
            if (part.layer.masksToBounds) part.layer.masksToBounds = NO;
        if (part == view) break;
    }

    if (!objc_getAssociatedObject(view, qArtworkTapKey)) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:qArtworkTapObserver action:@selector(tapped:)];
        tap.cancelsTouchesInView = NO;
        tap.delegate = qArtworkTapObserver;
        [view addGestureRecognizer:tap];
        objc_setAssociatedObject(view, qArtworkTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // The system's separate rectangular artwork shadow remains visible behind
    // a circular cover. Hide only that shadow; keep the native artwork itself.
    SEL shadowSelector = @selector(artworkShadowView);
    UIView *shadow = [view respondsToSelector:shadowSelector] ?
        ((id (*)(id, SEL))objc_msgSend)(view, shadowSelector) : nil;
    if ([shadow isKindOfClass:UIView.class]) {
        NSNumber *wasHidden = objc_getAssociatedObject(shadow, qShadowWasHiddenKey);
        if (!wasHidden) {
            wasHidden = @(shadow.hidden);
            objc_setAssociatedObject(shadow, qShadowWasHiddenKey, wasHidden,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        shadow.hidden = roundness > 0 ? YES : wasHidden.boolValue;
    }

    CAShapeLayer *track = objc_getAssociatedObject(view, qTrackKey);
    CAShapeLayer *ring = objc_getAssociatedObject(view, qRingKey);
    if (!track) {
        track = [CAShapeLayer layer];
        ring = [CAShapeLayer layer];
        for (CAShapeLayer *layer in @[track, ring]) {
            layer.fillColor = UIColor.clearColor.CGColor;
            layer.lineWidth = 6;
            layer.lineCap = kCALineCapRound;
            [ringHost.layer addSublayer:layer];
        }
        objc_setAssociatedObject(view, qTrackKey, track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, qRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (track.superlayer != ringHost.layer) {
        [track removeFromSuperlayer];
        [ring removeFromSuperlayer];
        [ringHost.layer addSublayer:track];
        [ringHost.layer addSublayer:ring];
    }
    UIImage *artwork = [image isKindOfClass:UIImageView.class] ? ((UIImageView *)image).image : nil;
    if (!artwork && [view respondsToSelector:@selector(artworkImage)]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(view, @selector(artworkImage));
        if ([value isKindOfClass:UIImage.class]) artwork = value;
    }
    UIImage *previousArtwork = objc_getAssociatedObject(view, qAccentImageKey);
    UIColor *accent = objc_getAssociatedObject(view, qAccentColorKey);
    if (!accent || previousArtwork != artwork) {
        accent = QArtworkAccent(artwork);
        objc_setAssociatedObject(view, qAccentImageKey, artwork, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, qAccentColorKey, accent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    track.strokeColor = [accent colorWithAlphaComponent:0.3].CGColor;
    ring.strokeColor = accent.CGColor;
    // The compact player's progressStyle selects one of its three layouts.
    // Expanded system artwork has no progress bar or background track, so its
    // progress indication is always the artwork ring when progress is enabled.
    BOOL showRing = !qArtworkSettings[@"showProgress"] ||
                    [qArtworkSettings[@"showProgress"] boolValue];
    track.hidden = !showRing;
    ring.hidden = !showRing;
    CGRect imageFrame = image.frame;
    CGRect ringFrame = CGRectInset(imageFrame, -7, -7);
    CGFloat ringRadius = roundness > 0 ?
        MIN(MIN(imageFrame.size.width, imageFrame.size.height) * roundness / 2 + 7,
            ringFrame.size.width / 2) : 0;
    CGFloat left = CGRectGetMinX(ringFrame), right = CGRectGetMaxX(ringFrame);
    CGFloat top = CGRectGetMinY(ringFrame), bottom = CGRectGetMaxY(ringFrame);
    // Begin at twelve o'clock and follow the outside edge clockwise.
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, CGRectGetMidX(ringFrame), top);
    CGPathAddLineToPoint(path, NULL, right - ringRadius, top);
    if (ringRadius > 0) CGPathAddArcToPoint(path, NULL, right, top,
                                            right, top + ringRadius, ringRadius);
    CGPathAddLineToPoint(path, NULL, right, bottom - ringRadius);
    if (ringRadius > 0) CGPathAddArcToPoint(path, NULL, right, bottom,
                                            right - ringRadius, bottom, ringRadius);
    CGPathAddLineToPoint(path, NULL, left + ringRadius, bottom);
    if (ringRadius > 0) CGPathAddArcToPoint(path, NULL, left, bottom,
                                            left, bottom - ringRadius, ringRadius);
    CGPathAddLineToPoint(path, NULL, left, top + ringRadius);
    if (ringRadius > 0) CGPathAddArcToPoint(path, NULL, left, top,
                                            left + ringRadius, top, ringRadius);
    CGPathCloseSubpath(path);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    track.frame = ringHost.bounds;
    ring.frame = ringHost.bounds;
    track.path = path;
    ring.path = path;
    [CATransaction commit];
    CGPathRelease(path);
    [qArtworkViews addObject:view];
    if (showRing && !qProgressLink) {
        qTicker = [QNativeArtworkTicker new];
        qProgressLink = [CADisplayLink displayLinkWithTarget:qTicker selector:@selector(tick:)];
        qProgressLink.preferredFramesPerSecond = 30;
        [qProgressLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        qLastInfoRequest = 0;
    }
}

static void (*qOriginalArtworkLayout)(id, SEL);
static void QArtworkLayout(id self, SEL cmd) {
    qOriginalArtworkLayout(self, cmd);
    QStyleNativeArtwork((UIView *)self);
}

static void QToggleNativeArtwork(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // MediaRemoteUI's compact scene exists before MRULockscreenViewController.
        // The coordinator's own platter-tap action creates the expanded scene
        // and drives the native cover, background, and transition together.
        Class coordinatorClass = objc_getClass("_TtC13MediaRemoteUI21LockScreenCoordinator");
        id coordinator = coordinatorClass && [coordinatorClass respondsToSelector:@selector(shared)]
            ? ((id (*)(id, SEL))objc_msgSend)(coordinatorClass, @selector(shared)) : nil;
        if (coordinator && [coordinator respondsToSelector:@selector(handlePlatterTap)]) {
            ((BOOL (*)(id, SEL))objc_msgSend)(coordinator, @selector(handlePlatterTap));
            qNativeArtworkExpanded = YES;
            qNativeArtworkExpandedAt = CACurrentMediaTime();
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.gushi.quart17/nativeartworkexpanded"), NULL, NULL, YES);
        }
    });
}

static void QNativeArtworkChanged(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        qArtworkSettings = QReadArtworkSettings();
        for (UIView *view in qArtworkViews.allObjects) QStyleNativeArtwork(view);
    });
}

static void QNativeArtworkSeekChanged(CFNotificationCenterRef center, void *observer,
                                      CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        uint64_t state = 0;
        if (qSeekStateToken < 0 ||
            notify_get_state(qSeekStateToken, &state) != NOTIFY_STATUS_OK) return;
        uint64_t amount = state & ~(1ULL << 63);
        if (amount > 1000000) return;
        qSeekFraction = amount / 1000000.0;
        qSeekDragging = (state & (1ULL << 63)) != 0;
        if (!qSeekDragging) {
            CFTimeInterval now = CACurrentMediaTime();
            qProgressAnchorElapsed = qDuration * qSeekFraction;
            qProgressAnchorTime = now;
            qSeekHoldUntil = now + 2.5;
        }
        QTickNativeProgress();
    });
}

void QInstallNativeArtworkHooks(void) {
    notify_register_check("com.gushi.quart17/playercorner", &qCornerStateToken);
    notify_register_check("com.gushi.quart17/artworkseek", &qSeekStateToken);
    qArtworkTapObserver = [QNativeArtworkTapObserver new];
    qArtworkViews = [NSHashTable weakObjectsHashTable];
    qArtworkSettings = QReadArtworkSettings();
    qMediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (qMediaRemote) {
        qGetNowPlayingInfo = dlsym(qMediaRemote, "MRMediaRemoteGetNowPlayingInfo");
        qDurationKey = dlsym(qMediaRemote, "kMRMediaRemoteNowPlayingInfoDuration");
        qElapsedKey = dlsym(qMediaRemote, "kMRMediaRemoteNowPlayingInfoElapsedTime");
        qRateKey = dlsym(qMediaRemote, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
        qTitleKey = dlsym(qMediaRemote, "kMRMediaRemoteNowPlayingInfoTitle");
        qArtistKey = dlsym(qMediaRemote, "kMRMediaRemoteNowPlayingInfoArtist");
    }
    dlopen("/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls", RTLD_LAZY);
    Class artworkClass = objc_getClass("MRUArtworkView");
    if (artworkClass) MSHookMessageEx(artworkClass, @selector(layoutSubviews),
        (IMP)QArtworkLayout, (IMP *)&qOriginalArtworkLayout);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        QNativeArtworkChanged, CFSTR("com.gushi.quart17/preferenceschanged"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        QToggleNativeArtwork, CFSTR("com.gushi.quart17/togglenativeartwork"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        QNativeArtworkSeekChanged, CFSTR("com.gushi.quart17/artworkseek"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}
