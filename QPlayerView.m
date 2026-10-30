#import "QPlayerView.h"
#import <AVKit/AVKit.h>
#import <QuartzCore/CADisplayLink.h>
#import <dlfcn.h>
#import <objc/message.h>
#ifdef Q_ROOTHIDE
#import <roothide.h>
#define QJbroot(path) jbroot(path)
#else
// 标准 Rootless：直接使用 /var/jb 前缀
#define QJbroot(path) [@"/var/jb" stringByAppendingString:(path)]
#endif
#import <notify.h>
#import <math.h>



static NSDictionary *QReadPreferenceDomain(NSString *domain) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:
        [@"/var/mobile/Library/Preferences/" stringByAppendingFormat:@"%@.plist", domain]];
    if ([saved isKindOfClass:NSDictionary.class]) return saved;
    CFStringRef identifier = (__bridge CFStringRef)domain;
    CFPreferencesAppSynchronize(identifier);
    CFArrayRef keys = CFPreferencesCopyKeyList(identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!keys) return @{};
    CFDictionaryRef values = CFPreferencesCopyMultiple(keys, identifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(keys);
    return CFBridgingRelease(values) ?: @{};
}

// Vela icon themes: Quart17 shows the same media.previous / media.play / media.next artwork as Vela.
static NSString *QVelaThemeRoot(void) {
#ifdef Q_ROOTHIDE
    return jbroot(@"/Library/Themes/Vela");
#else
    return @"/var/mobile/Library/Theme/Vela";
#endif
}

static BOOL QVelaComponent(id name) {
    return [name isKindOfClass:NSString.class] && [name length] > 0 && [name length] <= 255 &&
        ![name isEqualToString:@"."] && ![name isEqualToString:@".."] &&
        [name rangeOfString:@"/"].location == NSNotFound && [name rangeOfString:@"\\"].location == NSNotFound &&
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

static NSString *QVelaThemeFolderNamed(NSString *name) {
    if (!QVelaComponent(name) || [name hasPrefix:@"."]) return nil;
    NSString *folder = [QVelaThemeRoot() stringByAppendingPathComponent:name];
    BOOL directory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&directory] && directory ? folder : nil;
}

// Same rule as Vela's PIconUsesTheme/PIconReadTheme: only folder themes, and "system" turns them off.
static NSString *QVelaThemeFolder(NSDictionary *vela) {
    id identifier = vela[@"iconTheme"];
    if ([vela[@"iconSource"] isEqual:@"system"] || ![identifier isKindOfClass:NSString.class] ||
        ![identifier hasPrefix:@"folder:"]) return nil;
    return QVelaThemeFolderNamed([identifier substringFromIndex:7]);
}

uint32_t QVelaThemeHash(NSString *folder) {
    // FNV-1a of the theme folder name; MediaRemoteUI matches it against the theme directory.
    uint32_t hash = 2166136261u;
    for (const unsigned char *c = (const unsigned char *)folder.lastPathComponent.UTF8String; c && *c; c++)
        hash = (hash ^ *c) * 16777619u;
    return hash;
}

static NSString *QVelaThemeFolderForHash(uint32_t hash) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:QVelaThemeRoot() error:nil]) {
        NSString *folder = QVelaThemeFolderNamed(name);
        if (folder && QVelaThemeHash(folder) == hash) return folder;
    }
    return nil;
}

NSDictionary *QReadPlayerSettings(void) {
    NSDictionary *saved = QReadPreferenceDomain(@"com.gushi.quart17");
    NSMutableDictionary *settings = [@{ @"masterEnabled": @YES, @"enabled": @YES,
                    @"smallLockClock": @NO,
                    @"smallLockClockFontSize": @23,
                    @"playerEnabled": @YES, @"disableListScaling": @NO,
                     @"scaleBanners": @NO,
                    @"showNotificationCount": @YES, @"notificationsFromTop": @NO,
                    @"playerBorderEnabled": @NO, @"playerBorderWidth": @1.5,
                    @"largeArtworkOffsetY": @0,
                    @"clearAllEnabled": @YES, @"clearHapticEnabled": @YES,
                    @"showProgress": @YES, @"backgroundProgress": @YES, @"hideRoute": @YES,
                     @"hideControls": @NO, @"customControlIcons": @NO,
                    @"titleFromArtwork": @YES, @"artistFromArtwork": @YES,
                    @"progressFromArtwork": @YES, @"backgroundFromArtwork": @YES } mutableCopy];
    if ([saved isKindOfClass:NSDictionary.class]) [settings addEntriesFromDictionary:saved];
    if (!settings[@"progressStyle"]) {
        settings[@"progressStyle"] = [settings[@"backgroundProgress"] boolValue] ? @0 : @1;
    }
    NSDictionary *aura = QReadPreferenceDomain(@"com.gushi.aura");
    // Quart17 owns the player corner; Aura's former value is only a migration fallback.
    settings[@"playerCornerRoundness"] = saved[@"playerCornerRoundness"] ?: aura[@"playerCornerRoundness"] ?:
        (saved[@"roundArtwork"] && ![saved[@"roundArtwork"] boolValue] ? @0 : @1);
    if (!settings[@"largeArtworkRoundness"])
        settings[@"largeArtworkRoundness"] = settings[@"playerCornerRoundness"];
    // Aura's player glass replaces the panel surface; the border is only drawn while it is off.
    settings[@"auraPlayerGlass"] = @([aura[@"masterEnabled"] ?: @YES boolValue] && [aura[@"playerGlass"] boolValue]);
    NSString *velaTheme = QVelaThemeFolder(QReadPreferenceDomain(@"com.gushi.vela"));
    if (velaTheme) settings[@"velaThemeFolder"] = velaTheme;
    // MediaRemoteUI cannot reliably read the mobile user's preference domain.
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) {
        static int flagsToken = -1;
        if (flagsToken < 0) notify_register_check("com.gushi.quart17/artworkflags", &flagsToken);
        uint64_t flags = 0;
        if (flagsToken >= 0 && notify_get_state(flagsToken, &flags) == NOTIFY_STATUS_OK &&
            (flags & ~4095ULL) == 0x51710000ULL) {
            settings[@"masterEnabled"] = @((flags & 1) != 0);
            settings[@"playerEnabled"] = @((flags & 2) != 0);
            settings[@"showProgress"] = @((flags & 4) != 0);
            NSUInteger style = (flags >> 3) & 3;
            if (style) settings[@"progressStyle"] = @(style - 1);
            if (flags & (1ULL << 11)) {
                NSArray *keys = @[@"hideControls", @"hideRoute", @"backgroundFromArtwork", @"titleFromArtwork", @"artistFromArtwork", @"progressFromArtwork"];
                for (NSUInteger i = 0; i < keys.count; i++)
                    settings[keys[i]] = @((flags & (1ULL << (i + 5))) != 0);
            }
        }
        static int cornerToken = -1;
        if (cornerToken < 0) notify_register_check("com.gushi.quart17/playercorner", &cornerToken);
        uint64_t corner = 0;
        if (cornerToken >= 0 && notify_get_state(cornerToken, &corner) == NOTIFY_STATUS_OK &&
            (corner & 0xffff0000ULL) == 0x51700000ULL && (corner & 0xffffULL) <= 10000)
            settings[@"playerCornerRoundness"] = @((corner & 0xffffULL) / 10000.0);
        // Border: bit 15 = enabled, low bits = width in hundredths of a point.
        static int borderToken = -1;
        if (borderToken < 0) notify_register_check("com.gushi.quart17/playerborder", &borderToken);
        uint64_t border = 0;
        if (borderToken >= 0 && notify_get_state(borderToken, &border) == NOTIFY_STATUS_OK &&
            (border & 0xffff0000ULL) == 0x51720000ULL) {
            settings[@"playerBorderEnabled"] = @((border & 0x8000ULL) != 0);
            settings[@"playerBorderWidth"] = @((border & 0x7fffULL) / 100.0);
        }
        // Aura publishes its component switches here (bit 0 master, bit 7 player glass).
        static int auraToken = -1;
        if (auraToken < 0) notify_register_check("com.gushi.aura/components", &auraToken);
        uint64_t auraState = 0;
        if (auraToken >= 0 && notify_get_state(auraToken, &auraState) == NOTIFY_STATUS_OK &&
            (auraState & 0xffff0000ULL) == 0x51430000ULL)
            settings[@"auraPlayerGlass"] = @((auraState & 1ULL) && (auraState & (1ULL << 7)));
        // SpringBoard publishes Vela's theme: tag 0x5173 in the top 16 bits, bit 32 = theme on, low 32 = name hash,
        // bit 33 = Quart17's own static icons are switched on.
        static int velaToken = -1;
        if (velaToken < 0) notify_register_check("com.gushi.quart17/velatheme", &velaToken);
        uint64_t vela = 0;
        if (velaToken >= 0 && notify_get_state(velaToken, &vela) == NOTIFY_STATUS_OK && (vela >> 48) == 0x5173ULL) {
            NSString *folder = (vela & (1ULL << 32)) ? QVelaThemeFolderForHash((uint32_t)vela) : nil;
            if (folder) settings[@"velaThemeFolder"] = folder;
            else [settings removeObjectForKey:@"velaThemeFolder"];
            settings[@"customControlIcons"] = @((vela & (1ULL << 33)) != 0);
        }
    }
    return [settings copy];
}

NSString *QCornerCurveForRoundness(CGFloat roundness) {
    return isfinite(roundness) && roundness >= 0.999 ? kCACornerCurveCircular : kCACornerCurveContinuous;
}

