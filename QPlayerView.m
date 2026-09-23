#import "QPlayerView.h"
#import <AVKit/AVKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <roothide.h>

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

static UIImage *QButtonArtwork(NSString *name, CGFloat size) {
    NSString *directory = jbroot(@"/Library/Application Support/Quart17/Buttons");
    NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [image drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

typedef NS_ENUM(NSInteger, QOutlineKind) {
    QOutlineKindLeft,
    QOutlineKindRight,
    QOutlineKindSquare,
    QOutlineKindCircle
};

@interface QOutlineButton : UIButton
@property (nonatomic) QOutlineKind outlineKind;
@property (nonatomic) BOOL visuallyHidden;
@property (nonatomic) CGFloat iconSize;
@property (nonatomic, strong) CAShapeLayer *outlineLayer;
- (void)useThemeImage:(UIImage *)image;
@end

@implementation QOutlineButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _iconSize = 24;
        _outlineLayer = [CAShapeLayer layer];
        _outlineLayer.fillColor = UIColor.clearColor.CGColor;
        _outlineLayer.lineWidth = 1.65;
        _outlineLayer.lineJoin = kCALineJoinMiter;
        _outlineLayer.lineCap = kCALineCapButt;
        [self.layer addSublayer:_outlineLayer];
    }
    return self;
}

- (void)useThemeImage:(UIImage *)image {
    [self setImage:!self.visuallyHidden && image ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil
          forState:UIControlStateNormal];
    self.outlineLayer.hidden = self.visuallyHidden || image != nil;
    [self setNeedsLayout];
}

- (void)setOutlineKind:(QOutlineKind)outlineKind {
    _outlineKind = outlineKind;
    [self setNeedsLayout];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    self.outlineLayer.strokeColor = self.tintColor.CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = self.iconSize > 0 ? self.iconSize : 24;
    CGRect icon = CGRectMake((CGRectGetWidth(self.bounds) - size) / 2,
                             (CGRectGetHeight(self.bounds) - size) / 2, size, size);
    self.outlineLayer.frame = icon;
    CGFloat c = size / 24.0;
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (self.outlineKind == QOutlineKindCircle) {
        CGFloat inset = 5 * c, side = 14 * c;
        [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(inset, inset, side, side)]];
    } else if (self.outlineKind == QOutlineKindSquare) {
        CGFloat inset = 5 * c, side = 14 * c;
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(inset, inset, side, side)]];
    } else {
        BOOL left = self.outlineKind == QOutlineKindLeft;
        [path moveToPoint:CGPointMake((left ? 18 : 6) * c, 5 * c)];
        [path addLineToPoint:CGPointMake((left ? 6 : 18) * c, 12 * c)];
        [path addLineToPoint:CGPointMake((left ? 18 : 6) * c, 19 * c)];
        [path closePath];
    }
    self.outlineLayer.path = path.CGPath;
    self.outlineLayer.strokeColor = self.tintColor.CGColor;
}

@end

@interface QPlayerView ()
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) CAShapeLayer *artworkProgressTrack;
@property (nonatomic, strong) CAShapeLayer *artworkProgressRing;
@property (nonatomic, strong) UIView *artworkSeekArea;
@property (nonatomic, strong) QMarqueeLabel *titleLabel;
@property (nonatomic, strong) QMarqueeLabel *artistLabel;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UIView *backgroundProgress;
@property (nonatomic, strong) UIView *backgroundSeekArea;
@property (nonatomic, strong) QOutlineButton *previousButton;
@property (nonatomic, strong) QOutlineButton *playButton;
@property (nonatomic, strong) QOutlineButton *nextButton;
@property (nonatomic, strong) AVRoutePickerView *routeView;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) CADisplayLink *progressDisplayLink;
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
@end

