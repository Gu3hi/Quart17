"""Player buttons reuse Vela's media icons (static and animated) and follow Vela theme changes."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
tweak = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
host = (root / "VelaCAIconHost.h").read_text(encoding="utf-8")
vela_host = Path(r"C:\db\prysm\shared\PCAIconHost.inc")

# The CA host is Vela's own, vendored unchanged apart from the header note.
assert "@interface PCAIconHost : UIView" in host and "- (void)playTap;" in host
if vela_host.exists():
    assert host.split("\n", 3)[3] == vela_host.read_text(encoding="utf-8"), "vendored host drifted from Vela"
assert player.index("static inline NSString *PFResource(") < player.index('#import "VelaCAIconHost.h"')

# Theme selection mirrors Vela: folder themes only, "system" source turns them off.
rule = player.split("static NSString *QVelaThemeFolder(NSDictionary *vela) {", 1)[1].split("\n}", 1)[0]
assert '[vela[@"iconSource"] isEqual:@"system"]' in rule and '[identifier hasPrefix:@"folder:"]' in rule
assert 'QReadPreferenceDomain(@"com.gushi.vela")' in player

# Resolution order: Quart17 folder only when the switch is on, then explicit theme PNG, theme animation, other theme PNGs, native animation, symbol.
art = player.split("static NSDictionary *QControlArt(", 1)[1].split("\n}\n", 1)[0]
order = ["custom ? QVelaPNG", '@"Icons/%@/%@"', "Folders/Prysm/Icons", '@"Animations/%@.ca"', "Bundles/com.apple.MediaControls",
         "/System/Library/PrivateFrameworks/MediaControls.framework", '@{@"symbol": symbol}']
positions = [art.index(token) for token in order]
assert positions == sorted(positions), positions
assert '@[playing ? @"pause" : @"play"]' in art, "media.play states match Vela"
assert 'mapping[@"States"]' in art and 'mapping[@"Mirror"]' in art and 'mapping[@"Package"]' in art

# Animated art plays: state changes animate once shown, taps play the skip animation.
assert "applyStates:art[@\"states\"] animated:[self qAnimates] && self.art != nil" in player
assert "[self.previousButton playTap];" in player and "[self.nextButton playTap];" in player
assert '@"media.play", self.playing ? @"playing" : @"paused"' in player

# SpringBoard follows Vela's change notification and hands the theme to MediaRemoteUI.
assert 'CFSTR("com.gushi.vela/changed")' in tweak
publish = tweak.split('"com.gushi.quart17/velatheme"', 1)[1].split("playercornerchanged", 1)[0]
# notifyd forgets a state when its last token closes; MediaRemoteUI starts after SpringBoard on respring.
load = tweak.split("static void QLoadSettings(void) {", 1)[1].split("static void QChanged(", 1)[0]
assert "notify_cancel" not in load, "published states must keep their tokens open"
for name in ("artworkoffset", "artworkflags", "playerborder", "velatheme"):
    assert load.count('"com.gushi.quart17/' + name + '"') == 1
assert "(0x5173ULL << 48)" in publish and "QVelaThemeHash(velaTheme)" in publish
assert tweak.index('"com.gushi.quart17/velatheme"') < tweak.index('notify_post("com.gushi.quart17/playercornerchanged")')
mrui = player.split('notify_register_check("com.gushi.quart17/velatheme"', 1)[1].split("\n    }\n", 1)[0]
assert "(vela >> 48) == 0x5173ULL" in mrui and "QVelaThemeFolderForHash((uint32_t)vela)" in mrui
assert art.count("Quart17/Buttons") == 1, "the folder is never consulted with the switch off"
assert "settings[@\"customControlIcons\"] = @((vela & (1ULL << 33)) != 0);" in player
assert '[qSettings[@"customControlIcons"] boolValue] ? (1ULL << 33) : 0' in tweak
assert "QOutlineButton" not in player and "QButtonArtwork" not in player
print("PASS: Vela media icons reused (static + animated), theme changes followed in SpringBoard and MediaRemoteUI")