CGPathRef QCreateRoundedRingPath(CGRect rect, CGFloat radius, CGFloat roundness) {
    CGFloat left = CGRectGetMinX(rect), right = CGRectGetMaxX(rect);
    CGFloat top = CGRectGetMinY(rect), bottom = CGRectGetMaxY(rect), midX = CGRectGetMidX(rect);
    radius = MAX(0, MIN(radius, MIN(rect.size.width, rect.size.height) / 2));
    if (radius > 0 && [QCornerCurveForRoundness(roundness) isEqualToString:kCACornerCurveContinuous]) {
        // UIKit's rounded rect is Apple's continuous outline but starts near the top-left corner.
        // Re-start it at the top centre so a ring's strokeEnd grows clockwise from 12 o'clock.
        CGPathRef source = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius].CGPath;
        CGMutablePathRef path = CGPathCreateMutable();
        __block BOOL started = NO, valid = YES, closed = NO;
        CGPathApplyWithBlock(source, ^(const CGPathElement *element) {
            const CGPoint *p = element->points;
            switch (element->type) {
                case kCGPathElementMoveToPoint:
                    if (started || fabs(p[0].y - top) > 0.01 || p[0].x > midX + 0.01) valid = NO;
                    started = YES;
                    CGPathMoveToPoint(path, NULL, midX, top);
                    break;
                case kCGPathElementAddLineToPoint:
                    CGPathAddLineToPoint(path, NULL, p[0].x, p[0].y);
                    break;
                case kCGPathElementAddQuadCurveToPoint:
                    CGPathAddQuadCurveToPoint(path, NULL, p[0].x, p[0].y, p[1].x, p[1].y);
                    break;
                case kCGPathElementAddCurveToPoint:
                    CGPathAddCurveToPoint(path, NULL, p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y);
                    break;
                case kCGPathElementCloseSubpath:
                    if (closed) valid = NO;
                    closed = YES;
                    CGPathAddLineToPoint(path, NULL, midX, top);
                    CGPathCloseSubpath(path);
                    break;
            }
        });
        if (valid && started) {
            if (!closed) {
                CGPathAddLineToPoint(path, NULL, midX, top);
                CGPathCloseSubpath(path);
            }
            return path;
        }
        CGPathRelease(path);
        return CGPathCreateCopy(source);
    }
    // Circular corners: begin at twelve o'clock and follow the edge clockwise.
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, midX, top);
    CGPathAddLineToPoint(path, NULL, right - radius, top);
    if (radius > 0) CGPathAddArcToPoint(path, NULL, right, top, right, top + radius, radius);
    CGPathAddLineToPoint(path, NULL, right, bottom - radius);
    if (radius > 0) CGPathAddArcToPoint(path, NULL, right, bottom, right - radius, bottom, radius);
    CGPathAddLineToPoint(path, NULL, left + radius, bottom);
    if (radius > 0) CGPathAddArcToPoint(path, NULL, left, bottom, left, bottom - radius, radius);
    CGPathAddLineToPoint(path, NULL, left, top + radius);
    if (radius > 0) CGPathAddArcToPoint(path, NULL, left, top, left + radius, top, radius);
    CGPathCloseSubpath(path);
    return path;
}

typedef void (^QInfoCompletion)(CFDictionaryRef);
typedef void (^QPlayingCompletion)(Boolean);
static void (*QGetInfo)(dispatch_queue_t, QInfoCompletion);
static void (*QGetPlaying)(dispatch_queue_t, QPlayingCompletion);
static Boolean (*QSendCommand)(int, id);
static void (*QSetElapsed)(double);
static void (*QRegisterNotifications)(dispatch_queue_t);
static CFStringRef *QTitleKey, *QArtistKey, *QArtworkKey, *QDurationKey;
static CFStringRef *QElapsedKey, *QTimestampKey, *QRateKey;
static CFStringRef *QUniqueKey;
static int qExpandedSeekToken = -1;

static void QPublishExpandedSeek(CGFloat fraction, BOOL dragging) {
    if (qExpandedSeekToken < 0)
        notify_register_check("com.gushi.quart17/artworkseek", &qExpandedSeekToken);
    if (qExpandedSeekToken < 0) return;
    uint64_t value = (dragging ? (1ULL << 63) : 0) |
        (uint64_t)llround(MIN(1, MAX(0, fraction)) * 1000000);
    notify_set_state(qExpandedSeekToken, value);
    notify_post("com.gushi.quart17/artworkseek");
}

static NSTimeInterval QMetadataTimestamp(id value) {
    if ([value isKindOfClass:NSDate.class]) return [value timeIntervalSince1970];
    if ([value isKindOfClass:NSNumber.class]) return [value doubleValue];
    return 0;
}

static CGFloat QPlayerBorderWidth(NSDictionary *settings);

static NSString *QKey(CFStringRef *symbol, NSString *fallback) {
    return symbol && *symbol ? (__bridge NSString *)*symbol : fallback;
}

static BOOL QLoadMediaRemote(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!handle) return;
        QGetInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        QGetPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        QSendCommand = dlsym(handle, "MRMediaRemoteSendCommand");
        QSetElapsed = dlsym(handle, "MRMediaRemoteSetElapsedTime");
        QRegisterNotifications = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        QTitleKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoTitle");
        QArtistKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoArtist");
        QArtworkKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoArtworkData");
        QDurationKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoDuration");
        QElapsedKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoElapsedTime");
        QTimestampKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoTimestamp");
        QRateKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
        QUniqueKey = dlsym(handle, "kMRMediaRemoteNowPlayingInfoUniqueIdentifier");
        if (QRegisterNotifications) QRegisterNotifications(dispatch_get_main_queue());
    });
    return QGetInfo != NULL && QSendCommand != NULL;
}

@interface QMarqueeLabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@end

@implementation QMarqueeLabel {
    UILabel *_label;
    BOOL _needsMarqueeLayout;
    CGSize _lastBoundsSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        _label = [UILabel new];
        _label.numberOfLines = 1;
        _label.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_label];
        _needsMarqueeLayout = YES;
    }
    return self;
}

- (void)setText:(NSString *)text {
    NSString *value = [text isKindOfClass:NSString.class] ? text : @"";
    if ([_text isEqualToString:value]) return;
    _text = [value copy];
    _label.text = value;
    _needsMarqueeLayout = YES;
    [self setNeedsLayout];
}

- (void)setFont:(UIFont *)font {
    _font = font;
    _label.font = font;
    _needsMarqueeLayout = YES;
    [self setNeedsLayout];
}

- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor;
    _label.textColor = textColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_needsMarqueeLayout && CGSizeEqualToSize(_lastBoundsSize, self.bounds.size)) return;
    _needsMarqueeLayout = NO;
    _lastBoundsSize = self.bounds.size;
    [_label.layer removeAnimationForKey:@"quartMarquee"];
    CGFloat visible = self.bounds.size.width;
    CGFloat textWidth = ceil([self.text sizeWithAttributes:@{NSFontAttributeName: self.font ?: [UIFont systemFontOfSize:14]}].width) + 2;
    _label.frame = CGRectMake(0, 0, MAX(visible, textWidth), self.bounds.size.height);
    CGFloat travel = MAX(0, textWidth - visible);
    if (travel <= 1 || visible <= 0) {
        self.layer.mask = nil;
        return;
    }
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.frame = self.bounds;
    fade.startPoint = CGPointMake(0, 0.5);
    fade.endPoint = CGPointMake(1, 0.5);
    fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor,
                    (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    fade.locations = @[@0, @0.07, @0.93, @1];
    self.layer.mask = fade;
    NSTimeInterval move = MAX(2, travel / 28.0);
    NSTimeInterval total = 2 + 2 * move;
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    animation.values = @[@0, @0, @(-travel), @(-travel), @0];
    animation.keyTimes = @[@0, @(1 / total), @((1 + move) / total),
                           @((2 + move) / total), @1];
    animation.calculationMode = kCAAnimationLinear;
    animation.duration = total;
    animation.repeatCount = HUGE_VALF;
    [_label.layer addAnimation:animation forKey:@"quartMarquee"];
}

@end

static NSString *QVelaResource(NSString *root, id relative) {
    if (![root isKindOfClass:NSString.class] || !root.length || ![relative isKindOfClass:NSString.class] ||
        ![relative length] || [relative isAbsolutePath]) return nil;
    for (NSString *part in [relative pathComponents]) if (!QVelaComponent(part)) return nil;
    NSString *base = root.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSString *path = [base stringByAppendingPathComponent:relative].stringByResolvingSymlinksInPath;
    if (![path hasPrefix:[base stringByAppendingString:@"/"]]) return nil;
    return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}

static NSDictionary *QVelaSafePlist(NSString *path) {
    if (!path) return nil;
    if ([NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize > 1048576) return nil;
    id plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return [plist isKindOfClass:NSDictionary.class] ? plist : nil;
}

// Names the vendored Vela host expects.
static inline NSString *PFResource(NSString *root, id relative) { return QVelaResource(root, relative); }
static inline NSDictionary *PFSafePlist(NSString *path) { return QVelaSafePlist(path); }
#import "VelaCAIconHost.h"

static NSString *QVelaPNG(NSString *root, id stem) {
    if (![stem isKindOfClass:NSString.class] || ![stem length]) return nil;
    if ([[stem pathExtension].lowercaseString isEqualToString:@"png"]) return QVelaResource(root, stem);
    for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png"]) {
        NSString *path = QVelaResource(root, [stem stringByAppendingString:suffix]);
        if (path) return path;
    }
    return nil;
}

static NSDictionary *QVelaMapping(NSString *root, NSString *key) {
    NSDictionary *manifest = QVelaSafePlist(QVelaResource(root, @"VelaTheme.plist")) ?:
        QVelaSafePlist(QVelaResource(root, @"PrysmTheme.plist"));
    id icons = manifest[@"Icons"];
    id mapping = [icons isKindOfClass:NSDictionary.class] ? icons[key] : nil;
    return [mapping isKindOfClass:NSDictionary.class] ? mapping : nil;
}