@implementation QPlayerView

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
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

        _backgroundProgress = [UIView new];
        _backgroundProgress.userInteractionEnabled = NO;
        [self addSubview:_backgroundProgress];
        _backgroundSeekArea = [UIView new];
        _backgroundSeekArea.backgroundColor = UIColor.clearColor;
        [_backgroundSeekArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(seekTapped:)]];
        [_backgroundSeekArea addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(seekPanned:)]];
        [self addSubview:_backgroundSeekArea];

        _artwork = [UIImageView new];
        _artwork.contentMode = UIViewContentModeScaleAspectFill;
        _artwork.clipsToBounds = YES;
        _artwork.backgroundColor = [UIColor colorWithWhite:0.78 alpha:1];
        _artwork.userInteractionEnabled = YES;
        [_artwork addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayingApp:)]];
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
        [_artworkSeekArea addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(artworkSeekPanned:)]];
        [self addSubview:_artworkSeekArea];

        _titleLabel = [QMarqueeLabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1];
        _titleLabel.text = @"";
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
        [_progress addGestureRecognizer:seekPan];
        [_progress addTarget:self action:@selector(scrubStarted:) forControlEvents:UIControlEventTouchDown];
        [_progress addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
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

- (QOutlineButton *)button:(NSString *)symbol action:(SEL)action {
    QOutlineButton *button = [[QOutlineButton alloc] initWithFrame:CGRectZero];
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
    self.previousButton.outlineKind = QOutlineKindLeft;
    self.nextButton.outlineKind = QOutlineKindRight;
    self.playButton.outlineKind = self.playing ? QOutlineKindSquare : QOutlineKindCircle;
    [self.previousButton useThemeImage:QButtonArtwork(@"previous", 24)];
    [self.nextButton useThemeImage:QButtonArtwork(@"next", 24)];
    [self.playButton useThemeImage:QButtonArtwork(self.playing ? @"pause" : @"play", self.playButton.iconSize)];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateAccent];
    [self.timer invalidate];
    self.timer = nil;
    [self.progressDisplayLink invalidate];
    self.progressDisplayLink = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil];
    if (self.window) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nowPlayingChanged:)
                                                name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil];
        [self refresh];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
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
    self.settings = settings;
    NSInteger progressStyle = [settings[@"progressStyle"] integerValue];
    if (progressStyle < 0 || progressStyle > 2) progressStyle = 0;
    CGFloat roundness = settings[@"playerCornerRoundness"] ? [settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    CGFloat radius = self.bounds.size.height * roundness / 2;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveCircular;
    self.artwork.layer.cornerRadius = [self artworkSide] * roundness / 2;
    self.artwork.layer.cornerCurve = kCACornerCurveCircular;
    BOOL showProgress = [settings[@"showProgress"] boolValue];
    self.progress.hidden = !showProgress || progressStyle != 1;
    self.backgroundProgress.hidden = !showProgress || progressStyle != 0;
    self.backgroundSeekArea.hidden = !showProgress || progressStyle != 0;
    BOOL showArtworkRing = showProgress && progressStyle == 2;
    self.artworkProgressTrack.hidden = !showArtworkRing;
    self.artworkProgressRing.hidden = !showArtworkRing;
    self.artworkSeekArea.hidden = !showArtworkRing;
    self.elapsedLabel.hidden = !showProgress;
    self.remainingLabel.hidden = !showProgress;
    self.routeView.hidden = [settings[@"hideRoute"] boolValue];
    [self updateControlImages];
    [self updateAccent];
    [self updateScaledFonts];   // 字号只在这里更新（布局之外），避免布局递归
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
    UIColor *textAccent = dark ? [UIColor colorWithRed:MIN(1, r * 0.52 + 0.48)
                                                  green:MIN(1, g * 0.52 + 0.48)
                                                   blue:MIN(1, b * 0.52 + 0.48) alpha:1] : accent;
    UIColor *baseProgress = [self.settings[@"progressFromArtwork"] boolValue]
        ? accent : [UIColor colorWithRed:0.18 green:0.45 blue:0.76 alpha:1];
    CGFloat pr = 0, pg = 0, pb = 0, pa = 0;
    [baseProgress getRed:&pr green:&pg blue:&pb alpha:&pa];
    UIColor *progressColor = dark ? [UIColor colorWithRed:pr * 0.55 + 0.45
                                                    green:pg * 0.55 + 0.45
                                                     blue:pb * 0.55 + 0.45 alpha:1] : baseProgress;
    self.backgroundColor = [self.settings[@"backgroundFromArtwork"] boolValue]
        ? (dark ? [UIColor colorWithRed:r * 0.22 + 0.08 green:g * 0.22 + 0.08 blue:b * 0.22 + 0.08 alpha:0.97]
                : [UIColor colorWithRed:r * 0.18 + 0.82 green:g * 0.18 + 0.82 blue:b * 0.18 + 0.82 alpha:0.97])
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
    if (self.usesNativeMetadataFallback && self.superview) [self seedFromNativePlayer:self.superview];
    if (!self.window || !QLoadMediaRemote()) return;
    __weak typeof(self) weakSelf = self;
    QGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef result) {
        QPlayerView *strongSelf = weakSelf;
        if (!strongSelf) return;
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
        NSTimeInterval timestamp = [info[QKey(QTimestampKey, @"kMRMediaRemoteNowPlayingInfoTimestamp")] doubleValue];
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
    });
    if (QGetPlaying) QGetPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
        QPlayerView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.playing != isPlaying) {
            CFTimeInterval now = CACurrentMediaTime();
            strongSelf.progressAnchorElapsed = strongSelf.elapsed;
            strongSelf.progressAnchorTime = now;
        }
        strongSelf.playing = isPlaying;
        if (QIsPlaybackPlaceholder(strongSelf.titleLabel.text) || strongSelf.titleLabel.text.length == 0) {
            strongSelf.titleLabel.text = isPlaying ? QPlayingPlaceholder() : @"";
        }
        [strongSelf updateControlImages];
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

