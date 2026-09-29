// QGlassCore.h - Quart17 共享玻璃核心
// SpringBoard dylib 和 UIKit dylib 共用：设置读取、基础工具、弹窗玻璃渲染。
// 策略逻辑（何时启用、用什么参数）由各 dylib 自己决定。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

// MARK: - 设置

extern NSString *const QPrefsBundleID;
extern NSMutableDictionary *QGlassSettings(void);
extern void QGlassLoadSettings(void);
extern void QGlassRefreshAlerts(void);
void QUpdateGlassRefraction(CALayer *backdrop, CGSize size, CGFloat radius,
                           CGFloat magnitude, UIVisualEffectView *glass);
extern id QGlassReadPref(NSString *key, id defaultValue);
extern void QGlassWritePref(NSString *key, id value);

// MARK: - 关联键（玻璃视图标记）

extern void *QGlassViewKey;              // material -> UIVisualEffectView
extern void *QGlassCompatKey;            // glass -> NSNumber compatibility flag
extern void *QGlassSheenKey;             // glass -> CAGradientLayer sheen
extern void *QGlassRimKey;               // glass -> CAGradientLayer rim
extern void *QGlassRimMaskKey;           // glass -> CALayer rim mask
extern void *QGlassBackdropKey;          // glass -> CABackdropLayer
extern void *QGlassBlurFilterKey;        // glass -> CAFilter blur
extern void *QGlassStyleKey;             // glass -> NSNumber UIBlurEffectStyle
extern void *QGlassOriginalStateKey;     // material -> @[hidden, cornerRadius, cornerCurve]

// MARK: - 基础工具

BOOL QGlassHasAncestor(UIView *view, NSString *className);
UIView *_Nullable QGlassFind(UIView *root, NSString *className);

// MARK: - 弹窗玻璃参数

typedef struct {
    CGFloat blur;        // 0-18, 默认 8
    CGFloat refraction;  // 0-24, 默认 12
    CGFloat highlight;   // 0-1,  默认 0.5
    CGFloat veil;        // 0-30, 默认 28
    BOOL forceDark;      // 强制深色
    CGFloat cornerRadius;
} QPopupGlassParams;

QPopupGlassParams QPopupGlassParamsFromSettings(void);

// MARK: - 弹窗玻璃渲染

// 为 material 创建或复用玻璃视图，返回 glass。调用方负责定位和圆角。
// 首次调用时保存 material 的原始 hidden/cornerRadius/cornerCurve。
UIVisualEffectView *QGlassRenderPopup(UIView *material, QPopupGlassParams params, BOOL dark);
// 移除玻璃并恢复 material 原始状态。
void QGlassRemovePopup(UIView *material);
BOOL QGlassMaterialIsBackground(UIView *material);

// MARK: - 系统弹窗样式

// 查找弹窗内的原生材质并应用玻璃；处理强制深色外观。
void QGlassStyleSystemAlert(UIView *alert);
void QGlassRestoreSystemAlert(UIView *alert);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