static BOOL QVelaPackage(NSString *path) {
    return [path.pathExtension isEqualToString:@"ca"] && QVelaResource(path, @"main.caml") != nil;
}

// Where the art for one Quart17 button comes from. With "custom playback icons" on, Quart17's own
// button folder comes first (works without Vela). Otherwise, and for any missing file, Vela's order
// (PIconView refresh): a theme's explicit PNG, the theme's CA animation, the theme's other PNG names,
// then Vela's default: the native animated MediaControls glyph, and an SF Symbol only if that is missing.
static NSDictionary *QControlArt(NSString *root, NSString *key, NSString *state, NSString *ownName, NSString *symbol,
                                 BOOL custom) {
    NSString *own = custom ? QVelaPNG(QJbroot(@"/Library/Application Support/Quart17/Buttons"), ownName) : nil;
    if (own) return @{@"png": own};
    BOOL playing = [state isEqualToString:@"playing"];
    NSDictionary *mapping = root ? QVelaMapping(root, key) : nil;
    NSString *systemPackage = [key isEqualToString:@"media.play"] ? @"PlayPauseStop.ca" : @"ForwardBackward.ca";
    NSArray *packageStates = [key isEqualToString:@"media.play"] ? @[playing ? @"pause" : @"play"] : @[state, @"State 1", @"default"];
    id mappedState = [mapping[@"States"] isKindOfClass:NSDictionary.class] ? mapping[@"States"][state] : nil;
    if ([mappedState isKindOfClass:NSString.class]) packageStates = @[mappedState];
    if (root) {
        NSMutableArray *explicitStems = [NSMutableArray new];
        id images = mapping[@"Images"];
        if ([images isKindOfClass:NSDictionary.class] && (images[state] ?: images[@"default"]))
            [explicitStems addObject:images[state] ?: images[@"default"]];
        [explicitStems addObjectsFromArray:@[[NSString stringWithFormat:@"Icons/%@/%@", key, state],
                                             [NSString stringWithFormat:@"Icons/%@/default", key],
                                             [@"Icons" stringByAppendingPathComponent:key]]];
        NSString *legacy = @{@"media.previous": @"rewind", @"media.next": @"skip"}[key] ?: (playing ? @"pause" : @"play");
        NSString *onOff = playing ? @"-on" : @"-off";
        NSString *prysm = [@"Folders/Prysm/Icons" stringByAppendingPathComponent:legacy];
        [explicitStems addObjectsFromArray:@[[prysm stringByAppendingString:onOff], prysm]];
        for (id stem in explicitStems) {
            NSString *path = QVelaPNG(root, stem);
            if (path) return @{@"png": path, @"theme": @YES};
        }
        NSString *package = [mapping[@"Package"] isKindOfClass:NSString.class] ? QVelaResource(root, mapping[@"Package"]) : nil;
        if (!QVelaPackage(package)) package = QVelaResource(root, [NSString stringWithFormat:@"Animations/%@.ca", key]);
        if (!QVelaPackage(package)) {
            package = nil;
            for (NSString *prefix in @[@"映射文件", @"", @"Animations"]) {
                NSString *candidate = QVelaResource(root, [prefix stringByAppendingPathComponent:
                    [@"PrivateFrameworks/MediaControls.framework" stringByAppendingPathComponent:systemPackage]]);
                if (QVelaPackage(candidate)) { package = candidate; break; }
            }
        }
        if (package) {
            id mirror = mapping[@"Mirror"];
            BOOL mirrored = [mirror isKindOfClass:NSNumber.class] ? [mirror boolValue] :
                ([key isEqualToString:@"media.previous"] && !mapping[@"Package"] &&
                 ([package.lastPathComponent isEqualToString:@"ForwardBackward.ca"] ||
                  [package.lastPathComponent isEqualToString:@"media.previous.ca"]));
            return @{@"package": package, @"states": packageStates, @"mirror": @(mirrored)};
        }
        NSArray *names = @{@"media.previous": @[@"backward.fill"], @"media.next": @[@"forward.fill"]}[key] ?:
            (playing ? @[@"pause.fill", @"pause"] : @[@"play.fill", @"play"]);
        NSMutableArray *stems = [NSMutableArray new];
        for (NSString *name in names) [stems addObject:[@"Bundles/com.apple.MediaControls" stringByAppendingPathComponent:name]];
        for (NSString *stem in @[[@"Icons" stringByAppendingPathComponent:legacy], legacy])
            [stems addObjectsFromArray:@[[stem stringByAppendingString:onOff], stem]];
        for (NSString *name in names) [stems addObjectsFromArray:@[[@"UIImages" stringByAppendingPathComponent:name], name]];
        for (id stem in stems) {
            NSString *path = QVelaPNG(root, stem);
            if (path) return @{@"png": path, @"theme": @YES};
        }
    }
    NSString *native = [@"/System/Library/PrivateFrameworks/MediaControls.framework" stringByAppendingPathComponent:systemPackage];
    if (QVelaPackage(native))
        return @{@"package": native, @"states": packageStates, @"native": @YES,
                 @"mirror": @([key isEqualToString:@"media.previous"])};
    return @{@"symbol": symbol};
}

// Trim transparent margins (as Vela does); single-ink art stays tintable, colored art keeps its colors.
static UIImage *QPreparedGlyph(UIImage *image, BOOL forceTemplate) {
    if (!image || image.size.width < 1 || image.size.height < 1) return nil;
    const CGFloat side = 128;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIImage *sample = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            CGFloat scale = MIN(side / image.size.width, side / image.size.height);
            [image drawInRect:CGRectMake((side - image.size.width * scale) / 2, (side - image.size.height * scale) / 2,
                                         image.size.width * scale, image.size.height * scale)];
        }];
    NSMutableData *buffer = [NSMutableData dataWithLength:128 * 128 * 4];
    unsigned char *pixels = buffer.mutableBytes;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 128, 128, 8, 512, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), sample.CGImage);
    CGContextRelease(context);
    NSInteger left = 128, top = 128, right = -1, bottom = -1;
    BOOL single = YES, found = NO;
    CGFloat reference[3] = {0};
    for (NSInteger y = 0; y < 128; y++) for (NSInteger x = 0; x < 128; x++) {
        unsigned char *p = pixels + (y * 128 + x) * 4;
        if (p[3] > 24) { left = MIN(left, x); right = MAX(right, x); top = MIN(top, y); bottom = MAX(bottom, y); }
        if (p[3] < 48 || !single) continue;
        CGFloat r = (CGFloat)p[0] / p[3], g = (CGFloat)p[1] / p[3], b = (CGFloat)p[2] / p[3];
        CGFloat high = MAX(r, MAX(g, b)), low = MIN(r, MIN(g, b));
        if (high - low > .065 && high > .22) single = NO;
        else if (!found) { reference[0] = r; reference[1] = g; reference[2] = b; found = YES; }
        else if (fabs(r - reference[0]) > .065 || fabs(g - reference[1]) > .065 || fabs(b - reference[2]) > .065) single = NO;
    }
    if (right < left) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(sample.CGImage, CGRectMake(left, top, right - left + 1, bottom - top + 1));
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return [result imageWithRenderingMode:forceTemplate || (single && found) ?
            UIImageRenderingModeAlwaysTemplate : UIImageRenderingModeAlwaysOriginal];
}

static UIImage *QArtImage(NSDictionary *art) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 32; });
    NSString *path = art[@"png"];
    NSDate *modified = path ? [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate : nil;
    NSString *cacheKey = path ? [NSString stringWithFormat:@"%@|%f", path, modified.timeIntervalSince1970] : art[@"symbol"];
    if (!cacheKey) return nil;
    UIImage *glyph = [cache objectForKey:cacheKey];
    if (glyph) return glyph;
    if (path) {
        NSData *data = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize <= 4194304 ?
            [NSData dataWithContentsOfFile:path] : nil;
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        // Quart17's own folder has always been drawn as a template; Vela art keeps its colors if it has any.
        if (MAX(image.size.width * image.scale, image.size.height * image.scale) <= 1024)
            glyph = QPreparedGlyph(image, ![art[@"theme"] boolValue]);
    } else {
        glyph = QPreparedGlyph([UIImage systemImageNamed:art[@"symbol"] withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightRegular]], YES);
    }
    if (glyph) [cache setObject:glyph forKey:cacheKey];
    return glyph;
}

@interface QGlyphButton : UIButton
@property (nonatomic) BOOL visuallyHidden;
@property (nonatomic) CGFloat iconSize;
// The glyph is fitted inside this fraction of iconSize (width, height).
@property (nonatomic) CGSize glyphBox;
@property (nonatomic, strong) UIImageView *glyphView;
@property (nonatomic, strong) PCAIconHost *animationHost;
@property (nonatomic, copy) NSDictionary *art;
@property (nonatomic, copy) NSString *fallbackSymbol;
- (void)useArt:(NSDictionary *)art;
- (void)playTap;
@end

@implementation QGlyphButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _iconSize = 24;
        // 18pt visible height at the default player size (iconSize 24), matching Vela's controls.
        _glyphBox = CGSizeMake(1.25, 0.75);
        _glyphView = [UIImageView new];
        _glyphView.userInteractionEnabled = NO;
        [self addSubview:_glyphView];
    }
    return self;
}

- (BOOL)qAnimates {
    return !UIAccessibilityIsReduceMotionEnabled() && self.window && !self.window.hidden;
}

