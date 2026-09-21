#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

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

- (NSArray *)specifiers {
    if (!self.allQuartSpecifiers) {
        self.allQuartSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSDictionary *symbols = @{
            @"masterEnabled": @"power", @"enabled": @"bell.badge", @"darkCards": @"moon.fill",
            @"roundIcons": @"app.fill", @"showContent": @"text.bubble",
            @"playerEnabled": @"play.rectangle.fill", @"roundArtwork": @"circle.grid.2x2.fill",
            @"showProgress": @"slider.horizontal.3", @"backgroundProgress": @"rectangle.fill",
            @"hideRoute": @"airplay.audio", @"backgroundFromArtwork": @"paintpalette.fill",
            @"titleFromArtwork": @"textformat", @"artistFromArtwork": @"person.fill",
            @"progressFromArtwork": @"line.diagonal"
        };
        NSDictionary *english = @{
            @"启用插件": @"Enable Quart17", @"通知外观": @"Notifications",
            @"启用通知样式": @"Enable notification style", @"深色卡片": @"Dark cards",
            @"圆形应用图标": @"Round app icons", @"显示通知内容": @"Show notification text",
            @"锁屏播放器": @"Lock Screen Player", @"Quart 风格播放器": @"Quart style player",
            @"圆角封面": @"Rounded artwork", @"显示播放进度": @"Show playback progress",
            @"用背景显示进度": @"Use background progress", @"隐藏音频输出入口": @"Hide audio output control",
            @"跟随封面颜色": @"Artwork Colors", @"播放器背景": @"Player background",
            @"歌曲标题": @"Song title", @"作者文字": @"Artist text",
            @"播放进度": @"Playback progress", @"关于": @"About",
            @"作者 @Put_Story": @"Author @Put_Story",
            @"致敬 @LaughingQuoll": @"Tribute to @LaughingQuoll",
            @"开源项目": @"Source code"
        };
        NSDictionary *englishFooters = @{
            @"关闭总开关会停用通知与锁屏播放器样式，并收起以下设置。": @"Turn off to disable both styles and collapse the options below.",
            @"只控制通知卡片。锁屏播放器由下方的开关单独控制。": @"Only affects notification cards. The player has its own switch below.",
            @"替换锁屏播放器外观。点右上角“刷新”可更新已显示的内容，不会中断音频。": @"Replace the Lock Screen player. Refresh updates visible content without interrupting audio.",
            @"为每首歌从封面提取颜色。关闭某项后，该项使用固定配色。": @"Pick colors from each song's artwork. Disabled items use fixed colors.",
            @"致敬 @LaughingQuoll\n永远怀念最好的开发者。": @"In tribute to @LaughingQuoll\nForever remembering the best developer."
        };
        for (PSSpecifier *specifier in self.allQuartSpecifiers) {
            NSString *key = specifier.properties[@"key"];
            NSString *symbol = key ? symbols[key] : nil;
            UIImage *icon = symbol ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) [specifier setProperty:icon forKey:@"iconImage"];
            if (!self.isChinese) {
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

- (void)openURLString:(NSString *)value {
    NSURL *url = [NSURL URLWithString:value];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)openAuthor:(id)sender { [self openURLString:@"https://x.com/Put_Story"]; }
- (void)openOriginalAuthor:(id)sender { [self openURLString:@"https://x.com/LaughingQuoll"]; }
- (void)openProject:(id)sender {
    [self openURLString:@"https://github.com/Gu3hi/Quart17"];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.gushi.quart17.plist"];
    return settings[specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = @"/var/mobile/Library/Preferences/com.gushi.quart17.plist";
    NSMutableDictionary *settings = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
    settings[specifier.properties[@"key"]] = value;
    [settings writeToFile:path atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.gushi.quart17/preferenceschanged"), NULL, NULL, YES);
    if ([specifier.properties[@"key"] isEqualToString:@"masterEnabled"]) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}
@end
