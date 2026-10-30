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
// Apple's continuous corners below full roundness; circular at 100% so shapes stay true circles and capsules.
NSString *QCornerCurveForRoundness(CGFloat roundness);
// Rounded-rect outline that starts at the top centre (for progress rings); +1 retained.
CGPathRef QCreateRoundedRingPath(CGRect rect, CGFloat radius, CGFloat roundness);
// FNV-1a of a Vela theme folder name; SpringBoard publishes it so MediaRemoteUI can find the folder.
uint32_t QVelaThemeHash(NSString *folder);
#ifdef __cplusplus
}
#endif