- (void)useArt:(NSDictionary *)art {
    NSString *package = self.visuallyHidden ? nil : art[@"package"];
    if (package) {
        BOOL native = [art[@"native"] boolValue];
        if (!self.animationHost || ![self.animationHost.path isEqualToString:package]) {
            [self.animationHost stop];
            [self.animationHost removeFromSuperview];
            PCAIconHost *host = [PCAIconHost new];
            host.userInteractionEnabled = NO;
            // Same host setup Vela uses for its media keys.
            host.nativeSystem = native;
            host.templateForeground = !native;
            host.mirrorsHorizontally = [art[@"mirror"] boolValue];
            host.tintColor = self.tintColor;
            [self addSubview:host];
            self.animationHost = host;
            if (![host loadPath:package]) package = nil;
        }
        if (package && ![self.animationHost applyStates:art[@"states"] animated:[self qAnimates] && self.art != nil])
            package = nil;
    }
    if (!package) {
        [self.animationHost stop];
        [self.animationHost removeFromSuperview];
        self.animationHost = nil;
    }
    // A package that fails to load falls back to the SF Symbol Vela would show.
    UIImage *image = self.visuallyHidden || package ? nil :
        QArtImage(art[@"package"] ? @{@"symbol": self.fallbackSymbol ?: @"play.fill"} : art);
    self.glyphView.image = image;
    self.glyphView.hidden = !image;
    self.art = art;
    [self setNeedsLayout];
}

- (void)playTap {
    if ([self qAnimates]) [self.animationHost playTap];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self.animationHost resume];
    else [self.animationHost pause];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    self.animationHost.tintColor = self.tintColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = self.iconSize > 0 ? self.iconSize : 24;
    CGSize box = CGSizeMake(size * self.glyphBox.width, size * self.glyphBox.height);
    CGRect boxRect = CGRectMake((CGRectGetWidth(self.bounds) - box.width) / 2,
                                (CGRectGetHeight(self.bounds) - box.height) / 2, box.width, box.height);
    self.animationHost.frame = boxRect;
    CGSize image = self.glyphView.image.size;
    CGFloat scale = image.width > 0 && image.height > 0 ? MIN(box.width / image.width, box.height / image.height) : 0;
    CGSize fitted = CGSizeMake(image.width * scale, image.height * scale);
    self.glyphView.frame = CGRectMake(CGRectGetMidX(boxRect) - fitted.width / 2, CGRectGetMidY(boxRect) - fitted.height / 2,
                                      fitted.width, fitted.height);
}

@end

@interface QPlayerView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, assign) BOOL expandedArtwork;
@property (nonatomic, strong) CAShapeLayer *artworkProgressTrack;
@property (nonatomic, strong) CAShapeLayer *artworkProgressRing;
@property (nonatomic, strong) UIView *artworkSeekArea;
@property (nonatomic, strong) UIPanGestureRecognizer *progressPan;
@property (nonatomic, strong) QMarqueeLabel *titleLabel;
@property (nonatomic, strong) QMarqueeLabel *artistLabel;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UIView *backgroundProgress;
@property (nonatomic, strong) UIView *backgroundSeekArea;
@property (nonatomic, strong) QGlyphButton *previousButton;
@property (nonatomic, strong) QGlyphButton *playButton;
@property (nonatomic, strong) QGlyphButton *nextButton;
@property (nonatomic, strong) AVRoutePickerView *routeView;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) CADisplayLink *progressDisplayLink;
@property (nonatomic) BOOL refreshSuspended;
@property (nonatomic) CGSize appliedSettingsSize;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSTimeInterval elapsed;
@property (nonatomic) NSTimeInterval progressAnchorElapsed;
@property (nonatomic) CFTimeInterval progressAnchorTime;
@property (nonatomic) CFTimeInterval lastMediaRemoteProgressTime;
@property (nonatomic) BOOL playing;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic, copy) NSDictionary *settings;
@property (nonatomic, strong) UIColor *artworkAccent;
@property (nonatomic, copy) NSData *artworkData;
@property (nonatomic) BOOL hasValidNativeMetadata;
@property (nonatomic, weak) UISlider *nativeSlider;
@property (nonatomic, weak) id nativeTimeControls;
@property (nonatomic, copy) NSString *trackIdentity;
@property (nonatomic) BOOL suppressSiblingViews;
@property (nonatomic) BOOL usesNativeMetadataFallback;
@property (nonatomic) NSTimeInterval seekHoldUntil;
@property (nonatomic) NSTimeInterval seekTarget;
@property (nonatomic) NSTimeInterval lastMetadataTime;
@property (nonatomic) NSTimeInterval lastReportedDuration;
@property (nonatomic) CGFloat dragStartProgress;
@property (nonatomic) CGFloat dragStartX;
- (CGFloat)sizeFactor;
- (CGFloat)artworkSide;
- (void)updateScaledFonts;
- (BOOL)qRefreshVisible;
- (void)qUpdateRefreshLifecycle;
@end

@implementation QPlayerView

- (BOOL)containsArtworkAtPoint:(CGPoint)point {
    return !self.hidden && !self.expandedArtwork && self.artwork.image &&
        CGRectContainsPoint(CGRectInset(self.artwork.frame, 4, 4), point);
}

- (void)setExpandedArtwork:(BOOL)expanded {
    if (_expandedArtwork == expanded) return;
    _expandedArtwork = expanded;
    [self updateAccent];
    self.artwork.hidden = expanded;
    self.artworkProgressTrack.hidden = expanded ||
        !([self.settings[@"showProgress"] boolValue] && [self.settings[@"progressStyle"] integerValue] == 2);
    self.artworkProgressRing.hidden = self.artworkProgressTrack.hidden;
    self.artworkSeekArea.hidden = expanded || self.artworkProgressTrack.hidden;
    self.backgroundSeekArea.hidden = expanded ||
        !([self.settings[@"showProgress"] boolValue] && [self.settings[@"progressStyle"] integerValue] == 0);
    [self setNeedsLayout];
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self layoutIfNeeded]; } completion:nil];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return [super hitTest:point withEvent:event];
}

- (void)setHidden:(BOOL)hidden {
    if (self.hidden == hidden) return;
    [super setHidden:hidden];
    [self qUpdateRefreshLifecycle];
    if (!self.suppressSiblingViews) return;
    UIView *host = self.superview;
    if (!host) return;
    for (UIView *sibling in host.subviews) {
        if (sibling != self) sibling.alpha = hidden ? 1 : 0;
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.93 alpha:0.94];
        self.layer.borderWidth = 0;
        self.clipsToBounds = YES;
        self.hidden = NO;
        self.suppressSiblingViews = YES;
        self.usesNativeMetadataFallback = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nowPlayingChanged:)
            name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(qSuspendRefresh:)
            name:UISceneDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(qResumeRefresh:)
            name:UISceneWillEnterForegroundNotification object:nil];

        _backgroundProgress = [UIView new];
        _backgroundProgress.userInteractionEnabled = NO;
        [self addSubview:_backgroundProgress];
        _backgroundSeekArea = [UIView new];
        _backgroundSeekArea.backgroundColor = UIColor.clearColor;
        [_backgroundSeekArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(seekTapped:)]];
        [self addSubview:_backgroundSeekArea];

        _artwork = [UIImageView new];
        _artwork.contentMode = UIViewContentModeScaleAspectFill;
        _artwork.clipsToBounds = YES;
        _artwork.backgroundColor = [UIColor colorWithWhite:0.78 alpha:1];
        _artwork.userInteractionEnabled = YES;
        [_artwork addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkTapped:)]];
        [self addSubview:_artwork];

        _artworkProgressTrack = [CAShapeLayer layer];
        _artworkProgressRing = [CAShapeLayer layer];
        for (CAShapeLayer *ring in @[_artworkProgressTrack, _artworkProgressRing]) {
            ring.fillColor = UIColor.clearColor.CGColor;
            ring.lineWidth = 2.5;
            ring.lineCap = kCALineCapRound;
            [self.layer addSublayer:ring];
        }
        _artworkSeekArea = [UIView new];
        _artworkSeekArea.backgroundColor = UIColor.clearColor;
        _artworkSeekArea.hidden = YES;
        [_artworkSeekArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkSeekTapped:)]];
        [self addSubview:_artworkSeekArea];

        _progressPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekPanned:)];
        _progressPan.delegate = self;
        [self addGestureRecognizer:_progressPan];

        _titleLabel = [QMarqueeLabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
        _titleLabel.text = @"";
        _titleLabel.userInteractionEnabled = YES;
        [_titleLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayingApp:)]];
        [self addSubview:_titleLabel];

        _artistLabel = [QMarqueeLabel new];
        _artistLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _artistLabel.textColor = [UIColor colorWithWhite:0.36 alpha:1];
        [self addSubview:_artistLabel];

        _progress = [UISlider new];
        _progress.minimumTrackTintColor = [UIColor colorWithRed:0.18 green:0.45 blue:0.76 alpha:1];
        _progress.maximumTrackTintColor = [UIColor colorWithWhite:0.62 alpha:0.6];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
        UIImage *clearThumb = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [_progress setThumbImage:clearThumb forState:UIControlStateNormal];
        [_progress setThumbImage:clearThumb forState:UIControlStateHighlighted];
        UITapGestureRecognizer *seekTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(seekTapped:)];
        [_progress addGestureRecognizer:seekTap];
        UIPanGestureRecognizer *seekPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekPanned:)];
        seekPan.delegate = self;
        [_progress addGestureRecognizer:seekPan];
        [self addSubview:_progress];

        _elapsedLabel = [UILabel new];
        _remainingLabel = [UILabel new];
        for (UILabel *label in @[_elapsedLabel, _remainingLabel]) {
            label.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
            label.textColor = [UIColor colorWithWhite:0.40 alpha:1];
            [self addSubview:label];
        }
        _remainingLabel.textAlignment = NSTextAlignmentRight;

        _previousButton = [self button:@"play" action:@selector(previous:)];
        _previousButton.accessibilityIdentifier = @"Quart17.Previous";
        _playButton = [self button:@"square" action:@selector(toggle:)];
        _playButton.iconSize = 36;
        _playButton.accessibilityIdentifier = @"Quart17.PlayPause";
        _nextButton = [self button:@"play" action:@selector(next:)];
        _nextButton.accessibilityIdentifier = @"Quart17.Next";

        _routeView = [[AVRoutePickerView alloc] initWithFrame:CGRectZero];
        _routeView.tintColor = [UIColor colorWithWhite:0.22 alpha:1];
        _routeView.activeTintColor = [UIColor colorWithWhite:0.22 alpha:1];
        [self addSubview:_routeView];
    }
    return self;
}