- (void)previous:(id)sender { if (QSendCommand) QSendCommand(5, nil); [self refresh]; }
- (void)toggle:(id)sender { if (QSendCommand) QSendCommand(2, nil); [self refresh]; }
- (void)next:(id)sender { if (QSendCommand) QSendCommand(4, nil); [self refresh]; }
- (void)openPlayingApp:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/openplayingapp"), NULL, NULL, YES);
}
- (void)scrubStarted:(id)sender { self.scrubbing = YES; }
- (void)seekTapped:(UITapGestureRecognizer *)gesture {
    UIView *area = gesture.view;
    CGPoint point = [gesture locationInView:area];
    self.progress.value = MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
    [self updateProgressFill];
    [self scrubEnded:self.progress];
}
- (void)seekPanned:(UIPanGestureRecognizer *)gesture {
    UIView *area = gesture.view;
    if (area == self.progress) {
        // 底部进度条：手指位置即进度（保持原交互）
        CGPoint point = [gesture locationInView:area];
        self.progress.value = MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
        [self updateProgressFill];
        if (gesture.state == UIGestureRecognizerStateBegan) self.scrubbing = YES;
        if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
            [self scrubEnded:self.progress];
        }
        return;
    }
    // 背景进度：相对拖拽，拖动 0.6 倍播放器宽度走完全程
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.scrubbing = YES;
        self.dragStartProgress = MIN(1, MAX(0, self.progress.value));
        self.dragStartX = [gesture translationInView:self].x;
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat span = MAX(1, self.bounds.size.width * 0.6);
        self.progress.value = MIN(1, MAX(0, self.dragStartProgress +
                                         ([gesture translationInView:self].x - self.dragStartX) / span));
        [self updateProgressFill];
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self scrubEnded:self.progress];
    }
}
static CGFloat QArtworkSeekFraction(UIView *area, CGPoint point) {
    return MIN(1, MAX(0, point.x / MAX(1, area.bounds.size.width)));
}
- (void)artworkSeekTapped:(UITapGestureRecognizer *)gesture {
    UIView *area = gesture.view;
    CGPoint point = [gesture locationInView:area];
    CGRect artFrame = [self.artwork convertRect:self.artwork.bounds toView:area];
    CGPoint center = CGPointMake(CGRectGetMidX(artFrame), CGRectGetMidY(artFrame));
    CGFloat distance = hypot(point.x - center.x, point.y - center.y);
    if (distance < MIN(artFrame.size.width, artFrame.size.height) / 2 - 6) {
        [self openPlayingApp:area];
        return;
    }
    self.progress.value = QArtworkSeekFraction(area, point);
    [self updateProgressFill];
    [self scrubEnded:self.progress];
}
- (void)artworkSeekPanned:(UIPanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan &&
        gesture.state != UIGestureRecognizerStateChanged &&
        gesture.state != UIGestureRecognizerStateEnded &&
        gesture.state != UIGestureRecognizerStateCancelled) return;
    // 封面进度：相对拖拽，拖动 0.6 倍播放器宽度走完全程
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.scrubbing = YES;
        self.dragStartProgress = MIN(1, MAX(0, self.progress.value));
        self.dragStartX = [gesture translationInView:self].x;
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat span = MAX(1, self.bounds.size.width * 0.6);
        self.progress.value = MIN(1, MAX(0, self.dragStartProgress +
                                         ([gesture translationInView:self].x - self.dragStartX) / span));
        [self updateProgressFill];
        return;
    }
    [self scrubEnded:self.progress];
}
- (void)scrubEnded:(id)sender {
    self.scrubbing = NO;
    CGFloat fraction = MIN(1, MAX(0, self.progress.value));
    self.seekTarget = self.duration * fraction;
    self.seekHoldUntil = CFAbsoluteTimeGetCurrent() + 2.5;
    if (QSetElapsed && self.duration > 0) QSetElapsed(fraction * self.duration);
    UISlider *native = self.nativeSlider;
    if (native) {
        native.value = native.minimumValue + fraction * (native.maximumValue - native.minimumValue);
        [native sendActionsForControlEvents:UIControlEventValueChanged];
        [native sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    self.elapsed = self.duration * fraction;
    self.progressAnchorElapsed = self.elapsed;
    self.progressAnchorTime = CACurrentMediaTime();
    [self updateProgressFill];
    [self refresh];
}

- (void)updateProgressFill {
    CGFloat fraction = isfinite(self.progress.value) ? MIN(1, MAX(0, self.progress.value)) : 0;
    CGFloat scale = UIScreen.mainScreen.scale;
    CGFloat width = round(self.bounds.size.width * fraction * scale) / scale;
    self.backgroundProgress.frame = CGRectMake(0, 0, width, self.bounds.size.height);
    CGFloat roundness = self.settings[@"playerCornerRoundness"] ? [self.settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    self.backgroundProgress.layer.cornerRadius = MIN(self.bounds.size.height * roundness / 2, width / 2);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.artworkProgressRing.strokeEnd = fraction;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat roundness = self.settings[@"playerCornerRoundness"] ? [self.settings[@"playerCornerRoundness"] doubleValue] : 1;
    roundness = isfinite(roundness) ? MIN(1, MAX(0, roundness)) : 1;
    self.layer.cornerRadius = h * roundness / 2;
    self.layer.cornerCurve = kCACornerCurveCircular;
    self.backgroundProgress.layer.cornerCurve = kCACornerCurveCircular;
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
    self.artwork.layer.cornerCurve = kCACornerCurveCircular;
    CGRect ringFrame = CGRectInset(self.artwork.frame, -3 * c, -3 * c);
    self.artworkSeekArea.frame = self.bounds;
    CGFloat ringRectPad = 1.25 * c;
    CGRect ringRect = CGRectInset(CGRectMake(0, 0, ringFrame.size.width, ringFrame.size.height), ringRectPad, ringRectPad);
    CGFloat left = CGRectGetMinX(ringRect), right = CGRectGetMaxX(ringRect);
    CGFloat top = CGRectGetMinY(ringRect), bottom = CGRectGetMaxY(ringRect);
    CGFloat ringRadius = MIN(ringRect.size.width, ringRect.size.height) * roundness / 2;
    CGMutablePathRef ringPath = CGPathCreateMutable();
    CGPathMoveToPoint(ringPath, NULL, CGRectGetMidX(ringRect), top);
    CGPathAddLineToPoint(ringPath, NULL, right - ringRadius, top);
    if (ringRadius > 0) CGPathAddArcToPoint(ringPath, NULL, right, top, right, top + ringRadius, ringRadius);
    CGPathAddLineToPoint(ringPath, NULL, right, bottom - ringRadius);
    if (ringRadius > 0) CGPathAddArcToPoint(ringPath, NULL, right, bottom, right - ringRadius, bottom, ringRadius);
    CGPathAddLineToPoint(ringPath, NULL, left + ringRadius, bottom);
    if (ringRadius > 0) CGPathAddArcToPoint(ringPath, NULL, left, bottom, left, bottom - ringRadius, ringRadius);
    CGPathAddLineToPoint(ringPath, NULL, left, top + ringRadius);
    if (ringRadius > 0) CGPathAddArcToPoint(ringPath, NULL, left, top, left + ringRadius, top, ringRadius);
    CGPathCloseSubpath(ringPath);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.artworkProgressTrack.frame = ringFrame;
    self.artworkProgressRing.frame = ringFrame;
    self.artworkProgressTrack.path = ringPath;
    self.artworkProgressRing.path = ringPath;
    [CATransaction commit];
    CGPathRelease(ringPath);
    CGFloat textX = pad + art + 12 * c;
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
