#import <UIKit/UIKit.h>

@interface QPlayerView : UIView
- (void)applySettings:(NSDictionary *)settings;
- (void)refresh;
- (void)seedFromNativePlayer:(UIView *)player;
- (void)setSuppressSiblingViews:(BOOL)suppress;
- (void)setUsesNativeMetadataFallback:(BOOL)enabled;
- (BOOL)containsArtworkAtPoint:(CGPoint)point;
- (void)setExpandedArtwork:(BOOL)expanded;
@end

#ifdef __cplusplus
extern "C" {
#endif
NSDictionary *QReadPlayerSettings(void);
void QInstallCompactPlayerHooks(void);
#ifdef __cplusplus
}
#endif