- (QGlyphButton *)button:(NSString *)symbol action:(SEL)action {
    QGlyphButton *button = [[QGlyphButton alloc] initWithFrame:CGRectZero];
    button.tintColor = [UIColor colorWithWhite:0.22 alpha:1];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];
    return button;
}

- (void)updateControlImages {
    BOOL hideControls = [self.settings[@"hideControls"] boolValue];
    self.previousButton.visuallyHidden = hideControls;
    self.playButton.visuallyHidden = hideControls;
    self.nextButton.visuallyHidden = hideControls;
    self.playButton.glyphBox = CGSizeMake(0.6, 0.5);   // 18pt of iconSize 36
    NSString *theme = self.settings[@"velaThemeFolder"];
    BOOL custom = [self.settings[@"customControlIcons"] boolValue];
    self.previousButton.fallbackSymbol = @"backward.fill";
    self.nextButton.fallbackSymbol = @"forward.fill";
    self.playButton.fallbackSymbol = self.playing ? @"pause.fill" : @"play.fill";
    [self.previousButton useArt:QControlArt(theme, @"media.previous", @"default", @"previous", @"backward.fill", custom)];
    [self.nextButton useArt:QControlArt(theme, @"media.next", @"default", @"next", @"forward.fill", custom)];
    // Vela's media.play states: "playing" shows the pause glyph, "paused" the play glyph.
    [self.playButton useArt:QControlArt(theme, @"media.play", self.playing ? @"playing" : @"paused",
                                        self.playing ? @"pause" : @"play", self.playing ? @"pause.fill" : @"play.fill",
                                        custom)];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    self.refreshSuspended = self.window.windowScene.activationState == UISceneActivationStateBackground;
    [self updateAccent];
    [self qUpdateRefreshLifecycle];
    [self refresh];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.timer invalidate];
    [self.progressDisplayLink invalidate];
}

- (BOOL)qRefreshVisible {
    if (!self.window || self.refreshSuspended || CGRectIsEmpty(self.bounds)) return NO;
    for (UIView *view = self; view; view = view.superview)
        if (view.hidden || view.alpha < 0.01) return NO;
    return CGRectIntersectsRect([self convertRect:self.bounds toView:self.window], self.window.bounds);
}

- (void)qSuspendRefresh:(NSNotification *)notification {
    if (notification.object != self.window.windowScene) return;
    self.refreshSuspended = YES;
    [self qUpdateRefreshLifecycle];
}

- (void)qResumeRefresh:(NSNotification *)notification {
    if (notification.object != self.window.windowScene) return;
    self.refreshSuspended = NO;
    [self qUpdateRefreshLifecycle];
    [self refresh];
}

- (void)qUpdateRefreshLifecycle {
    BOOL attached = self.window && !self.hidden && !self.refreshSuspended;
    if (!attached) {
        [self.timer invalidate];
        self.timer = nil;
    } else if (!self.timer) {
        __weak typeof(self) weakSelf = self;
        // shortcut: Probe hidden ancestors once per second; use host callbacks if faster resume is needed.
        self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            QPlayerView *player = weakSelf;
            if (!player) { [timer invalidate]; return; }
            [player qUpdateRefreshLifecycle];
            [player refresh];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        [self refresh];
    }
    BOOL animateProgress = [self qRefreshVisible] && self.playing && self.duration > 0 &&
        [self.settings[@"showProgress"] boolValue];
    if (!animateProgress) {
        [self.progressDisplayLink invalidate];
        self.progressDisplayLink = nil;
    } else if (!self.progressDisplayLink) {
        self.progressDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateVisualProgress)];
        self.progressDisplayLink.preferredFramesPerSecond = 30;
        [self.progressDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        [self updateAccent];
    }
}

- (void)updateVisualProgress {
    if (![self qRefreshVisible]) { [self qUpdateRefreshLifecycle]; return; }
    if (self.scrubbing || self.duration <= 0 || ![self.settings[@"showProgress"] boolValue]) return;
    CFTimeInterval now = CACurrentMediaTime();
    NSTimeInterval elapsed = self.progressAnchorElapsed + (self.playing ? MAX(0, now - self.progressAnchorTime) : 0);
    self.elapsed = MIN(self.duration, MAX(0, elapsed));
    self.progress.value = self.elapsed / self.duration;
    [self updateProgressFill];
}

- (void)nowPlayingChanged:(NSNotification *)notification {
    [self refresh];
}

// 尺寸系数：本视图按基准设计高度 88pt 设计。外层用 transform 缩放时，
// 传入的 bounds 已是"缩放后"的尺寸，所以这里算出的系数同时包含两层缩放，
// 内部（封面/按钮/进度条/边距/字号）据此一起缩。
- (CGFloat)sizeFactor {
    CGFloat h = self.bounds.size.height;
    if (h <= 0 || !isfinite(h)) return 1.0;
    return h / (CGFloat)kQPlayerDesignHeight;
}

// 按设计高度 88pt 推出的封边尺寸
static const CGFloat kQPlayerDesignHeight = 88.0;
static const CGFloat kQPlayerArtworkDesign = 60.0;

- (CGFloat)artworkSide {
    CGFloat art = kQPlayerArtworkDesign * [self sizeFactor];
    return MIN(MAX(art, 34.0), 60.0);
}

