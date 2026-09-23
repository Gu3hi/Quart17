#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <roothide.h>

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
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
}

#pragma mark - 通用带标签滑块（尺寸 / 圆角共用）

// 设计要点：
// 1) 标题 + 右侧数值 + 下方满宽滑块，两行式；旧版「统一圆角」组两个滑块
//    完全没有标签，用户不知道该调什么，这里统一补上标题与百分比数值。
// 2) 颜色全部走系统语义色，浅色/深色自动切；旧版硬编码灰阶在深色设置页里发脏。
@interface QWidthSliderCell : PSTableCell
@property (nonatomic, strong) UIImageView *qIconView;
@property (nonatomic, strong) UILabel *qTitleLabel;
@property (nonatomic, strong) UILabel *qValueLabel;
@property (nonatomic, strong) UISlider *qSlider;
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

        _qIconView = [UIImageView new];
        _qIconView.contentMode = UIViewContentModeScaleAspectFit;
        _qIconView.tintColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:_qIconView];

        _qTitleLabel = [UILabel new];
        _qTitleLabel.font = [UIFont systemFontOfSize:17.0];
        _qTitleLabel.textColor = UIColor.labelColor;
        [self.contentView addSubview:_qTitleLabel];

        _qValueLabel = [UILabel new];
        _qValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightRegular];
        _qValueLabel.textColor = UIColor.secondaryLabelColor;
        _qValueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_qValueLabel];

        _qSlider = [UISlider new];
        NSNumber *min = specifier.properties[@"min"];
        NSNumber *max = specifier.properties[@"max"];
        _qSlider.minimumValue = min ? [min floatValue] : 0.70f;
        _qSlider.maximumValue = max ? [max floatValue] : 1.00f;
        _qSlider.continuous = YES;
        [_qSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [_qSlider addTarget:self action:@selector(sliderCommitted:)
           forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self.contentView addSubview:_qSlider];

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
    self.qIconView.image = specifier.properties[@"iconImage"];
    id raw = QReadPref(specifier.properties[@"key"], nil);
    if (!raw && [specifier.properties[@"key"] isEqualToString:@"playerCornerRoundness"]) {
        id legacy = QReadPref(@"roundArtwork", nil);
        raw = legacy && ![legacy boolValue] ? @0 : @1;
    }
    double v = [self rangeValue:raw ?: specifier.properties[@"default"]];
    self.qSlider.value = (float)v;
    BOOL scalingDisabled = [specifier.properties[@"key"] isEqualToString:@"widthScale"] &&
        [QReadPref(@"disableListScaling", @NO) boolValue];
    self.qSlider.enabled = !scalingDisabled;
    self.qTitleLabel.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qValueLabel.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qIconView.alpha = scalingDisabled ? 0.5 : 1.0;
    self.qValueLabel.text = [self percentForValue:v specifier:specifier];
}

- (double)rangeValue:(id)raw {
    double v = [raw respondsToSelector:@selector(doubleValue)] ? [raw doubleValue] : 1.0;
    if (!isfinite(v)) v = 1.0;
    return MIN(self.qSlider.maximumValue, MAX(self.qSlider.minimumValue, v));
}

// 统一按「倍率 → 百分比」显示（0-100% 与 70-100% 两种范围都是同一个读法）
- (NSString *)percentForValue:(double)v specifier:(PSSpecifier *)specifier {
    if ([specifier.properties[@"unit"] isEqualToString:@"pt"])
        return [NSString stringWithFormat:@"%.0f pt", round(v)];
    return [NSString stringWithFormat:@"%.0f%%", round(v * 100.0)];
}

- (void)sliderChanged:(UISlider *)slider {
    double v = slider.value;
    PSSpecifier *specifier = self.specifier;
    self.qValueLabel.text = [self percentForValue:v specifier:specifier];
}

