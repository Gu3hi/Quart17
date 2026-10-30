"""Continuous corners (circular only at 100%), top-centred ring paths, and Quart17 owning the player corner."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
artwork = (root / "QNativeArtwork.m").read_text(encoding="utf-8")
header = (root / "QPlayerView.h").read_text(encoding="utf-8")
prefs = (root / "preferences/QRootListController.m").read_text(encoding="utf-8")

# The rule: continuous below full roundness, circular at 100% (true circles and capsules).
rule = player.split("NSString *QCornerCurveForRoundness(CGFloat roundness) {", 1)[1].split("\n}", 1)[0]
assert "roundness >= 0.999 ? kCACornerCurveCircular : kCACornerCurveContinuous" in rule
assert "QCornerCurveForRoundness" in header and "QCreateRoundedRingPath" in header

# No hard-coded circular curves remain; every corner goes through the rule.
for name, source in (("QPlayerView.m", player), ("QNativeArtwork.m", artwork)):
    body = source.replace(rule, "")
    for line in body.splitlines():
        if "cornerCurve =" in line:
            assert "kCACornerCurveCircular" not in line, (name, line.strip())
assert player.count("cornerCurve = QCornerCurveForRoundness(roundness)") >= 5
assert "QRoundArtworkLayers(view, part.layer, image.bounds.size, radius, QCornerCurveForRoundness(roundness), 0);" in artwork
assert "if (![layer.cornerCurve isEqualToString:curve]) layer.cornerCurve = curve;" in artwork

# Square mask for non-square artwork: true circle at 100%, continuous rounded square otherwise.
assert "roundness >= 0.999 ? [UIBezierPath bezierPathWithOvalInRect:square]" in artwork

# Ring paths share one builder that starts at the top centre in both curve styles.
ring = player.split("CGPathRef QCreateRoundedRingPath(CGRect rect, CGFloat radius, CGFloat roundness) {", 1)[1].split("\ntypedef", 1)[0]
assert "bezierPathWithRoundedRect:rect cornerRadius:radius" in ring
assert ring.count("CGPathMoveToPoint(path, NULL, midX, top);") == 2
assert "fabs(p[0].y - top) > 0.01 || p[0].x > midX + 0.01" in ring, "restart only from a top-edge start point"
assert "return CGPathCreateCopy(source);" in ring, "unexpected UIKit structure falls back to the plain outline"
assert "CGPathRef ringPath = QCreateRoundedRingPath(ringRect, ringRadius, roundness);" in player
assert "CGPathRef path = QCreateRoundedRingPath(ringFrame, ringRadius, roundness);" in artwork
assert "CGPathAddArcToPoint" not in artwork

# Quart17 owns the player corner: its own value first, Aura's former value only as migration fallback.
assert ('settings[@"playerCornerRoundness"] = saved[@"playerCornerRoundness"] ?: aura[@"playerCornerRoundness"] ?:'
        in player)
assert 'settings[@"largeArtworkRoundness"] = settings[@"playerCornerRoundness"];' in player
fallback = prefs.split("static id QPlayerCornerPref(void) {", 1)[1].split("\n}", 1)[0]
assert 'QReadPref(@"playerCornerRoundness", nil)' in fallback and 'aura[@"playerCornerRoundness"] ?: @1' in fallback
assert '[key isEqualToString:@"playerCornerRoundness"]) return QPlayerCornerPref();' in prefs
assert "raw = QPlayerCornerPref();" in prefs
corner_sync = prefs.split('[key isEqualToString:@"playerCornerRoundness"]) {', 1)[1].split("notify_cancel(token);", 1)[0]
assert 'settings[@"playerCornerRoundness"] ?: QPlayerCornerPref()' in corner_sync
items = plistlib.loads((root / "preferences/Resources/PSettings.plist").read_bytes())["items"]
slider = next(i for i in items if i.get("key") == "playerCornerRoundness")
assert slider["cellClass"] == "QWidthSliderCell" and (slider["min"], slider["max"], slider["default"]) == (0.0, 1.0, 1.0)
assert items.index(next(i for i in items if i.get("key") == "playerEnabled")) < items.index(slider)
assert '@"播放器圆角": @"Player corners"' in prefs
print("PASS: continuous corners with circular at 100%, top-centred rings, Quart17-owned player corner")