- (void)applySettings:(NSDictionary *)settings {
    if ([self.settings isEqualToDictionary:settings] && CGSizeEqualToSize(self.appliedSettingsSize, self.bounds.size)) {
        [self qUpdateRefreshLifecycle];
        return;
    }
    self.settings = settings;
    self.appliedSettingsSize = self.bounds.size;
    NSInteger progressStyle = [settings[@"progressStyle"] integerValue];
    if (progressStyle < 0 || progressStyle > 2) progressStyle = 0;
    CGFloat roundness = settings[@"playerCornerRoundness"] ? [settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    CGFloat radius = self.bounds.size.height * roundness / 2;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = QCornerCurveForRoundness(roundness);
    self.artwork.layer.cornerRadius = [self artworkSide] * roundness / 2;
    self.artwork.layer.cornerCurve = QCornerCurveForRoundness(roundness);
    BOOL showProgress = [settings[@"showProgress"] boolValue];
    self.progress.hidden = !showProgress || progressStyle != 1;
    self.backgroundProgress.hidden = !showProgress || progressStyle != 0;
    self.backgroundSeekArea.hidden = self.expandedArtwork || !showProgress || progressStyle != 0;
    BOOL showArtworkRing = showProgress && progressStyle == 2;
    self.artwork.hidden = self.expandedArtwork;
    self.artworkProgressTrack.hidden = !showArtworkRing || self.expandedArtwork;
    self.artworkProgressRing.hidden = !showArtworkRing || self.expandedArtwork;
    self.artworkSeekArea.hidden = self.expandedArtwork || !showArtworkRing;
    self.elapsedLabel.hidden = !showProgress;
    self.remainingLabel.hidden = !showProgress;
    self.routeView.hidden = [settings[@"hideRoute"] boolValue];
    self.layer.borderWidth = QPlayerBorderWidth(settings);
    [self updateControlImages];
    [self updateAccent];
    [self updateScaledFonts];   // 字号只在这里更新（布局之外），避免布局递归
    [self qUpdateRefreshLifecycle];
    [self setNeedsLayout];
}

static UIColor *QAccentFromImage(UIImage *image) {
    if (!image.CGImage) return nil;
    unsigned char pixels[24 * 24 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 24, 24, 8, 24 * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, 24, 24), image.CGImage);
    CGContextRelease(context);
    double r = 0, g = 0, b = 0, total = 0;
    for (int i = 0; i < 24 * 24; i++) {
        double alpha = pixels[i * 4 + 3] / 255.0;
        if (alpha < 0.3) continue;
        double pr = pixels[i * 4] / 255.0, pg = pixels[i * 4 + 1] / 255.0, pb = pixels[i * 4 + 2] / 255.0;
        double maxv = MAX(pr, MAX(pg, pb)), minv = MIN(pr, MIN(pg, pb));
        double saturation = maxv - minv;
        double weight = alpha * (0.25 + saturation * 1.5);
        r += pr * weight; g += pg * weight; b += pb * weight; total += weight;
    }
    if (total <= 0) return nil;
    r /= total; g /= total; b /= total;
    double luminance = r * 0.2126 + g * 0.7152 + b * 0.0722;
    if (luminance > 0.55) { r *= 0.42; g *= 0.42; b *= 0.42; }
    else if (luminance < 0.17) { r = r * 0.65 + 0.10; g = g * 0.65 + 0.10; b = b * 0.65 + 0.10; }
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

- (void)updateAccent {
    UIColor *accent = QAccentFromImage(self.artwork.image) ?: [UIColor colorWithRed:0.18 green:0.45 blue:0.76 alpha:1];
    self.artworkAccent = accent;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [accent getRed:&r green:&g blue:&b alpha:&a];
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    CGFloat textMix = 0.48;
    UIColor *textAccent = dark ? [UIColor colorWithRed:MIN(1, r * (1 - textMix) + textMix)
                                                  green:MIN(1, g * (1 - textMix) + textMix)
                                                   blue:MIN(1, b * (1 - textMix) + textMix) alpha:1] : accent;
    UIColor *baseProgress = [self.settings[@"progressFromArtwork"] boolValue]
        ? accent : [UIColor colorWithRed:0.18 green:0.45 blue:0.76 alpha:1];
    CGFloat pr = 0, pg = 0, pb = 0, pa = 0;
    [baseProgress getRed:&pr green:&pg blue:&pb alpha:&pa];
    UIColor *progressColor = dark ? [UIColor colorWithRed:pr * 0.55 + 0.45
                                                    green:pg * 0.55 + 0.45
                                                     blue:pb * 0.55 + 0.45 alpha:1] : baseProgress;
    self.backgroundColor = [self.settings[@"backgroundFromArtwork"] boolValue]
        ? (dark ? [UIColor colorWithRed:r * 0.55 + 0.04 green:g * 0.55 + 0.04 blue:b * 0.55 + 0.04 alpha:0.97]
                : [UIColor colorWithRed:r * 0.38 + 0.60 green:g * 0.38 + 0.60 blue:b * 0.38 + 0.60 alpha:0.97])
        : [UIColor colorWithWhite:dark ? 0.14 : 0.93 alpha:0.96];
    self.titleLabel.textColor = [self.settings[@"titleFromArtwork"] boolValue]
        ? textAccent : [UIColor colorWithWhite:dark ? 0.96 : 0.15 alpha:1];
    self.artistLabel.textColor = [self.settings[@"artistFromArtwork"] boolValue]
        ? [textAccent colorWithAlphaComponent:0.78]
        : [UIColor colorWithWhite:dark ? 0.76 : 0.36 alpha:1];
    self.progress.minimumTrackTintColor = progressColor;
    self.progress.maximumTrackTintColor = [UIColor colorWithWhite:dark ? 0.85 : 0.62 alpha:dark ? 0.3 : 0.6];
    self.backgroundProgress.backgroundColor = [progressColor colorWithAlphaComponent:dark ? 0.36 : 0.18];
    UIColor *ringColor = progressColor;
    self.artworkProgressTrack.strokeColor = [ringColor colorWithAlphaComponent:0.25].CGColor;
    self.artworkProgressRing.strokeColor = ringColor.CGColor;
    self.previousButton.tintColor = textAccent;
    self.playButton.tintColor = textAccent;
    self.nextButton.tintColor = textAccent;
    // The border always uses the text colour picked from the artwork.
    self.layer.borderColor = textAccent.CGColor;
}

static CGFloat QPlayerBorderWidth(NSDictionary *settings) {
    if (![settings[@"playerBorderEnabled"] boolValue] || [settings[@"auraPlayerGlass"] boolValue]) return 0;
    CGFloat width = [settings[@"playerBorderWidth"] doubleValue];
    return isfinite(width) ? MIN(4, MAX(0.5, width)) : 1.5;
}


static NSString *QTime(NSTimeInterval value) {
    NSInteger seconds = MAX(0, (NSInteger)round(value));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

static NSString *QPlayingPlaceholder(void) {
    return [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"] ? @"正在播放" : @"Now Playing";
}

static BOOL QIsPlaybackPlaceholder(NSString *text) {
    return [@[@"正在播放", @"未在播放", @"Now Playing", @"Not Playing"] containsObject:text ?: @""];
}

static NSTimeInterval QParseTime(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return -1;
    NSString *clean = [[text stringByReplacingOccurrencesOfString:@"−" withString:@""]
                             stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSArray<NSString *> *parts = [clean componentsSeparatedByString:@":"];
    if (parts.count < 2 || parts.count > 3) return -1;
    NSTimeInterval seconds = 0;
    for (NSString *part in parts) {
        NSScanner *scanner = [NSScanner scannerWithString:part];
        NSInteger value = 0;
        if (![scanner scanInteger:&value] || !scanner.isAtEnd || value < 0) return -1;
        seconds = seconds * 60 + value;
    }
    return seconds;
}

- (void)refresh {
    if (![self qRefreshVisible]) return;
    if (self.usesNativeMetadataFallback && self.superview) [self seedFromNativePlayer:self.superview];
    if (!QLoadMediaRemote()) return;
    __weak typeof(self) weakSelf = self;
    QGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef result) {
        QPlayerView *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf qRefreshVisible]) return;
        NSDictionary *info = (__bridge NSDictionary *)result;
        NSString *title = info[QKey(QTitleKey, @"kMRMediaRemoteNowPlayingInfoTitle")];
        if (![title isKindOfClass:NSString.class] || title.length == 0) {
            if (!strongSelf.hasValidNativeMetadata &&
                CFAbsoluteTimeGetCurrent() - strongSelf.lastMetadataTime > 5) {
                strongSelf.titleLabel.text = strongSelf.playing ? QPlayingPlaceholder() : @"";
                strongSelf.artistLabel.text = @"";
                strongSelf.artwork.image = nil;
                strongSelf.artworkData = nil;
                strongSelf.duration = 0;
                strongSelf.progress.value = 0;
                strongSelf.progressAnchorElapsed = 0;
                [strongSelf updateProgressFill];
                [strongSelf updateAccent];
            }
            return;
        }
        strongSelf.lastMetadataTime = CFAbsoluteTimeGetCurrent();
        NSString *artist = info[QKey(QArtistKey, @"kMRMediaRemoteNowPlayingInfoArtist")];
        id uniqueID = info[QKey(QUniqueKey, @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier")];
        NSString *identity = uniqueID ? [uniqueID description] : nil;
        if (identity.length && strongSelf.trackIdentity.length &&
            ![identity isEqualToString:strongSelf.trackIdentity]) {
            strongSelf.trackIdentity = identity;
            strongSelf.duration = 0;
            strongSelf.elapsed = 0;
            strongSelf.progress.value = 0;
            strongSelf.progressAnchorElapsed = 0;
            strongSelf.progressAnchorTime = CACurrentMediaTime();
            strongSelf.seekHoldUntil = 0;
            [strongSelf updateProgressFill];
        }
        if (identity.length) strongSelf.trackIdentity = identity;
        strongSelf.titleLabel.text = title;
        strongSelf.artistLabel.text = [artist isKindOfClass:NSString.class] ? artist : @"";
        NSData *data = info[QKey(QArtworkKey, @"kMRMediaRemoteNowPlayingInfoArtworkData")];
        if ([data isKindOfClass:NSData.class] && ![data isEqualToData:strongSelf.artworkData]) {
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                strongSelf.artworkData = data;
                strongSelf.artwork.image = image;
                [strongSelf updateAccent];
                [strongSelf.artwork setNeedsDisplay];
            }
        }
        NSTimeInterval reportedDuration = [info[QKey(QDurationKey, @"kMRMediaRemoteNowPlayingInfoDuration")] doubleValue];
        if (isfinite(reportedDuration) && reportedDuration > 0) {
            // 切歌检测（不依赖 uniqueIdentifier）：时长突变超过 2s 且 5% 即视为新歌，进度归零
            if (strongSelf.lastReportedDuration > 0 &&
                fabs(reportedDuration - strongSelf.lastReportedDuration) > MAX(2, strongSelf.lastReportedDuration * 0.05)) {
                strongSelf.trackIdentity = @"";
                strongSelf.duration = 0;
                strongSelf.elapsed = 0;
                strongSelf.progress.value = 0;
                strongSelf.progressAnchorElapsed = 0;
                strongSelf.progressAnchorTime = CACurrentMediaTime();
                strongSelf.seekHoldUntil = 0;
                [strongSelf updateProgressFill];
            }
            strongSelf.lastReportedDuration = reportedDuration;
            strongSelf.duration = reportedDuration;
        }
        NSTimeInterval elapsed = [info[QKey(QElapsedKey, @"kMRMediaRemoteNowPlayingInfoElapsedTime")] doubleValue];
        NSTimeInterval timestamp = QMetadataTimestamp(info[QKey(QTimestampKey, @"kMRMediaRemoteNowPlayingInfoTimestamp")]);
        double rate = [info[QKey(QRateKey, @"kMRMediaRemoteNowPlayingInfoPlaybackRate")] doubleValue];
        NSTimeInterval age = [NSDate date].timeIntervalSince1970 - timestamp;
        if (timestamp > 0 && rate > 0 && age >= 0 && age < 10) elapsed += age * rate;
        if (strongSelf.duration > 0 && isfinite(elapsed)) {
            NSTimeInterval reported = MIN(MAX(0, elapsed), strongSelf.duration);
            strongSelf.lastMediaRemoteProgressTime = CACurrentMediaTime();
            if (fabs(reported - strongSelf.seekTarget) < 2) strongSelf.seekHoldUntil = 0;
            if (!strongSelf.scrubbing && CFAbsoluteTimeGetCurrent() >= strongSelf.seekHoldUntil) {
                CFTimeInterval now = CACurrentMediaTime();
                NSTimeInterval predicted = strongSelf.progressAnchorElapsed +
                    (strongSelf.playing ? MAX(0, now - strongSelf.progressAnchorTime) : 0);
                // 单向校正：MediaRemote 报告常滞后于本地实时推进，只允许向前修正，
                // 忽略滞后的旧报告，杜绝进度回退抖动（含 seek 后回退）。
                // 兜底：进度大幅回退到起始位置（<5s）视为切歌，允许归零重置。
                // 暂停时仅在差异明显（>2s）时校正，容忍暂停瞬间 rate/timestamp 未更新导致的短暂抖动
                BOOL rewoundToStart = reported < predicted - 8 && reported < 5;
                BOOL pausedCorrection = !strongSelf.playing && fabs(reported - predicted) > 2.0;
                if (strongSelf.progressAnchorTime == 0 || reported > predicted + 0.8 ||
                    rewoundToStart || pausedCorrection) {
                    strongSelf.progressAnchorElapsed = reported;
                    strongSelf.progressAnchorTime = now;
                }
                [strongSelf updateVisualProgress];
            }
        }
        strongSelf.elapsedLabel.text = QTime(strongSelf.elapsed);
        strongSelf.remainingLabel.text = [@"−" stringByAppendingString:QTime(MAX(0, strongSelf.duration - strongSelf.elapsed))];
        [strongSelf qUpdateRefreshLifecycle];
    });
    if (QGetPlaying) QGetPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
        QPlayerView *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf qRefreshVisible]) return;
        BOOL changed = strongSelf.playing != isPlaying;
        if (strongSelf.playing != isPlaying) {
            CFTimeInterval now = CACurrentMediaTime();
            strongSelf.progressAnchorElapsed = strongSelf.elapsed;
            strongSelf.progressAnchorTime = now;
        }
        strongSelf.playing = isPlaying;
        if (QIsPlaybackPlaceholder(strongSelf.titleLabel.text) || strongSelf.titleLabel.text.length == 0) {
            strongSelf.titleLabel.text = isPlaying ? QPlayingPlaceholder() : @"";
        }
        if (changed) [strongSelf updateControlImages];
        [strongSelf qUpdateRefreshLifecycle];
    });
}

