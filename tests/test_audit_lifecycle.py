"""Check the source's geometry and refresh decisions across state transitions."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
springboard = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
position = springboard.split("static void QPositionLockWidget(", 1)[1].split(
    "static void QPositionLowerWidgets", 1)[0]
assert "CGRectApplyAffineTransform(widget.bounds, nativeTransform).size" in position
assert "QLockClockAppliedTransformKey" in position and "QLockClockAppliedCenterKey" in position
assert "widget.transform, appliedTransform.CGAffineTransformValue" in position
scale_expression = re.search(r"CGFloat scale = ([^;]+);", position)[1]
scale_expression = scale_expression.replace("original.size.width", "native_width").replace("MAX", "max")
# A retained widget resizes from 430 to 300, then to 600. The requested width stays 200.
for bounds_width, native_scale in ((430, 1), (300, 1), (300, 1), (600, 1), (300, 1.2)):
    width, native_width = 200, bounds_width * native_scale
    scale = eval(scale_expression, {"__builtins__": {}, "max": max}, locals())
    assert abs(bounds_width * native_scale * scale - width) < 1e-9
assert "CGAffineTransformScale(nativeTransform, scale, scale)" in position
assert "CGPointEqualToPoint(widget.center, appliedCenter.CGPointValue)" in position
assert "QLockClockOriginalFrameKey, nil" in position

artwork = (root / "QNativeArtwork.m").read_text(encoding="utf-8")
monitor = artwork.split("static void QSetNativeArtworkExpanded", 1)[1].split(
    "static void QTickNativeProgress", 1)[0]
assert "showRing" not in monitor and "QArtworkFlag" not in monitor
assert "timerWithTimeInterval:0.25" in monitor and "QNativeArtworkVisible(view)" in monitor
assert "QSetNativeArtworkExpanded(NO)" in monitor
assert "[qArtworkVisibilityTimer invalidate]" in monitor
assert "NSRunLoopCommonModes" in monitor
tick = artwork.split("static void QTickNativeProgress", 1)[1].split("@interface QNativeArtworkTicker", 1)[0]
assert "nativeartworkcollapsed" not in tick  # Collapse cannot depend on a progress frame.
assert "QSetNativeArtworkExpanded(YES)" in artwork.split("static void QToggleNativeArtwork", 1)[1]

player = (root / "QPlayerView.m").read_text(encoding="utf-8")
visible = player.split("- (BOOL)qRefreshVisible {", 1)[1].split("- (void)qSuspendRefresh", 1)[0]
assert "view = view.superview" in visible and "view.hidden || view.alpha < 0.01" in visible
assert "CGRectIntersectsRect" in visible and "self.refreshSuspended" in visible
lifecycle = player.split("- (void)qUpdateRefreshLifecycle {", 1)[1].split(
    "- (void)traitCollectionDidChange", 1)[0]
animate = re.search(r"BOOL animateProgress = ([^;]+);", lifecycle)[1]
animate = animate.replace("[self qRefreshVisible]", "visible").replace("self.playing", "playing")
animate = animate.replace("self.duration", "duration").replace('[self.settings[@"showProgress"] boolValue]', "show_progress")
animate = " ".join(animate.replace("&&", "and").split())
for visible, playing, duration, show_progress, expected in (
    (True, True, 60, True, True), (False, True, 60, True, False),
    (True, False, 60, True, False), (True, True, 0, True, False),
    (True, True, 60, False, False),
):
    assert eval(animate, {"__builtins__": {}}, locals()) == expected
assert "__weak typeof(self) weakSelf" in lifecycle and "else if (!self.timer)" in lifecycle
assert "if (!animateProgress)" in lifecycle and "[self.progressDisplayLink invalidate]" in lifecycle
refresh = player.split("- (void)refresh {", 1)[1].split("static NSString *QTextInView", 1)[0]
assert refresh.index("if (![self qRefreshVisible]) return") < refresh.index("QGetInfo(")
assert refresh.count("![strongSelf qRefreshVisible]") == 2
settings = player.split("- (void)applySettings:", 1)[1].split("static UIColor *QAccentFromImage", 1)[0]
assert "isEqualToDictionary:settings" in settings and "CGSizeEqualToSize" in settings
assert settings.index("return;") < settings.index("[self updateControlImages]")
print("PASS: retained widget resize, cover collapse without progress, visibility/paused refresh and unchanged settings")
