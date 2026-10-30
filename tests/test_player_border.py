"""Player border: settings, cross-process encoding, Aura glass suppression, artwork colour and preferences."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
springboard = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
prefs = (root / "preferences/QRootListController.m").read_text(encoding="utf-8")

# Defaults: off, 1.5pt.
assert '@"playerBorderEnabled": @NO, @"playerBorderWidth": @1.5' in player

# Width: zero unless enabled and Aura's player glass is off; clamped to 0.5-4pt.
width_fn = player.split("static CGFloat QPlayerBorderWidth(NSDictionary *settings) {", 1)[1].split("\n}", 1)[0]
assert '![settings[@"playerBorderEnabled"] boolValue] || [settings[@"auraPlayerGlass"] boolValue]) return 0;' in width_fn
assert "MIN(4, MAX(0.5, width))" in width_fn
apply = player.split("- (void)applySettings:(NSDictionary *)settings {", 1)[1].split("\n}", 1)[0]
assert "self.layer.borderWidth = QPlayerBorderWidth(settings);" in apply

# Colour: the text accent picked from the artwork, refreshed with every accent update.
accent = player.split("- (void)updateAccent {", 1)[1].split("\n}", 1)[0]
assert "self.layer.borderColor = textAccent.CGColor;" in accent

# Aura glass, outside MediaRemoteUI: Aura's own master switch and playerGlass preference.
assert 'settings[@"auraPlayerGlass"] = @([aura[@"masterEnabled"] ?: @YES boolValue] && [aura[@"playerGlass"] boolValue]);' in player
# Inside MediaRemoteUI: Aura's component state (marker 0x5143, bit 0 master, bit 7 player glass), as Aura reads it.
assert 'notify_register_check("com.gushi.aura/components", &auraToken)' in player
assert "(auraState & 0xffff0000ULL) == 0x51430000ULL" in player
assert "@((auraState & 1ULL) && (auraState & (1ULL << 7)))" in player


# Border channel: every writer encodes what MediaRemoteUI decodes.
def encode(enabled, width):
    width = max(0.5, min(4, width))
    return 0x51720000 | (0x8000 if enabled else 0) | round(width * 100)


def decode(state):
    assert state & 0xFFFF0000 == 0x51720000
    return bool(state & 0x8000), (state & 0x7FFF) / 100


for enabled in (False, True):
    for width in (0.5, 1.0, 1.5, 2.5, 4.0, 9.0, 0.1):
        assert decode(encode(enabled, width)) == (enabled, max(0.5, min(4, width)))
writer = "0x51720000ULL | ([{}[@\"playerBorderEnabled\"] boolValue] ? 0x8000ULL : 0) |"
assert writer.format("qSettings") in springboard and writer.format("settings") in prefs
assert 'notify_register_check("com.gushi.quart17/playerborder", &borderToken)' in prefs
# SpringBoard keeps its token open so the state survives until MediaRemoteUI registers after a respring.
assert 'notify_register_check("com.gushi.quart17/playerborder", &qBorderStateToken)' in springboard
for source in (springboard, prefs):
    assert "MAX(0.5, MIN(4, width))" in source and "(uint64_t)llround(width * 100)" in source
assert '(border & 0xffff0000ULL) == 0x51720000ULL' in player
assert 'settings[@"playerBorderEnabled"] = @((border & 0x8000ULL) != 0);' in player
assert 'settings[@"playerBorderWidth"] = @((border & 0x7fffULL) / 100.0);' in player
# SpringBoard writes the state before telling MediaRemoteUI to re-read.
load = springboard.split("static void QLoadSettings(void) {", 1)[1].split("static void QChanged(", 1)[0]
assert load.index("com.gushi.quart17/playerborder") < load.index('notify_post("com.gushi.quart17/playercornerchanged")')

# Preferences: switch + half-point slider matching the clamp, translated.
items = plistlib.loads((root / "preferences/Resources/PSettings.plist").read_bytes())["items"]
switch = next(i for i in items if i.get("key") == "playerBorderEnabled")
slider = next(i for i in items if i.get("key") == "playerBorderWidth")
assert switch["cell"] == "PSSwitchCell" and switch["default"] is False
assert slider["cellClass"] == "QWidthSliderCell" and slider["unit"] == "halfPt"
assert (slider["min"], slider["max"], slider["default"]) == (0.5, 4.0, 1.5)
assert items.index(switch) < items.index(slider)
assert '[specifier.properties[@"unit"] isEqualToString:@"halfPt"]' in prefs and '"%.1f pt"' in prefs
assert re.search(r'isEqualToString:@"halfPt"\] \? 0\.5 : 0\.01', prefs)
for zh, en in (("播放器描边", "Player border"), ("描边粗细", "Border width"), ("描边", "Border")):
    assert f'@"{zh}": @"{en}"' in prefs, zh
print("PASS: border defaults, Aura glass suppression, artwork colour, cross-process encoding and preferences")