static NSString *QTextInView(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:UILabel.class] && ((UILabel *)root).text.length) return ((UILabel *)root).text;
    if ([root respondsToSelector:@selector(text)]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(root, @selector(text));
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    for (UIView *child in root.subviews) {
        NSString *value = QTextInView(child);
        if (value.length) return value;
    }
    return nil;
}

- (void)seedFromNativePlayer:(UIView *)player {
    if (!player) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:player];
    UIView *labelHost = nil;
    UIView *artHost = nil;
    UIView *timeHost = nil;
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        if (view == self) continue;
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqualToString:@"MRUNowPlayingLabelView"]) labelHost = view;
        if ([name containsString:@"Artwork"] && view.bounds.size.width > 40) artHost = view;
        if ([name isEqualToString:@"MRUNowPlayingTimeControlsView"]) timeHost = view;
        [queue addObjectsFromArray:view.subviews];
    }
    NSString *title = nil, *artist = nil;
    if (labelHost && [labelHost respondsToSelector:@selector(titleMarqueeView)]) {
        UIView *titleView = ((id (*)(id, SEL))objc_msgSend)(labelHost, @selector(titleMarqueeView));
        title = QTextInView(titleView);
    }
    if (labelHost && [labelHost respondsToSelector:@selector(subtitleMarqueeView)]) {
        UIView *artistView = ((id (*)(id, SEL))objc_msgSend)(labelHost, @selector(subtitleMarqueeView));
        artist = QTextInView(artistView);
    }
    UIImage *nativeArtwork = nil;
    if (artHost) {
        if ([artHost respondsToSelector:@selector(artworkImage)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(artHost, @selector(artworkImage));
            if ([value isKindOfClass:UIImage.class]) nativeArtwork = value;
        }
        NSMutableArray<UIView *> *images = [NSMutableArray arrayWithObject:artHost];
        while (!nativeArtwork && images.count) {
            UIView *view = images.lastObject;
            [images removeLastObject];
            if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) {
                nativeArtwork = ((UIImageView *)view).image;
                break;
            }
            [images addObjectsFromArray:view.subviews];
        }
    }
    if (timeHost) {
        if ([timeHost respondsToSelector:@selector(timeControls)]) {
            id controls = ((id (*)(id, SEL))objc_msgSend)(timeHost, @selector(timeControls));
            self.nativeTimeControls = [controls respondsToSelector:@selector(setElapsedTime:)] ? controls : nil;
        }
        if ([timeHost respondsToSelector:@selector(slider)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(timeHost, @selector(slider));
            if ([value isKindOfClass:UISlider.class]) self.nativeSlider = value;
        }
        UILabel *elapsedLabel = nil, *remainingLabel = nil;
        if ([timeHost respondsToSelector:@selector(elapsedTimeLabel)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(timeHost, @selector(elapsedTimeLabel));
            if ([value isKindOfClass:UILabel.class]) elapsedLabel = value;
        }
        if ([timeHost respondsToSelector:@selector(remainingTimeLabel)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(timeHost, @selector(remainingTimeLabel));
            if ([value isKindOfClass:UILabel.class]) remainingLabel = value;
        }
        NSTimeInterval elapsed = QParseTime(elapsedLabel.text);
        NSTimeInterval remaining = QParseTime(remainingLabel.text);
        if (elapsed < 0 || remaining < 0) {
            NSMutableArray<UILabel *> *timeLabels = [NSMutableArray array];
            NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:timeHost];
            while (pending.count) {
                UIView *candidate = pending.lastObject;
                [pending removeLastObject];
                if ([candidate isKindOfClass:UILabel.class] && QParseTime(((UILabel *)candidate).text) >= 0) [timeLabels addObject:(UILabel *)candidate];
                [pending addObjectsFromArray:candidate.subviews];
            }
            [timeLabels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
                CGFloat xA = [a convertPoint:CGPointZero toView:timeHost].x;
                CGFloat xB = [b convertPoint:CGPointZero toView:timeHost].x;
                return xA < xB ? NSOrderedAscending : (xA > xB ? NSOrderedDescending : NSOrderedSame);
            }];
            if (timeLabels.count >= 2) {
                elapsed = QParseTime(timeLabels.firstObject.text);
                remaining = QParseTime(timeLabels.lastObject.text);
            }
        }
        if (elapsed >= 0 && remaining >= 0 && elapsed + remaining > 0 &&
            CACurrentMediaTime() - self.lastMediaRemoteProgressTime > 3) {
            self.duration = elapsed + remaining;
            if (!self.scrubbing && CFAbsoluteTimeGetCurrent() >= self.seekHoldUntil) {
                CFTimeInterval now = CACurrentMediaTime();
                NSTimeInterval predicted = self.progressAnchorElapsed +
                    (self.playing ? MAX(0, now - self.progressAnchorTime) : 0);
                // 与 MediaRemote 路径一致的单向校正，防止原生兜底时间回退进度；
                // 进度大幅回退到起始位置视为切歌，允许归零重置；
                // 暂停时仅在差异明显（>2s）时校正，容忍暂停瞬间报告抖动
                BOOL rewoundToStart = elapsed < predicted - 8 && elapsed < 5;
                BOOL pausedCorrection = !self.playing && fabs(elapsed - predicted) > 2.0;
                if (self.progressAnchorTime == 0 || elapsed > predicted + 0.8 ||
                    rewoundToStart || pausedCorrection) {
                    self.progressAnchorElapsed = elapsed;
                    self.progressAnchorTime = now;
                }
                [self updateVisualProgress];
            }
            [self updateProgressFill];
        } else if (self.nativeSlider && !self.scrubbing && self.duration <= 0) {
            CGFloat span = self.nativeSlider.maximumValue - self.nativeSlider.minimumValue;
            if (span > 0 && span <= 1.01 && self.nativeSlider.value < self.nativeSlider.maximumValue) {
                self.progress.value = (self.nativeSlider.value - self.nativeSlider.minimumValue) / span;
                [self updateProgressFill];
            }
        }
    }
    self.hasValidNativeMetadata = title.length && (artist.length || nativeArtwork);
    if (self.hasValidNativeMetadata) {
        self.titleLabel.text = title;
        self.artistLabel.text = artist ?: @"";
        if (nativeArtwork && self.artwork.image != nativeArtwork) {
            self.artwork.image = nativeArtwork;
            [self updateAccent];
        }
    }
}

