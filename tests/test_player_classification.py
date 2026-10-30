"""Evaluate production recognition expressions against captured and boundary cases."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
source = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
helper = source.split("static NSInteger QNowPlayingPlatterState(", 1)[1].split("static void *QPlayerChromeAlphaKey", 1)[0]
apply = source.split("static void QApplyPlatterChrome(", 1)[1].split("%group QHostPlatter", 1)[0]
group = source.split("%group QHostPlatter", 1)[1].split("%ctor", 1)[0]
hook = group.split("%hook PLPlatterView", 1)[1].split("%end", 1)[0]
material = group.split("%hook MTMaterialView", 1)[1].split("%end", 1)[0]


def expression(text):
    text = re.sub(r'QHasAncestor\(platter, @"([^"]+)"\)', r'"\1" in ancestors', text)
    text = re.sub(r'QFind\(platter, @"([^"]+)"\)', r'"\1" in views', text)
    text = text.replace("size.width", "width").replace("size.height", "height")
    text = text.replace("[identity isKindOfClass:NSString.class]", "isinstance(target_bundle, str)")
    text = re.sub(r'\[identity isEqualToString:@"([^"]+)"\]', r'target_bundle == "\1"', text)
    text = text.replace("? 1 : 0", "")
    return " ".join(text.replace("&&", "and").replace("||", "or").split())


candidate = expression(re.search(r"BOOL candidate = (.*?);", apply, re.S)[1])
local = expression(re.search(r"BOOL hasLocalMedia = (.*?);", helper, re.S)[1])
remote = expression(re.search(r"return (\[identity isKindOfClass:NSString.class\].*?);", helper, re.S)[1])
selectors = re.findall(r"@selector\(([^)]+)\)", helper)
assert selectors == ["activityHostViewController", "activitySceneDescriptor",
                     "activityDescriptor", "platterTargetBundleIdentifier"]
assert "if (!content) return -1;" in helper
assert "respondsToSelector:selector]) return hasLocalMedia ? 1 : 0" in helper
assert "if (!identity) return hasLocalMedia ? 1 : -1;" in helper
assert "if (!identity) return -1;" in helper


def state(views, target_bundle=None, descriptor=True, width=402, height=167,
          ancestors=("NCNotificationListCell", "NCNotificationListSupplementaryHostingView")):
    values = dict(views=views, target_bundle=target_bundle, width=width, height=height,
                  ancestors=ancestors, isinstance=isinstance, str=str)
    if not eval(candidate, {"__builtins__": {}}, values):
        return 0
    if "CSActivityItemContentView" not in views:
        return -1
    if not descriptor:
        return 1 if eval(local, {"__builtins__": {}}, values) else 0
    if target_bundle is None:
        return -1
    return 1 if eval(remote, {"__builtins__": {}}, values) else 0


def classify(*args, **kwargs):
    return state(*args, **kwargs) == 1


capture = json.loads((root / "tests/fixtures/remote_now_playing.json").read_text(encoding="utf-8"))
assert capture["now_playing_application"] is None
assert classify(capture["views"], capture["target_bundle"], width=capture["width"],
                height=capture["height"], ancestors=capture["ancestors"])
activity = {"CSActivityItemContentView", "_UISceneLayerHostContainerView"}
# Equal-sized Live Activities in the same supplementary section must stay native,
# even while music is playing elsewhere or the activity is above the player.
for bundle in ("com.example.liveactivity", "com.apple.Music", None, 1):
    assert not classify(activity, bundle)
    assert not classify(activity | {"MRUNowPlayingLabelView"}, bundle)
for bundle in ("com.example.liveactivity", "com.apple.Music", 1):
    assert state(activity, bundle) == 0, "Resolved foreign activities never inherit hidden chrome"
assert state(activity, None) == -1, "Unattached descriptor is retried, not treated as foreign"
assert state({"_UISceneLayerHostContainerView"}, "com.apple.MediaRemoteUI") == -1
assert not classify(activity, descriptor=False)
for signal in ("MRUNowPlayingLabelView", "MRUNowPlayingTimeControlsView"):
    media = activity | {signal}
    assert classify(media, descriptor=False), "Retain local MRU compatibility"
    assert classify(media, descriptor=False, height=100)
    assert classify(media, descriptor=False, width=300)
    assert not classify(media, descriptor=False, ancestors=("OtherCell",))
assert not classify({"MRUNowPlayingLabelView"}, descriptor=False)
assert "nowPlayingApplication" not in group

# Only an unresolved identity may keep chrome hidden; a resolved foreign activity restores it.
assert "state < 0 && wasHidden && platter.window" in apply
assert "if (state < 0 && platter.window && attempt < 8)" in apply
assert "[NSObject new]" in apply, "Retry token must be unique per chain"

# SpringBoard only controls external material and must never render a player.
assert "QPlayerView" not in group  # the hooks themselves never build a player
# iOS 16: local media views identify the platter, the player overlays it, and the material guard stays off.
assert "if (QUsesSpringBoardPlayer()) return hasLocalMedia ? 1 : 0;" in helper
assert helper.index("QUsesSpringBoardPlayer()") < helper.index('QFind(platter, @"CSActivityItemContentView")')
assert apply.index("if (QUsesSpringBoardPlayer()) {") < apply.index("QPlatterChromeHiddenKey, hideChrome ? @YES : nil")
sb = source.split("static void QLayoutSpringBoardPlayer(", 1)[1].split("static void QApplyPlatterChrome(", 1)[0]
assert "platter.layer.opacity = 0;" in sb and "platter.layer.opacity = 1;" in sb and "platter.alpha = 1;" in sb
assert "[player removeFromSuperview];" in sb and "QSpringBoardPlayerKey, nil" in sb
assert "setSuppressSiblingViews:NO" in sb and "seedFromNativePlayer:platter" in sb
assert "self.layer.opacity = 0" not in group
assert 'isEqualToString:@"MTMaterialView"' in source
assert "view.alpha = original.doubleValue" in apply
assert "QPlayerChromeAlphaKey, nil" in apply
for event in ("layoutSubviews", "didMoveToWindow", "didAddSubview:"):
    assert event in hook, event
# Late system alpha writes are recorded and kept at zero while suppressed.
assert "setAlpha:(CGFloat)alpha" in material and "%orig(0)" in material
assert "QPlayerChromeAlphaKey, @(alpha)" in material
# Always-On Display rewrites layer opacity directly; hidden keeps the material undrawn regardless.
assert "setHidden:(BOOL)hidden" in material and "%orig(YES)" in material
assert "QPlayerChromeVisibilityKey, @(hidden)" in material
assert "[view setHidden:originalHidden ? originalHidden.boolValue : view.hidden]" in apply
assert "view.hidden = originalHidden.boolValue" in apply
assert "QPlayerChromeVisibilityKey, nil" in apply
print("PASS: media identity, retry/stickiness, Live Activity chrome isolation, material alpha and hidden guards")
