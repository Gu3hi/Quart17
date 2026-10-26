"""Exercise the production Darwin state encoding shared by the two player hosts."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
prefs = (root / "preferences/QRootListController.m").read_text(encoding="utf-8")
springboard = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
artwork = (root / "QNativeArtwork.m").read_text(encoding="utf-8")

encode = re.search(r"flags \|= \(uint64_t\)(.*);", prefs)[1]
encode = encode.replace("MIN", "min").replace("MAX", "max")
decode = re.search(r"NSUInteger style = (.*);", player)[1]
native_mask = re.search(r"\(state & (~\d+ULL)\) == (0x[0-9A-Fa-f]+)ULL", artwork)
assert native_mask
assert '((uint64_t)(MIN(2, MAX(0, [qSettings[@"progressStyle"] integerValue])) + 1) << 3)' in springboard
assert '(flags & ~4095ULL) == 0x51710000ULL' in player
assert 'if (style) settings[@"progressStyle"] = @(style - 1)' in player
for style in (-1, 0, 1, 2, 3):
    bits = eval(encode, {"__builtins__": {}, "min": min, "max": max}, dict(style=style))
    for enabled in range(8):
        flags = 0x51710000 | enabled | bits
        decoded = eval(decode, {"__builtins__": {}}, dict(flags=flags))
        assert decoded - 1 == min(2, max(0, style))
        assert flags & int(native_mask[1][1:-3]) == enabled | bits
        assert flags & ~int(native_mask[1][1:-3]) == int(native_mask[2], 16)
        assert flags & 7 == enabled
assert eval(decode, {"__builtins__": {}}, dict(flags=0x51710007)) == 0
assert 'settings[@"masterEnabled"] = @((flags & 1) != 0)' in player
assert 'settings[@"playerEnabled"] = @((flags & 2) != 0)' in player
assert 'settings[@"showProgress"] = @((flags & 4) != 0)' in player
print("PASS: all three styles, clamping, legacy state, enable flags and native artwork mask")

# Compare all publishers and the consumer, including every combination of switches.
keys = re.findall(r'NSArray \*keys = @\[([^\]]+)\]', prefs)[0]
assert keys in springboard and keys in player
assert len(re.findall(r'@"[^"]+"', keys)) == 6
assert 'flags |= 1ULL << 11' in prefs
assert 'flags | (1ULL << 11)' in springboard
assert 'if (flags & (1ULL << 11))' in player
publish = re.search(r'flags \|= (1ULL << \(i \+ 5\))', prefs)[1].replace('ULL', '')
assert publish.replace('1 <<', '1ULL <<') in springboard
consume = re.search(r'settings\[keys\[i\]\] = @\((.*)\);', player)[1].replace('ULL', '')
for switches in range(64):
    flags = 0x51710000 | (1 << 11) | (3 << 3) | 7
    for i in range(6):
        if switches & (1 << i):
            flags |= eval(publish, {"__builtins__": {}}, dict(i=i))
    assert flags & ~4095 == 0x51710000
    for i in range(6):
        assert eval(consume, {"__builtins__": {}}, dict(flags=flags, i=i)) == bool(switches & (1 << i))
assert 'settings[@"playerCornerRoundness"] = @((corner & 0xffffULL) / 10000.0)' in player
assert '(corner & 0xffffULL) <= 10000' in player
shrink = springboard.split('static CGFloat QShrinkScale(void) {', 1)[1].split('\n}', 1)[0]
assert '![qSettings[@"enabled"] boolValue]' in shrink
print("PASS: six switch round trips (64 combinations), legacy marker, corner channel and notification gate")