- (void)previous:(id)sender {
    [self.previousButton playTap];
    if (QSendCommand) QSendCommand(5, nil);
    [self refresh];
}
- (void)toggle:(id)sender { if (QSendCommand) QSendCommand(2, nil); [self refresh]; }
- (void)next:(id)sender {
    [self.nextButton playTap];
    if (QSendCommand) QSendCommand(4, nil);
    [self refresh];
}
- (void)openPlayingApp:(id)sender {
    UIView *host = self.superview;
    id controller = host.nextResponder;
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"] &&
        [controller respondsToSelector:@selector(didSelectLabelView:)] &&
        [host respondsToSelector:@selector(headerView)]) {
        id header = ((id (*)(id, SEL))objc_msgSend)(host, @selector(headerView));
        id label = [header respondsToSelector:@selector(labelView)]
            ? ((id (*)(id, SEL))objc_msgSend)(header, @selector(labelView)) : nil;
        if (label) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, @selector(didSelectLabelView:), label);
            return;
        }
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/openplayingapp"), NULL, NULL, YES);
}
- (void)artworkTapped:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/togglenativeartwork"), NULL, NULL, YES);
}
- (void)scrubStarted:(id)sender {
    if (self.scrubbing) return;
    self.scrubbing = YES;
}
- (void)seekTapped:(UITapGestureRecognizer *)gesture {
    if (self.duration <= 0) return;
    [self scrubStarted:gesture];
    UIView *area = gesture.view;
    CGPoint point = [gesture locationInView:area];
    self.progress.value = MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
    [self updateProgressFill];
    [self scrubEnded:self.progress];
}
- (void)seekPanned:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateCancelled) {
        self.scrubbing = NO;
        [self updateVisualProgress];
        if (self.expandedArtwork) QPublishExpandedSeek(self.progress.value, NO);
        return;
    }
    UIView *area = gesture.view;
    if (area == self.progress) {
        // 底部进度条：手指位置即进度（保持原交互）
        CGPoint point = [gesture locationInView:area];
        self.progress.value = MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
        [self updateProgressFill];
        if (gesture.state == UIGestureRecognizerStateBegan) [self scrubStarted:gesture];
        if (gesture.state == UIGestureRecognizerStateEnded) {
            [self scrubEnded:self.progress];
        }
        return;
    }
    // 背景进度：相对拖拽，拖动 0.6 倍播放器宽度走完全程
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self scrubStarted:gesture];
        self.dragStartProgress = MIN(1, MAX(0, self.progress.value));
        self.dragStartX = [gesture translationInView:self].x;
        if (self.expandedArtwork) QPublishExpandedSeek(self.progress.value, YES);
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat span = MAX(1, self.bounds.size.width * 0.6);
        self.progress.value = MIN(1, MAX(0, self.dragStartProgress +
                                         ([gesture translationInView:self].x - self.dragStartX) / span));
        [self updateProgressFill];
        if (self.expandedArtwork) QPublishExpandedSeek(self.progress.value, YES);
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self scrubEnded:self.progress];
    }
}
static CGFloat QArtworkSeekFraction(UIView *area, CGPoint point) {
    return MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
}
- (void)artworkSeekTapped:(UITapGestureRecognizer *)gesture {
    if (self.duration <= 0) return;
    UIView *area = gesture.view;
    CGPoint point = [gesture locationInView:area];
    if (self.expandedArtwork) {
        [self scrubStarted:gesture];
        self.progress.value = QArtworkSeekFraction(area, point);
        [self updateProgressFill];
        [self scrubEnded:self.progress];
        return;
    }
    CGRect artFrame = [self.artwork convertRect:self.artwork.bounds toView:area];
    CGPoint center = CGPointMake(CGRectGetMidX(artFrame), CGRectGetMidY(artFrame));
    CGFloat distance = hypot(point.x - center.x, point.y - center.y);
    if (distance < MIN(artFrame.size.width, artFrame.size.height) / 2 - 6) {
        [self artworkTapped:area];
        return;
    }
    [self scrubStarted:gesture];
    self.progress.value = QArtworkSeekFraction(area, point);
    [self updateProgressFill];
    [self scrubEnded:self.progress];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (self.duration <= 0 ||
        ![self.settings[@"showProgress"] boolValue]) return NO;
    if (gesture == self.progressPan) {
        if (!self.expandedArtwork && [self.settings[@"progressStyle"] integerValue] == 1) return NO;
        UIView *target = [self hitTest:[gesture locationInView:self] withEvent:nil];
        for (UIView *view = target; view && view != self; view = view.superview)
            if ([view isKindOfClass:UIControl.class]) return NO;
    }
    CGPoint translation = [(UIPanGestureRecognizer *)gesture translationInView:self];
    return fabs(translation.x) > fabs(translation.y) * 0.5;
}

- (BOOL)acuis_wantsPriorityOverTargetOfGestureRecognizer:(UIGestureRecognizer *)gesture {
    // Match MRUNowPlayingTimeControlsView's activity-scene touch routing.
    return YES;
}

- (void)scrubEnded:(id)sender {
    self.scrubbing = NO;
    CGFloat fraction = MIN(1, MAX(0, self.progress.value));
    self.seekTarget = self.duration * fraction;
    self.seekHoldUntil = CFAbsoluteTimeGetCurrent() + 2.5;
    id native = self.nativeTimeControls;
    if (native) {
        ((void (*)(id, SEL, double))objc_msgSend)(native, @selector(setElapsedTime:), self.seekTarget);
    } else if (QSetElapsed && self.duration > 0) QSetElapsed(self.seekTarget);
    NSLog(@"[Quart17] seek committed target=%.3f duration=%.3f native=%@", self.seekTarget, self.duration, [native class]);
    self.elapsed = self.duration * fraction;
    self.progressAnchorElapsed = self.elapsed;
    self.progressAnchorTime = CACurrentMediaTime();
    [self updateProgressFill];
    if (self.expandedArtwork) QPublishExpandedSeek(fraction, NO);
    [self refresh];
}

- (void)updateProgressFill {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat fraction = isfinite(self.progress.value) ? MIN(1, MAX(0, self.progress.value)) : 0;
    CGFloat scale = UIScreen.mainScreen.scale;
    CGFloat width = round(self.bounds.size.width * fraction * scale) / scale;
    self.backgroundProgress.frame = CGRectMake(0, 0, width, self.bounds.size.height);
    CGFloat roundness = self.settings[@"playerCornerRoundness"] ? [self.settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    self.backgroundProgress.layer.cornerRadius = MIN(self.bounds.size.height * roundness / 2, width / 2);
    self.artworkProgressRing.strokeEnd = fraction;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat roundness = self.settings[@"playerCornerRoundness"] ? [self.settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    self.layer.cornerRadius = h * roundness / 2;
    self.layer.cornerCurve = QCornerCurveForRoundness(roundness);
    self.backgroundProgress.layer.cornerCurve = QCornerCurveForRoundness(roundness);
    self.backgroundProgress.layer.allowsEdgeAntialiasing = YES;
    [self updateProgressFill];
    self.backgroundSeekArea.frame = self.bounds;
    // 内部度量随 sizeFactor 等比：单元格内部布局跟着缩，配合外层的 transform，
    // 视觉上才是整体缩放而不是"外框缩小、内容不变"。
    CGFloat c = [self sizeFactor];
    CGFloat pad = 12 * c;
    CGFloat art = [self artworkSide];
    NSInteger progressStyle = [self.settings[@"progressStyle"] integerValue];
    BOOL bottomProgress = [self.settings[@"showProgress"] boolValue] && progressStyle == 1;
    CGFloat verticalShift = bottomProgress ? -3 * c : 0;
    CGFloat artY = (h - art) / 2 + verticalShift;
    self.artwork.frame = CGRectMake(pad, artY, art, art);
    self.artwork.layer.cornerRadius = art * roundness / 2;
    self.artwork.layer.cornerCurve = QCornerCurveForRoundness(roundness);
    CGRect ringFrame = CGRectInset(self.artwork.frame, -3 * c, -3 * c);
    self.artworkSeekArea.frame = self.bounds;
    CGFloat ringRectPad = 1.25 * c;
    CGRect ringRect = CGRectInset(CGRectMake(0, 0, ringFrame.size.width, ringFrame.size.height), ringRectPad, ringRectPad);
    CGFloat ringRadius = MIN(ringRect.size.width, ringRect.size.height) * roundness / 2;
    CGPathRef ringPath = QCreateRoundedRingPath(ringRect, ringRadius, roundness);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.artworkProgressTrack.frame = ringFrame;
    self.artworkProgressRing.frame = ringFrame;
    self.artworkProgressTrack.path = ringPath;
    self.artworkProgressRing.path = ringPath;
    [CATransaction commit];
    CGPathRelease(ringPath);
    CGFloat textX = self.expandedArtwork ? pad + 4 * c : pad + art + 12 * c;
    CGFloat controlsWidth = 110 * c;
    CGFloat textW = MAX(50 * c, w - textX - controlsWidth - 12 * c);
    self.titleLabel.frame = CGRectMake(textX, h / 2 - 20 * c + verticalShift, textW, 20 * c);
    self.artistLabel.frame = CGRectMake(textX, h / 2 + 3 * c + verticalShift, textW, 17 * c);

    CGFloat buttonsX = w - controlsWidth - 8 * c;
    CGFloat buttonsY = (h - 34 * c) / 2 + verticalShift;
    self.previousButton.frame = CGRectMake(buttonsX, buttonsY, 33 * c, 36 * c);
    self.playButton.frame = CGRectMake(buttonsX + 35 * c, buttonsY - 3 * c, 40 * c, 40 * c);
    self.nextButton.frame = CGRectMake(buttonsX + 77 * c, buttonsY, 33 * c, 36 * c);
    self.previousButton.iconSize = 24 * c;
    self.playButton.iconSize = 36 * c;
    self.nextButton.iconSize = 24 * c;

    self.progress.frame = CGRectMake(textX, h - 31 * c, MAX(20 * c, w - textX - 17 * c), 30 * c);
    self.elapsedLabel.hidden = YES;
    self.remainingLabel.hidden = YES;
    self.routeView.frame = CGRectMake(w - 39 * c, 4 * c, 26 * c, 26 * c);
}

// 字号不在 layoutSubviews 里设：QMarqueeLabel 的 setFont: 内部会 setNeedsLayout，
// 在布局过程中赋 font 会形成 layout → setFont → setNeedsLayout → layout 的无限递归，
// 每帧新建 UIFont 直到内存触顶（曾导致 SpringBoard EXC_RESOURCE）。
// 改为在布局之外调用，且仅在字号真正变化时才赋值。
- (void)updateScaledFonts {
    CGFloat c = [self sizeFactor];
    CGFloat titleSize = 15 * c, artistSize = 12 * c;
    if (fabs(self.titleLabel.font.pointSize - titleSize) > 0.01)
        self.titleLabel.font = [UIFont systemFontOfSize:titleSize weight:UIFontWeightSemibold];
    if (fabs(self.artistLabel.font.pointSize - artistSize) > 0.01)
        self.artistLabel.font = [UIFont systemFontOfSize:artistSize weight:UIFontWeightMedium];
}

@end
