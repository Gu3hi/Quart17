"""Regression contracts for native suppression and the actual pan geometry."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
compact = (root / "QCompactPlayer.m").read_text(encoding="utf-8")
events = json.loads((root / "tests/fixtures/native_slider_events.json").read_text())

# These are the actions registered by MRUNowPlayingTimeControlsView on iOS 17.3.1.
assert events["UIControlEventTouchDown"] == "sliderTouchDown:"
assert events["UIControlEventTouchUpInside"] == "sliderValueChanged:"
started = player.split("- (void)scrubStarted:", 1)[1].split("- (void)seekTapped:", 1)[0]
ended = player.split("- (void)scrubEnded:", 1)[1].split("- (void)updateProgressFill", 1)[0]
assert "if (self.scrubbing) return" in started and "self.scrubbing = YES" in started
assert "self.nativeTimeControls" in ended and "@selector(setElapsedTime:), self.seekTarget" in ended
assert "sendActionsForControlEvents" not in started + ended
assert '"native_commit_selector": "setElapsedTime:"' in (root / "tests/fixtures/native_slider_events.json").read_text()
priority = player.split("- (BOOL)acuis_wantsPriorityOverTargetOfGestureRecognizer:", 1)[1].split("- (void)scrubEnded:", 1)[0]
assert "return YES" in priority
assert "else if (QSetElapsed" in ended  # Native and MediaRemote commits must not race.
assert '[_progress addTarget:' not in player  # Pan cancellation must not end the scrub early.
assert '_progressPan.delegate = self' in player and 'seekPan.delegate = self' in player
assert player.count('initWithTarget:self action:@selector(seekPanned:)') == 2
assert "[view isKindOfClass:UIControl.class]" in player

pan = player.split("- (void)seekPanned:", 1)[1].split("static CGFloat QArtworkSeekFraction", 1)[0]
cancelled = pan.split("UIGestureRecognizerStateCancelled) {", 1)[1].split("return;", 1)[0]
assert "self.scrubbing = NO" in cancelled and "scrubEnded" not in cancelled
assert "[self scrubStarted:gesture]" in pan and "QPublishExpandedSeek(self.progress.value, YES)" in pan
expression = re.search(r"self\.progress\.value = (MIN\(1, MAX\(0, self\.dragStartProgress .*?);", pan, re.S)[1]
expression = " ".join(expression.replace("MIN", "min").replace("MAX", "max")
    .replace("self.dragStartProgress", "initial")
    .replace("([gesture translationInView:self].x - self.dragStartX)", "translation").split())
for width in (88, 320, 402, 430):
    span = max(1, width * 0.6)
    for initial in (0, 0.25, 0.75, 1):
        previous = -1
        for translation in (-2*width, -width/2, 0, width/2, 2*width):
            actual = eval(expression, {"__builtins__": {}, "min": min, "max": max}, dict(initial=initial, translation=translation, span=span))
            assert 0 <= actual <= 1 and actual >= previous
            if translation == 0:
                assert actual == initial
            previous = actual

fill = player.split("- (void)updateProgressFill {", 1)[1].split("- (void)layoutSubviews", 1)[0]
assert fill.index("setDisableActions:YES") < fill.index("self.backgroundProgress.frame =")
layout = compact.split("static void QCompactLayout(", 1)[1].split("static void (*qCompactOriginalDidMove)", 1)[0]
assert "QRestoreCompactContent" not in layout
assert "view.hidden = YES" in compact and "performWithoutAnimation" in compact
assert "@[@(view.alpha), @(view.hidden)]" in compact
print("PASS: native model seek commit, activity gesture priority, exclusive seek route, pan ownership, cancellation, bounded geometry, immediate fill and persistent native suppression")

# Evaluate the production initiation expression: accumulated motion tolerates diagonal starts.
begin = player.split("- (BOOL)gestureRecognizerShouldBegin:", 1)[1].split("- (BOOL)acuis_wants", 1)[0]
assert "translationInView:self" in begin and "velocityInView:self" not in begin
condition = re.search(r"return (fabs\(translation.x\).*?);", begin)[1]
condition = condition.replace("fabs", "abs").replace("translation.x", "x").replace("translation.y", "y")
for x, y, expected in [(12, 0, True), (-12, 0, True), (-12, 12, True),
                       (12, -18, True), (-12, -18, True), (3, 20, False),
                       (-3, -20, False), (0, 12, False), (0, 0, False)]:
    assert eval(condition, {"__builtins__": {}, "abs": abs}, dict(x=x, y=y)) == expected
print("PASS: both drag directions tolerate diagonal starts and retain vertical scrolling")
