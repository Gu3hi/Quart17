#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#ifdef Q_ROOTHIDE
#import <roothide.h>
#define QJbroot(path) jbroot(path)
#else
// 标准 Rootless：直接使用 /var/jb 前缀
#define QJbroot(path) [@"/var/jb" stringByAppendingString:(path)]
#endif
#import <notify.h>
#import <objc/runtime.h>

#pragma mark - 设计主题（DESIGN.md）

// 深色：画布 #07080A / 卡片 #121419 / 强调 #FF646E / 分隔线白 12%
// 浅色：画布 #F6F7F9 / 卡片白 / 强调 #C72940 / 分隔线黑 10%
@interface QTheme : NSObject
+ (UIColor *)canvasColor;
+ (UIColor *)surfaceColor;
+ (UIColor *)accentColor;
+ (UIColor *)hairlineColor;
+ (UIColor *)sliderSurfaceColor;
@end

@implementation QTheme
+ (UIColor *)canvasColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight)
            return [UIColor colorWithRed:0.965 green:0.969 blue:0.976 alpha:1.0];
        return [UIColor colorWithRed:0.027 green:0.031 blue:0.039 alpha:1.0];
    }];
}
+ (UIColor *)surfaceColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight)
            return UIColor.whiteColor;
        return [UIColor colorWithRed:0.071 green:0.078 blue:0.098 alpha:1.0];
    }];
}
+ (UIColor *)accentColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight)
            return [UIColor colorWithRed:0.780 green:0.161 blue:0.251 alpha:1.0];
        return [UIColor colorWithRed:1.0 green:0.392 blue:0.431 alpha:1.0];
    }];
}
+ (UIColor *)hairlineColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleLight)
            return [UIColor colorWithWhite:0.0 alpha:0.10];
        return [UIColor colorWithWhite:1.0 alpha:0.12];
    }];
}
+ (UIColor *)sliderSurfaceColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleLight
            ? [UIColor colorWithRed:0.94 green:0.95 blue:0.96 alpha:1.0]
            : [UIColor colorWithRed:0.071 green:0.078 blue:0.098 alpha:1.0];
    }];
}
@end

// 主题基类：统一表格底色、分隔线、开关强调色；明暗切换时重刷
@interface QThemedListController : PSListController
- (void)qApplyTheme;
@end

@implementation QThemedListController
- (void)viewDidLoad {
    [super viewDidLoad];
    [self qApplyTheme];
}
- (void)qApplyTheme {
    self.view.tintColor = QTheme.accentColor;
    self.table.backgroundColor = QTheme.canvasColor;
    self.table.separatorColor = QTheme.hairlineColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
        [self qApplyTheme];
        [self.table reloadData];
    }
}
- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([PSListController instancesRespondToSelector:_cmd])
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    if (![cell isKindOfClass:NSClassFromString(@"QWidthSliderCell")]) {
        cell.backgroundColor = QTheme.surfaceColor;
        cell.textLabel.textColor = UIColor.labelColor;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier.properties[@"qNavigation"] boolValue]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        UIImage *icon = specifier.properties[@"iconImage"];
        if ([icon isKindOfClass:UIImage.class]) {
            cell.imageView.hidden = NO;
            cell.imageView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.tintColor = QTheme.accentColor;
            [cell setNeedsLayout];
        }
    }
    cell.tintColor = QTheme.accentColor;
    UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
    toggle.onTintColor = QTheme.accentColor;
}
@end