- (void)sliderCommitted:(UISlider *)slider {
    [self sliderChanged:slider];
    QWritePref(self.specifier.properties[@"key"], @(slider.value));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.hidden = YES;
    self.imageView.hidden = YES;
    self.detailTextLabel.hidden = YES;
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat margin = 18.0;
    self.qIconView.frame = CGRectMake(margin, 14.0, 23.0, 23.0);
    self.qTitleLabel.frame = CGRectMake(margin + 34.0, 12.0, w - margin * 2.0 - 104.0, 27.0);
    self.qValueLabel.frame = CGRectMake(w - margin - 70.0, 12.0, 70.0, 27.0);
    self.qSlider.frame = CGRectMake(margin, 46.0, w - margin * 2.0, 32.0);
}

@end

#pragma mark - 列表控制器

@interface QRootListController : PSListController
@property (nonatomic, strong) NSArray<PSSpecifier *> *allQuartSpecifiers;
@end

@implementation QRootListController
- (BOOL)isChinese {
    return [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
}

- (NSString *)localized:(NSString *)chinese english:(NSString *)english {
    return self.isChinese ? chinese : english;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[self localized:@"刷新" english:@"Refresh"]
        style:UIBarButtonItemStylePlain target:self action:@selector(respring:)];
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

- (NSArray *)specifiers {
    if (!self.allQuartSpecifiers) {
        self.allQuartSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSDictionary *symbols = @{
            @"masterEnabled": @"power", @"enabled": @"bell.badge", @"darkCards": @"moon.fill",
            @"roundIcons": @"app.fill", @"clearAllEnabled": @"arrow.down.to.line",
            @"clearHapticEnabled": @"iphone.radiowaves.left.and.right",
            @"widthScale": @"rectangle.compress.vertical",
            @"scaleBanners": @"rectangle.on.rectangle", @"glassBanners": @"sparkles.rectangle.stack",
            @"disableListScaling": @"arrow.up.left.and.arrow.down.right",
            @"playerEnabled": @"play.rectangle.fill",
            @"playerCornerRoundness": @"square.on.circle",
            @"showProgress": @"slider.horizontal.3", @"progressStyle": @"circle.dotted.circle",
            @"hideControls": @"eye.slash",
            @"hideRoute": @"airplay.audio", @"backgroundFromArtwork": @"paintpalette.fill",
            @"titleFromArtwork": @"textformat", @"artistFromArtwork": @"person.fill",
            @"progressFromArtwork": @"line.diagonal"
        };
        NSDictionary *english = @{
            @"启用插件": @"Enable Quart17", @"尺寸": @"Size", @"锁屏列表大小": @"Lock Screen list size",
            @"停用通知缩放": @"Disable notification scaling",
            @"缩放桌面横幅": @"Scale notification banners",
            @"横幅与锁屏玻璃": @"Banner & Lock Screen glass",
            @"玻璃参数": @"Glass appearance",
            @"通知外观": @"Notifications",
            @"启用通知样式": @"Enable notification style", @"深色卡片": @"Dark cards",
            @"圆形应用图标": @"Round app icons",
            @"锁屏手势": @"Lock Screen gestures",
            @"右侧双下滑清除": @"Double swipe down to clear",
            @"清除时轻震动": @"Light haptic on clear",
            @"锁屏播放器": @"Lock Screen Player", @"Quart 风格播放器": @"Quart style player",
            @"播放器圆角": @"Player corner roundness",
            @"显示播放进度": @"Show playback progress",
            @"进度条样式": @"Progress style", @"隐藏控制按钮": @"Hide playback buttons",
            @"按钮图标目录": @"Button icon folder",
            @"隐藏音频输出入口": @"Hide audio output control",
            @"跟随封面颜色": @"Artwork Colors", @"播放器背景": @"Player background",
            @"歌曲标题": @"Song title", @"作者文字": @"Artist text",
            @"播放进度": @"Playback progress", @"关于": @"About",
            @"作者 @Put_Story": @"Author @Put_Story",
            @"致敬 @LaughingQuoll": @"Tribute to @LaughingQuoll",
            @"开源项目": @"Source code"
        };
        NSDictionary *englishFooters = @{
            @"关闭总开关会停用通知与锁屏播放器样式，并收起以下设置。": @"Turn off to disable both styles and collapse the options below.",
            @"锁屏列表大小控制锁屏通知；开启桌面横幅缩放后，弹出的横幅使用相同的大小。": @"Lock Screen list size controls Lock Screen notifications. Enable banner scaling to use the same size for incoming banners.",
            @"只控制通知卡片，不影响列表大小和锁屏播放器。": @"Only affects notification cards, not list size or the player.",
            @"从右半屏空白处连续两次下滑清除普通通知；滚动列表不会计入。保留音乐控件和实时活动；左半屏下滑打开系统搜索。": @"Swipe down twice from empty space on the right half to clear ordinary notifications. Scrolling the list does not count. Media controls and Live Activities stay; swiping down on the left opens system Search.",
            @"三种进度样式只能选择一种。点右上角“刷新”可更新样式，不会中断音频。": @"Choose one of three progress styles. Refresh updates the style without interrupting audio.",
            @"为每首歌从封面提取颜色。关闭某项后，该项使用固定配色。": @"Pick colors from each song's artwork. Disabled items use fixed colors.",
            @"致敬 @LaughingQuoll\n永远怀念最好的开发者。": @"In tribute to @LaughingQuoll\nForever remembering the best developer."
        };
        for (PSSpecifier *specifier in self.allQuartSpecifiers) {
            NSString *key = specifier.properties[@"key"];
            NSString *symbol = key ? symbols[key] : nil;
            UIImage *icon = symbol ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) [specifier setProperty:icon forKey:@"iconImage"];
            if (!self.isChinese) {
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
    if (!_specifiers) {
        BOOL active = [[self readPreferenceValue:self.allQuartSpecifiers[1]] boolValue];
        NSArray *visible = active ? self.allQuartSpecifiers :
            [self.allQuartSpecifiers subarrayWithRange:NSMakeRange(0, MIN(2, self.allQuartSpecifiers.count))];
        _specifiers = [visible mutableCopy];
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
    if (isSliderCell) return 88.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)openURLString:(NSString *)value {
    NSURL *url = [NSURL URLWithString:value];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)openGlassSettings:(id)sender {
    Class controllerClass = NSClassFromString(@"QGlassListController");
    UIViewController *controller = [[controllerClass alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openAuthor:(id)sender { [self openURLString:@"https://x.com/Put_Story"]; }
- (void)openOriginalAuthor:(id)sender { [self openURLString:@"https://x.com/LaughingQuoll"]; }
- (void)openProject:(id)sender {
    [self openURLString:@"https://github.com/Gu3hi/Quart17"];
}

- (void)showButtonIconPath:(id)sender {
    NSString *path = jbroot(@"/Library/Application Support/Quart17/Buttons");
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view%@", path]];
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

@interface QGlassListController : PSListController
@end

@implementation QGlassListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Glass" target:self] mutableCopy];
        BOOL chinese = [[NSLocale.preferredLanguages.firstObject lowercaseString] hasPrefix:@"zh"];
        self.title = chinese ? @"通知玻璃" : @"Notification Glass";
        if (!chinese) {
            NSDictionary *labels = @{@"模糊强度": @"Blur", @"边缘折射": @"Edge refraction",
                                      @"高光强度": @"Highlights"};
            for (PSSpecifier *specifier in _specifiers) {
                NSString *label = labels[specifier.name];
                if (label) specifier.name = label;
                NSString *footer = specifier.properties[@"footerText"];
                if (footer) [specifier setProperty:@"Banners and ordinary Lock Screen notifications share these settings. Refraction uses the iOS 17 backdrop mesh when available."
                                    forKey:@"footerText"];
            }
        }
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    id cellClass = specifier.properties[@"cellClass"];
    if ([cellClass isKindOfClass:NSString.class] && [cellClass isEqualToString:@"QWidthSliderCell"])
        return 88.0;
    if (cellClass == NSClassFromString(@"QWidthSliderCell")) return 88.0;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}
@end
