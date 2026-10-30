"""Check process ownership and production predicates against runtime scene roles."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
compact = (root / "QCompactPlayer.m").read_text(encoding="utf-8")
springboard = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
artwork = (root / "QNativeArtwork.m").read_text(encoding="utf-8")
roles = json.loads((root / "tests/fixtures/media_scene_roles.json").read_text(encoding="utf-8"))

install = compact.split("void QInstallCompactPlayerHooks(void) {", 1)[1]
assert install.index('isEqualToString:@"com.apple.MediaRemoteUI"') < install.index("MSHookMessageEx")
assert 'objc_getClass("MRUCoverSheetView")' in install
assert "MSHookMessageEx(hostClass, @selector(layoutSubviews)" in install
assert "MSHookMessageEx(hostClass, @selector(didMoveToWindow)" in install
assert "../QCompactPlayer.m" in (root / "springboard/Makefile").read_text(encoding="utf-8")
ctor = springboard.split("%ctor {", 1)[1]
media_branch = ctor.split("return;", 1)[0]
assert "com.apple.MediaRemoteUI" in media_branch
assert "QInstallNativeArtworkHooks();" in media_branch and "QInstallCompactPlayerHooks();" in media_branch
# SpringBoard draws a player only on iOS 16, from the single gated layout function.
assert springboard.count("[[QPlayerView alloc]") == 1
sb_layout = springboard.split("static void QLayoutSpringBoardPlayer(", 1)[1].split("static void QApplyPlatterChrome(", 1)[0]
assert "[[QPlayerView alloc]" in sb_layout
assert springboard.count("QLayoutSpringBoardPlayer(platter, hideChrome)") == 1
chrome = springboard.split("static void QApplyPlatterChrome(", 1)[1].split("%group QHostPlatter", 1)[0]
assert "if (QUsesSpringBoardPlayer()) {\n        // The whole platter is hidden instead" in chrome
gate = springboard.split("static BOOL QUsesSpringBoardPlayer(void) {", 1)[1].split("}\n", 2)[0]
assert "isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}" in springboard

role = re.search(r'BOOL listScene = .*isEqualToString:@"([^"]+)"\];', compact)[1]
assert role == roles["ActivityUIServices.ActivityListItemSceneSpecification"]["role"]
enabled_expression = re.search(r"BOOL enabled = (.*?);", compact, re.S)[1]
enabled_expression = enabled_expression.replace('[qCompactSettings[@"masterEnabled"] boolValue]', "master")
enabled_expression = " ".join(enabled_expression.replace('[qCompactSettings[@"playerEnabled"] boolValue]', "enabled").replace("&&", "and").split())
reject_expression = re.search(r"if \((!listScene .*?)\) {", compact, re.S)[1]
reject_expression = reject_expression.replace("CGRectIsEmpty(host.bounds)", "empty")
reject_expression = reject_expression.replace("listScene", "list_scene").replace("||", "or").replace("!", "not ")
for spec, value in roles.items():
    for master, enabled, empty in ((True, True, False), (False, True, False),
                                   (True, False, False), (True, True, True)):
        allowed = eval(enabled_expression, {"__builtins__": {}}, dict(master=master, enabled=enabled))
        rejected = eval(reject_expression, {"__builtins__": {}},
                        dict(list_scene=value["role"] == role, enabled=allowed, empty=empty))
        assert (not rejected) == ("ListItem" in spec and master and enabled and not empty)

# Evaluate the actual geometry expression, including zero and short native bounds.
height_expression = re.search(r"CGFloat height = (.*?);", compact)[1]
height_expression = height_expression.replace("MIN", "min").replace("MAX", "max").replace("host.bounds.size.height", "native_height")
frame = re.search(r"player.frame = CGRectMake\((.*?)\);", compact, re.S)[1].split(",")
assert len(frame) == 4
frame = [" ".join(part.replace("CGRectGetMinX(host.bounds)", "x")
         .replace("CGRectGetMinY(host.bounds)", "y")
         .replace("host.bounds.size.height", "native_height")
         .replace("host.bounds.size.width", "width").split()) for part in frame]
for native_height in (0, 8, 40, 88, 137, 167, 195):
    height = eval(height_expression, {"__builtins__": {}, "min": min, "max": max}, dict(native_height=native_height))
    values = dict(x=0, y=0, native_height=native_height, width=402, height=height)
    actual = [eval(part, {"__builtins__": {}}, values) for part in frame]
    assert 0 <= actual[3] <= 88 and actual[1] >= 0
    assert actual[1] + actual[3] <= native_height
    assert abs(actual[1] - (native_height - height) / 2) < 1e-9

layout = compact.split("static void QCompactLayout(", 1)[1].split("static void (*qCompactOriginalDidMove)", 1)[0]
assert "QRestoreCompactContent(host)" not in layout
assert layout.index("qCompactOriginalLayout(host, selector)") < layout.index("QLayoutCompactHost(host)")
restore = compact.split("static void QRestoreCompactContent(", 1)[1].split("static void QLayoutCompactHost", 1)[0]
assert "doubleValue" in restore and "gesture.enabled" in restore and "view.hidden = state.lastObject.boolValue" in restore
assert "[player removeFromSuperview]" in restore and "QCompactPlayerKey, nil" in restore
assert "weakToStrongObjectsMapTable" in compact and "[qCompactHosts addObject:host]" in compact
assert "setSuppressSiblingViews:NO" in compact and "setUsesNativeMetadataFallback:YES" in compact
for notification in ("com.gushi.quart17/preferenceschanged", "com.gushi.aura/preferenceschanged",
                     "com.gushi.quart17/nativeartworkexpanded", "com.gushi.quart17/nativeartworkcollapsed"):
    assert notification in install
assert "QReadPlayerSettings()" in compact and "QReadPlayerSettings()" in springboard
assert "QReadPlayerSettings()" in artwork and "CFPreferencesCopyMultiple" in player
assert "UISceneDidEnterBackgroundNotification" in player and "UISceneWillEnterForegroundNotification" in player
assert player.count("notification.object != self.window.windowScene") == 2
assert "UIApplicationDidEnterBackgroundNotification" not in player
assert "@selector(didSelectLabelView:), label" in player
assert "com.gushi.quart17/togglenativeartwork" in player and "com.gushi.quart17/artworkseek" in player
print("PASS: MediaRemoteUI ownership, list-only scene isolation, native restoration, scene lifecycle, shared settings and controls wiring")