static NSString *QPrefsPath(void) {
    return @"/var/mobile/Library/Preferences/com.gushi.quart17.plist";
}
static id QReadPref(NSString *key, id fallback) {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:QPrefsPath()];
    return settings[key] ?: fallback;
}
static void QWritePref(NSString *key, id value) {
    if (!key.length || !value) return;
    NSMutableDictionary *settings = [[NSDictionary dictionaryWithContentsOfFile:QPrefsPath()] mutableCopy]
                                     ?: [NSMutableDictionary dictionary];
    settings[key] = value;
    [settings writeToFile:QPrefsPath() atomically:YES];
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        CFSTR("com.gushi.quart17"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.gushi.quart17"),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if ([key isEqualToString:@"playerCornerRoundness"] ||
        [key isEqualToString:@"largeArtworkScale"] ||
        [key isEqualToString:@"largeArtworkRoundness"]) {
        int token = -1;
        if (notify_register_check("com.gushi.quart17/playercorner", &token) == NOTIFY_STATUS_OK) {
            double corner = [settings[@"playerCornerRoundness"] ?: @1 doubleValue];
            corner = isfinite(corner) ? MAX(0, MIN(1, corner)) : 1;
            double scale = [settings[@"largeArtworkScale"] ?: @1 doubleValue];
            scale = isfinite(scale) ? MAX(0.6, MIN(1, scale)) : 1;
            double expandedCorner = [settings[@"largeArtworkRoundness"] ?: @(corner) doubleValue];
            expandedCorner = isfinite(expandedCorner) ? MAX(0, MIN(1, expandedCorner)) : corner;
            notify_set_state(token, ((uint64_t)llround(expandedCorner * 10000) << 48) |
                ((uint64_t)llround(scale * 10000) << 32) |
                0x51700000ULL | (uint64_t)llround(corner * 10000));
            notify_cancel(token);
        }
    }
    // 大封面上下位移走独立同步通道（-200~200，存 (v+200)*100+1，0 表示未写入）
    if ([key isEqualToString:@"largeArtworkOffsetY"]) {
        int token = -1;
        if (notify_register_check("com.gushi.quart17/artworkoffset", &token) == NOTIFY_STATUS_OK) {
            double v = [value doubleValue];
            v = isfinite(v) ? MAX(-200, MIN(200, v)) : 0;
            notify_set_state(token, (uint64_t)llround((v + 200) * 100) + 1);
            notify_cancel(token);
        }
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
}

#pragma mark - 通用带标签滑块（尺寸 / 圆角共用）

// 设计要点：
// 1) 标题 + 右侧数值 + 下方满宽滑块，两行式；旧版「统一圆角」组两个滑块
//    完全没有标签，用户不知道该调什么，这里统一补上标题与百分比数值。
// 2) 颜色全部走系统语义色，浅色/深色自动切；旧版硬编码灰阶在深色设置页里发脏。
@interface QWidthSliderCell : PSTableCell
@property (nonatomic, strong) UILabel *qTitleLabel;
@property (nonatomic, strong) UILabel *qValueLabel;
@property (nonatomic, strong) UIView *qCardView;
@property (nonatomic, strong) UISlider *qSlider;
@property (nonatomic, strong) UIButton *qMinusButton;
@property (nonatomic, strong) UIButton *qPlusButton;
@end

@implementation QWidthSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.hidden = YES;
        self.imageView.hidden = YES;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.backgroundView = [UIView new];

        _qTitleLabel = [UILabel new];
        _qTitleLabel.font = [UIFont systemFontOfSize:17.0];
        _qTitleLabel.textColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:_qTitleLabel];

        _qValueLabel = [UILabel new];
        _qValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightRegular];
        _qValueLabel.textColor = UIColor.secondaryLabelColor;
        _qValueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_qValueLabel];

        _qCardView = [UIView new];
        _qCardView.backgroundColor = QTheme.sliderSurfaceColor;
        _qCardView.layer.cornerRadius = 16.0;
        _qCardView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _qCardView.layer.borderColor = [QTheme.hairlineColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        [self.contentView addSubview:_qCardView];

        UIColor *accent = QTheme.accentColor;
        _qMinusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_qMinusButton setImage:[UIImage systemImageNamed:@"minus.circle"] forState:UIControlStateNormal];
        [_qMinusButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
        _qMinusButton.tintColor = accent;
        [_qMinusButton addTarget:self action:@selector(decreaseValue:) forControlEvents:UIControlEventTouchUpInside];
        [_qCardView addSubview:_qMinusButton];

        _qPlusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_qPlusButton setImage:[UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
        [_qPlusButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
        _qPlusButton.tintColor = accent;
        [_qPlusButton addTarget:self action:@selector(increaseValue:) forControlEvents:UIControlEventTouchUpInside];
        [_qCardView addSubview:_qPlusButton];

        _qSlider = [UISlider new];
        NSNumber *min = specifier.properties[@"min"];
        NSNumber *max = specifier.properties[@"max"];
        _qSlider.minimumValue = min ? [min floatValue] : 0.70f;
        _qSlider.maximumValue = max ? [max floatValue] : 1.00f;
        _qSlider.continuous = YES;
        _qSlider.minimumTrackTintColor = accent;
        _qSlider.maximumTrackTintColor = UIColor.tertiarySystemFillColor;
        _qSlider.thumbTintColor = UIColor.whiteColor;
        [_qSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [_qSlider addTarget:self action:@selector(sliderCommitted:)
           forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [_qCardView addSubview:_qSlider];

        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.hidden = YES;
    self.imageView.hidden = YES;
    self.detailTextLabel.hidden = YES;
    self.qTitleLabel.text = specifier.name;
    id raw = QReadPref(specifier.properties[@"key"], nil);
    if (!raw && [specifier.properties[@"key"] isEqualToString:@"playerCornerRoundness"]) {
        id legacy = QReadPref(@"roundArtwork", nil);
        raw = legacy && ![legacy boolValue] ? @0 : @1;
    }
    if (!raw && [specifier.properties[@"key"] isEqualToString:@"largeArtworkRoundness"])
        raw = QReadPref(@"playerCornerRoundness", @1);
    double v = [self rangeValue:raw ?: specifier.properties[@"default"]];
    self.qSlider.value = (float)v;
    BOOL scalingDisabled = [specifier.properties[@"key"] isEqualToString:@"widthScale"] &&
        [QReadPref(@"disableListScaling", @NO) boolValue];
    self.qSlider.enabled = !scalingDisabled;
    self.qMinusButton.enabled = !scalingDisabled;
    self.qPlusButton.enabled = !scalingDisabled;
    self.qTitleLabel.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qValueLabel.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qCardView.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qValueLabel.text = [self percentForValue:v specifier:specifier];
}

- (double)rangeValue:(id)raw {
    double v = [raw respondsToSelector:@selector(doubleValue)] ? [raw doubleValue] : 1.0;
    if (!isfinite(v)) v = 1.0;
    return MIN(self.qSlider.maximumValue, MAX(self.qSlider.minimumValue, v));
}

// 统一按「倍率 → 百分比」显示（0-100% 与 70-100% 两种范围都是同一个读法）
// 底色浓度滑块（desktopVeil/lockVeil）范围是 0-30，已经是百分比数值，直接显示
- (NSString *)percentForValue:(double)v specifier:(PSSpecifier *)specifier {
    if ([specifier.properties[@"unit"] isEqualToString:@"pt"])
        return [NSString stringWithFormat:@"%.0f pt", round(v)];
    NSString *key = specifier.properties[@"key"];
    if ([key isEqualToString:@"desktopVeil"] || [key isEqualToString:@"lockVeil"] ||
        [key isEqualToString:@"alertVeil"] || [key isEqualToString:@"ccVeil"])
        return [NSString stringWithFormat:@"%.0f%%", round(v)];
    return [NSString stringWithFormat:@"%.0f%%", round(v * 100.0)];
}

- (void)sliderChanged:(UISlider *)slider {
    double v = slider.value;
    PSSpecifier *specifier = self.specifier;
    self.qValueLabel.text = [self percentForValue:v specifier:specifier];
}

- (void)sliderCommitted:(UISlider *)slider {
    [self sliderChanged:slider];
    NSString *key = self.specifier.properties[@"key"];
    QWritePref(key, @(slider.value));
    // 大封面大小变化时通知播放器设置页刷新位移滑块显示/隐藏
    if ([key isEqualToString:@"largeArtworkScale"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"QArtworkScaleChanged" object:nil];
    }
}

- (void)adjustValueBy:(double)direction {
    BOOL wholeNumber = [self.specifier.properties[@"unit"] isEqualToString:@"pt"] ||
        [self.specifier.properties[@"key"] isEqualToString:@"largeArtworkOffsetY"];
    double step = wholeNumber ? 1.0 : 0.01;
    double value = round(self.qSlider.value / step) * step + direction * step;
    self.qSlider.value = (float)[self rangeValue:@(value)];
    [self sliderCommitted:self.qSlider];
}

- (void)decreaseValue:(id)sender { [self adjustValueBy:-1.0]; }
- (void)increaseValue:(id)sender { [self adjustValueBy:1.0]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.hidden = YES;
    self.imageView.hidden = YES;
    self.detailTextLabel.hidden = YES;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat margin = 16.0;
    self.qTitleLabel.frame = CGRectMake(margin + 12.0, 3.0, w - 2.0 * margin - 100.0, 27.0);
    self.qValueLabel.frame = CGRectMake(w - margin - 84.0, 3.0, 72.0, 27.0);
    self.qCardView.frame = CGRectMake(margin, 35.0, w - 2.0 * margin, 64.0);
    CGFloat cardWidth = self.qCardView.bounds.size.width;
    self.qMinusButton.frame = CGRectMake(12.0, 10.0, 44.0, 44.0);
    self.qPlusButton.frame = CGRectMake(cardWidth - 56.0, 10.0, 44.0, 44.0);
    self.qSlider.frame = CGRectMake(62.0, 16.0, cardWidth - 124.0, 32.0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.qCardView.layer.borderColor = [QTheme.hairlineColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

@end

#pragma mark - 列表控制器

@interface QHeroView : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIImageView *symbol;
@property (nonatomic, strong) UILabel *eyebrow;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitle;
@end

@implementation QHeroView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _panel = [UIView new];
        _panel.backgroundColor = QTheme.surfaceColor;
        _panel.layer.cornerRadius = 22;
        _panel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _panel.layer.borderColor = [QTheme.hairlineColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
        [self addSubview:_panel];

        NSString *iconPath = [[NSBundle bundleForClass:self.class] pathForResource:@"icon@3x" ofType:@"png"];
        _symbol = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:iconPath]];
        _symbol.contentMode = UIViewContentModeScaleAspectFit;
        [_panel addSubview:_symbol];

        _eyebrow = [UILabel new];
        _eyebrow.text = @"QUART17  /  iOS 17";
        _eyebrow.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        _eyebrow.textColor = QTheme.accentColor;
        [_panel addSubview:_eyebrow];

        _titleLabel = [UILabel new];
        _titleLabel.text = @"Quart17";
        _titleLabel.font = [UIFont systemFontOfSize:29 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.labelColor;
        [_panel addSubview:_titleLabel];

        _subtitle = [UILabel new];
        _subtitle.text = [[[NSLocale preferredLanguages].firstObject lowercaseString] hasPrefix:@"zh"]
            ? @"通知排版、播放器交互与下拉清理" : @"Notifications, player and swipe to clear";
        _subtitle.font = [UIFont systemFontOfSize:13];
        _subtitle.textColor = UIColor.secondaryLabelColor;
        _subtitle.numberOfLines = 2;
        [_panel addSubview:_subtitle];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.panel.frame = CGRectMake(16, 12, MAX(0, self.bounds.size.width - 32), 132);
    self.symbol.frame = CGRectMake(20, 20, 52, 52);
    CGFloat textWidth = MAX(0, self.panel.bounds.size.width - 104);
    self.eyebrow.frame = CGRectMake(88, 20, textWidth, 17);
    self.titleLabel.frame = CGRectMake(88, 39, textWidth, 36);
    self.subtitle.frame = CGRectMake(20, 89, MAX(0, self.panel.bounds.size.width - 40), 30);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.panel.layer.borderColor = [QTheme.hairlineColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}
@end

@interface QRootListController : QThemedListController
@property (nonatomic, strong) NSArray<PSSpecifier *> *allQuartSpecifiers;
@property (nonatomic, strong) QHeroView *quartHeader;
@end

@implementation QRootListController
- (BOOL)isChinese {
    return [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
}

- (NSString *)qPlistName {
    id detail = self.specifier.properties[@"detail"];
    NSString *detailName = nil;
    if ([detail isKindOfClass:NSString.class]) detailName = detail;
    else if (detail && class_isMetaClass(object_getClass(detail))) detailName = NSStringFromClass((Class)detail);
    if ([detailName isEqualToString:@"QNotifications"] || [detailName isEqualToString:@"QPlayer"]) {
        return detailName;
    }
    return @"Root";
}

- (NSString *)localized:(NSString *)chinese english:(NSString *)english {
    return self.isChinese ? chinese : english;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[self localized:@"刷新" english:@"Refresh"]
        style:UIBarButtonItemStylePlain target:self action:@selector(respring:)];
    if ([[self qPlistName] isEqualToString:@"Root"]) {
        self.quartHeader = [[QHeroView alloc] initWithFrame:CGRectMake(0, 0, self.table.bounds.size.width, 160)];
        self.table.tableHeaderView = self.quartHeader;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.quartHeader && fabs(self.quartHeader.bounds.size.width - self.table.bounds.size.width) > 1) {
        self.quartHeader.frame = CGRectMake(0, 0, self.table.bounds.size.width, 160);
        self.table.tableHeaderView = self.quartHeader;
    }
}

- (void)respring:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:
        [self localized:@"已刷新 Quart17" english:@"Quart17 refreshed"]
        message:[self localized:@"播放器和通知样式已重新载入，音频继续播放。"
                          english:@"Player and notification styles were refreshed without stopping audio."]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"好" english:@"OK"]
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"好" english:@"OK"]
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

+ (void)qApplyIconsAndTranslations:(NSArray<PSSpecifier *> *)specifiers isChinese:(BOOL)isChinese {
        NSDictionary *symbols = @{
            @"masterEnabled": @"power", @"enabled": @"bell.badge",
            @"clearAllEnabled": @"arrow.down.to.line",
            @"clearHapticEnabled": @"iphone.radiowaves.left.and.right",
            @"widthScale": @"rectangle.compress.vertical",
            @"scaleBanners": @"rectangle.on.rectangle",
            @"disableListScaling": @"arrow.up.left.and.arrow.down.right",
            @"playerEnabled": @"play.rectangle.fill",
            @"playerCornerRoundness": @"square.on.circle",
            @"largeArtworkScale": @"arrow.up.left.and.arrow.down.right",
            @"largeArtworkRoundness": @"square.on.circle",
            @"largeArtworkOffsetY": @"arrow.up.and.down",
            @"showProgress": @"slider.horizontal.3", @"progressStyle": @"circle.dotted.circle",
            @"hideControls": @"eye.slash",
            @"hideRoute": @"airplay.audio", @"backgroundFromArtwork": @"paintpalette.fill",
            @"titleFromArtwork": @"textformat", @"artistFromArtwork": @"person.fill",
            @"progressFromArtwork": @"line.diagonal",
            @"showNotificationCount": @"number.circle",
            @"notificationsLink": @"bell.badge", @"playerLink": @"play.rectangle.fill"
        };
        NSDictionary *namedSymbols = @{
            @"通知排版与缩放": @"bell.badge",
            @"播放器布局与操作": @"play.rectangle.fill",
            @"作者 @Put_Story": @"person.crop.circle",
            @"致敬 @LaughingQuoll": @"heart",
            @"开源项目": @"chevron.left.forwardslash.chevron.right"
        };
         NSDictionary *english = @{
             @"通知与播放器": @"Notifications & Player",
             @"通知排版与缩放": @"Notification layout & size",
             @"播放器布局与操作": @"Player layout & controls",
             @"下拉清理": @"Swipe to clear",
             @"双下滑清理通知": @"Double swipe to clear",
             @"清理时触感反馈": @"Haptic feedback on clear",
            @"启用插件": @"Enable Quart17", @"尺寸": @"Size", @"锁屏列表大小": @"Lock Screen list size",
            @"停用通知缩放": @"Disable notification scaling",
            @"缩放桌面横幅": @"Scale notification banners",
            @"通知外观": @"Notifications",
            @"通知计数": @"Notification count",
            @"锁屏手势": @"Lock Screen gestures",
            @"右侧双下滑清除": @"Double swipe down to clear",
            @"清除时轻震动": @"Light haptic on clear",
            @"锁屏播放器": @"Lock Screen Player", @"Quart 风格播放器": @"Quart style player",
            @"大封面大小": @"Expanded artwork size",
            @"大封面圆角": @"Expanded artwork corners",
            @"大封面上下位移": @"Artwork vertical offset",
            @"播放器圆角": @"Player corners",
            @"显示播放进度": @"Show playback progress",
            @"进度条样式": @"Progress style", @"隐藏控制按钮": @"Hide playback buttons",
            @"按钮图标目录": @"Button icon folder",
            @"隐藏音频输出入口": @"Hide audio output control",
            @"跟随封面颜色": @"Artwork Colors", @"播放器背景": @"Player background",
            @"歌曲标题": @"Song title", @"作者文字": @"Artist text",
            @"播放进度": @"Playback progress", @"关于": @"About",
            @"作者 @Put_Story": @"Author @Put_Story",
            @"致敬 @LaughingQuoll": @"Tribute to @LaughingQuoll",
            @"开源项目": @"Source code",
             @"通知设置": @"Notifications",
            @"通知样式": @"Notification Style",
            @"进度条": @"Progress Bar", @"控制按钮": @"Controls",
            @"播放器": @"Player", @"功能": @"Features",
            @"背景": @"Background",
            @"底部": @"Bottom", @"封面圆环": @"Artwork Ring"
        };
         NSDictionary *englishFooters = @{
             @"Quart17 负责通知排版、播放器布局与操作、下拉清理；玻璃外观请到 Aura 设置。": @"Quart17 controls notification layout, player controls, and swipe to clear. Glass appearance is in Aura.",
             @"调整内容、尺寸和交互，不调整玻璃材质。": @"Adjust content, size, and interaction. Glass materials are in Aura.",
            @"锁屏列表大小控制通知宽度。开启桌面横幅缩放后，弹出的横幅使用相同的大小。": @"Lock Screen list size controls notification width. Enable banner scaling to use the same size for incoming banners.",
            @"关闭总开关会停用通知与锁屏播放器样式，并收起以下设置。": @"Turn off to disable both styles and collapse the options below.",
            @"锁屏列表大小控制锁屏通知；开启桌面横幅缩放后，弹出的横幅使用相同的大小。": @"Lock Screen list size controls Lock Screen notifications. Enable banner scaling to use the same size for incoming banners.",
            @"从右半屏空白处连续两次下滑清除普通通知；滚动列表不会计入。保留音乐控件和实时活动；左半屏下滑打开系统搜索。": @"Swipe down twice from empty space on the right half to clear ordinary notifications. Scrolling the list does not count. Media controls and Live Activities stay; swiping down on the left opens system Search.",
            @"三种进度样式只能选择一种。点右上角“刷新”可更新样式，不会中断音频。": @"Choose one of three progress styles. Refresh updates the style without interrupting audio.",
            @"大封面与环绕进度条一起缩放；大封面圆角可单独调整。缩小时可上下位移大封面。点击封面展开或收起，展开后可横滑播放器调整进度；点击歌名打开播放 App。": @"Expanded artwork and its progress ring scale together. Adjust expanded artwork corners separately. When shrunk, you can shift the artwork vertically. Tap the cover to expand or collapse it, swipe the player to seek while expanded, or tap the title to open the playing app.",
            @"为每首歌从封面提取颜色。关闭某项后，该项使用固定配色。": @"Pick colors from each song's artwork. Disabled items use fixed colors.",
            @"致敬 @LaughingQuoll\n永远怀念最好的开发者。": @"In tribute to @LaughingQuoll\nForever remembering the best developer.",
        };
        for (PSSpecifier *specifier in specifiers) {
            NSString *originalName = specifier.name;
            NSString *key = specifier.properties[@"key"];
            NSString *symbol = key ? symbols[key] : namedSymbols[originalName];
            UIImage *icon = symbol ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) [specifier setProperty:icon forKey:@"iconImage"];
            if ([originalName isEqualToString:@"通知排版与缩放"] ||
                [originalName isEqualToString:@"播放器布局与操作"])
                [specifier setProperty:@YES forKey:@"qNavigation"];
            if (!isChinese) {
                if ([key isEqualToString:@"progressStyle"]) {
                    [specifier setProperty:@[@"Background", @"Bottom", @"Artwork ring"] forKey:@"validTitles"];
                }
                NSString *translatedName = english[specifier.name];
                if (translatedName) specifier.name = translatedName;
                NSString *footer = specifier.properties[@"footerText"];
                if (footer && englishFooters[footer]) [specifier setProperty:englishFooters[footer] forKey:@"footerText"];
            }
        }
}

- (NSArray *)specifiers {
    if (!self.allQuartSpecifiers) {
        self.allQuartSpecifiers = [self loadSpecifiersFromPlistName:[self qPlistName] target:self];
        [QRootListController qApplyIconsAndTranslations:self.allQuartSpecifiers isChinese:self.isChinese];
        NSString *version = [[NSBundle bundleForClass:self.class] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        for (PSSpecifier *specifier in self.allQuartSpecifiers)
            if ([specifier.properties[@"qVersionFooter"] boolValue])
                [specifier setProperty:[NSString stringWithFormat:@"Quart17 %@ · iOS 17", version ?: @"—"]
                             forKey:@"footerText"];
    }
    if (!_specifiers) {
        // Sub-pages (QNotifications, QPlayer) show all items; only Root does master-switch filtering
        NSString *plist = [self qPlistName];
        if ([plist isEqualToString:@"QNotifications"] || [plist isEqualToString:@"QPlayer"]) {
            _specifiers = [self.allQuartSpecifiers mutableCopy];
        } else {
            BOOL active = self.allQuartSpecifiers.count > 1 &&
                [[self readPreferenceValue:self.allQuartSpecifiers[1]] boolValue];
            if (active) {
                _specifiers = [self.allQuartSpecifiers mutableCopy];
            } else {
                NSMutableArray *visible = [[self.allQuartSpecifiers
                    subarrayWithRange:NSMakeRange(0, MIN(2, self.allQuartSpecifiers.count))] mutableCopy];
                BOOL showFooter = NO;
                for (PSSpecifier *specifier in self.allQuartSpecifiers) {
                    if ([specifier.properties[@"qAlwaysVisible"] boolValue]) showFooter = YES;
                    if (showFooter) [visible addObject:specifier];
                }
                _specifiers = visible;
            }
        }
    }
    return _specifiers;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    // cellClass 在 properties 里是 Class 对象（Preferences 已把类名字符串转成类），
    // 不是 NSString。对它发 isEqualToString: 会抛
    // +[QWidthSliderCell isEqualToString:]: unrecognized selector 并崩掉 Preferences。
    // 必须按对象/字符串两种形态都能比较。
    id cellClass = specifier.properties[@"cellClass"];
    BOOL isSliderCell = NO;
    if ([cellClass isKindOfClass:NSClassFromString(@"NSString")]) {
        isSliderCell = [(NSString *)cellClass isEqualToString:@"QWidthSliderCell"];
    } else if (cellClass == NSClassFromString(@"QWidthSliderCell")) {
        isSliderCell = YES;
    }
    if (isSliderCell) return 108.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)openURLString:(NSString *)value {
    NSURL *url = [NSURL URLWithString:value];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)openNotificationsSettings:(id)sender {
    Class controllerClass = NSClassFromString(@"QNotificationsListController");
    UIViewController *controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openPlayerSettings:(id)sender {
    Class controllerClass = NSClassFromString(@"QPlayerListController");
    UIViewController *controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openAuthor:(id)sender { [self openURLString:@"https://x.com/Put_Story"]; }
- (void)openOriginalAuthor:(id)sender { [self openURLString:@"https://x.com/LaughingQuoll"]; }
- (void)openProject:(id)sender {
    [self openURLString:@"https://github.com/Gu3hi/Quart17"];
}

- (void)showButtonIconPath:(id)sender {
    NSString *path = QJbroot(@"/Library/Application Support/Quart17/Buttons");
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view%@", encoded]];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:QPrefsPath()];
    if ([specifier.properties[@"key"] isEqualToString:@"progressStyle"] && !settings[@"progressStyle"]) {
        return settings[@"backgroundProgress"] ? ([settings[@"backgroundProgress"] boolValue] ? @0 : @1) : @0;
    }
    if ([specifier.properties[@"key"] isEqualToString:@"playerCornerRoundness"] && !settings[@"playerCornerRoundness"]) {
        return settings[@"roundArtwork"] && ![settings[@"roundArtwork"] boolValue] ? @0 : @1;
    }
    if ([specifier.properties[@"key"] isEqualToString:@"largeArtworkRoundness"] && !settings[@"largeArtworkRoundness"])
        return settings[@"playerCornerRoundness"] ?: @1;
    return settings[specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[@"key"];
    QWritePref(key, value);
    // 总开关会收起/展开后续分组，需要重建 specifier；其余项只写值 + Darwin 通知，
    // 由 SpringBoard 侧自行刷新（滑块拖动时连续触发，重建列表会打断拖动）。
    if ([key isEqualToString:@"masterEnabled"] ||
        [key isEqualToString:@"disableListScaling"]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}
@end









@interface QNotificationsListController : QThemedListController
@end

@implementation QNotificationsListController
- (BOOL)qIsChinese {
    return [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self qIsChinese] ? @"通知排版与缩放" : @"Notification Layout & Size";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[self qIsChinese] ? @"刷新" : @"Refresh"
        style:UIBarButtonItemStylePlain target:self action:@selector(qRespring:)];
}
- (void)qRespring:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"NSettings" target:self] mutableCopy];
        [QRootListController qApplyIconsAndTranslations:_specifiers isChinese:[self qIsChinese]];
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    id cellClass = specifier.properties[@"cellClass"];
    if ([cellClass isKindOfClass:NSString.class] && [cellClass isEqualToString:@"QWidthSliderCell"])
        return 108.0;
    if (cellClass == NSClassFromString(@"QWidthSliderCell")) return 108.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return QReadPref(specifier.properties[@"key"], specifier.properties[@"default"]);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    QWritePref(specifier.properties[@"key"], value);
}
@end

@interface QPlayerListController : QThemedListController
@end

@implementation QPlayerListController
- (BOOL)qIsChinese {
    return [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(qArtworkScaleChanged)
                                                 name:@"QArtworkScaleChanged" object:nil];
    self.title = [self qIsChinese] ? @"播放器布局与操作" : @"Player Layout & Controls";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[self qIsChinese] ? @"刷新" : @"Refresh"
        style:UIBarButtonItemStylePlain target:self action:@selector(qRespring:)];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // PSSegmentCell 不响应 specifier 的 validTitles 修改，直接改 segmented control
    if ([self qIsChinese]) return;
    for (UITableViewCell *cell in self.table.visibleCells) {
        for (UISegmentedControl *seg in cell.contentView.subviews) {
            if (![seg isKindOfClass:UISegmentedControl.class]) continue;
            if (seg.numberOfSegments == 3) {
                [seg setTitle:@"Background" forSegmentAtIndex:0];
                [seg setTitle:@"Bottom" forSegmentAtIndex:1];
                [seg setTitle:@"Artwork ring" forSegmentAtIndex:2];
            }
        }
        // segmented control 可能在 cell 的更深层级
        for (UIView *sub in cell.contentView.subviews) {
            for (UISegmentedControl *seg in sub.subviews) {
                if (![seg isKindOfClass:UISegmentedControl.class]) continue;
                if (seg.numberOfSegments == 3) {
                    [seg setTitle:@"Background" forSegmentAtIndex:0];
                    [seg setTitle:@"Bottom" forSegmentAtIndex:1];
                    [seg setTitle:@"Artwork ring" forSegmentAtIndex:2];
                }
            }
        }
    }
}
- (void)qRespring:(id)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
}
- (void)qArtworkScaleChanged {
    [self reloadSpecifiers];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)showButtonIconPath:(id)sender {
    NSString *path = QJbroot(@"/Library/Application Support/Quart17/Buttons");
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view%@", encoded]];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"PSettings" target:self] mutableCopy];
        [QRootListController qApplyIconsAndTranslations:_specifiers isChinese:[self qIsChinese]];
    }
    // 大封面上下位移滑块仅在大封面缩小时出现
    double scale = [QReadPref(@"largeArtworkScale", @1) doubleValue];
    if (scale >= 1) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (PSSpecifier *sp in _specifiers) {
            if (![sp.properties[@"key"] isEqualToString:@"largeArtworkOffsetY"])
                [filtered addObject:sp];
        }
        return filtered;
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    id cellClass = specifier.properties[@"cellClass"];
    if ([cellClass isKindOfClass:NSString.class] && [cellClass isEqualToString:@"QWidthSliderCell"])
        return 108.0;
    if (cellClass == NSClassFromString(@"QWidthSliderCell")) return 108.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return QReadPref(specifier.properties[@"key"], specifier.properties[@"default"]);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[@"key"];
    QWritePref(key, value);
    // 大封面大小变化时，刷新位移滑块的显示/隐藏
    if ([key isEqualToString:@"largeArtworkScale"]) {
        [self reloadSpecifiers];
    }
}
@end

// MARK: - 第三方 App 白名单（勾选列表）
