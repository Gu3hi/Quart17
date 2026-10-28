"""Evaluate production recognition expressions against captured and boundary cases."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
source = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
hook = source.split("%hook PLPlatterView", 1)[1].split("%end", 1)[0]
helper = source.split("static BOOL QIsNowPlayingPlatter(", 1)[1].split("%group QHostPlatter", 1)[0]


def expression(text):
    text = re.sub(r'QHasAncestor\(self, @"([^"]+)"\)', r'"\1" in ancestors', text)
    text = re.sub(r'QFind\((?:self|platter), @"([^"]+)"\)', r'"\1" in views', text)
    text = text.replace("QIsNowPlayingPlatter(self)", "identified")
    text = text.replace("size.width", "width").replace("size.height", "height")
    text = text.replace("[identity isKindOfClass:NSString.class]", "isinstance(target_bundle, str)")
    text = re.sub(r'\[identity isEqualToString:@"([^"]+)"\]', r'target_bundle == "\1"', text)
    return " ".join(text.replace("&&", "and").replace("||", "or").split())


predicate = expression(re.search(r"BOOL mediaPlatter = (.*?);", hook, re.S)[1])
local = expression(re.search(r"BOOL hasLocalMedia = (.*?);", helper, re.S)[1])
remote = expression(re.search(r"return (\[identity isKindOfClass:NSString.class\].*?);", helper, re.S)[1])
selectors = re.findall(r"@selector\(([^)]+)\)", helper)
assert selectors == ["activityHostViewController", "activitySceneDescriptor",
                     "activityDescriptor", "platterTargetBundleIdentifier"]
assert "if (!content) return NO;" in helper
assert "respondsToSelector:selector]) return hasLocalMedia" in helper


def classify(views, target_bundle=None, descriptor=True, width=402, height=167,
             ancestors=("NCNotificationListCell", "NCNotificationListSupplementaryHostingView")):
    values = dict(views=views, target_bundle=target_bundle, width=width, height=height,
                  ancestors=ancestors, isinstance=isinstance, str=str)
    identified = eval(remote if descriptor else local, {"__builtins__": {}}, values)
    values["identified"] = identified and "CSActivityItemContentView" in views
    return bool(eval(predicate, {"__builtins__": {}}, values))


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
assert not classify(activity, descriptor=False)
for signal in ("MRUNowPlayingLabelView", "MRUNowPlayingTimeControlsView"):
    media = activity | {signal}
    assert classify(media, descriptor=False), "Retain local MRU compatibility"
    assert classify(media, descriptor=False, height=100)
    assert classify(media, descriptor=False, width=300)
    assert not classify(media, descriptor=False, ancestors=("OtherCell",))
assert not classify({"MRUNowPlayingLabelView"}, descriptor=False)
assert "nowPlayingApplication" not in hook
assert "otherY" not in hook and "shouldCreate" not in hook

# SpringBoard only controls external material and must never render a player.
assert "QPlayerView" not in hook and "QSpringBoardPlayerKey" not in source
assert "self.layer.opacity = 0" not in hook
assert 'isEqualToString:@"MTMaterialView"' in hook
assert "view.alpha = original.doubleValue" in hook
assert "QPlayerChromeAlphaKey, nil" in hook
print("PASS: current media identity, Live Activity chrome isolation, legacy MRU and SpringBoard rendering removal")
