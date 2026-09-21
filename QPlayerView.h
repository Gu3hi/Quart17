#import <UIKit/UIKit.h>

@interface QPlayerView : UIView
- (void)applySettings:(NSDictionary *)settings;
- (void)refresh;
- (void)seedFromNativePlayer:(UIView *)player;
- (void)setSuppressSiblingViews:(BOOL)suppress;
- (void)setUsesNativeMetadataFallback:(BOOL)enabled;
@end
