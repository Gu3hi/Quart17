"""Check the source's date visibility transition and deferred widget geometry."""
from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / "springboard/Tweak.xm").read_text(encoding="utf-8")
style = source.split("static void QStyleLockClock(UIView *dateView) {", 1)[1].split(
    "static void QRestyleLockClockForWidget", 1)[0]
date = style.split("BOOL temporaryText =", 1)[1]
assignment = re.search(r"subtitleText.hidden = ([^;]+);", date).group(1)
assignment = assignment.replace("!", "not ")
for temporary in (False, True, True, False):
    native_hidden = eval(assignment, {"__builtins__": {}}, {"temporaryText": temporary})
    copied_date_hidden = temporary  # The attributed copy is clear during a temporary prompt.
    assert not (native_hidden and copied_date_hidden), "Both date representations became invisible"
    assert native_hidden == (not temporary)

position = source.split("static void QPositionLockWidget(", 1)[1].split(
    "static void QPositionLowerWidgets", 1)[0]
guard = re.search(r"if \(enabled && \((widget.bounds.size.width .*?)\)\) return;", position, re.S)
assert guard and guard.start() < position.index("if (!saved && enabled) {")
expression = guard.group(1).replace("||", "or")
names = ("widget.bounds.size.width", "widget.bounds.size.height",
         "widget.frame.size.width", "widget.frame.size.height")
for index, name in enumerate(names):
    expression = expression.replace(name, f"dimensions[{index}]")
expression = " ".join(expression.split())
for dimensions in ((0, 0, 0, 0), (0, 30, 0, 30), (430, 0, 430, 0), (430, 30, 430, 30)):
    deferred = eval(expression, {"__builtins__": {}}, {"dimensions": dimensions})
    assert deferred == any(value <= 0 for value in dimensions)
# The zero-size guard applies only while enabling; disabling always restores a saved baseline.
assert "if (enabled && (" in position
assert "hasBounds ? CGRectApplyAffineTransform(widget.bounds, nativeTransform).size : original.size" in position
assert position.index("CGSize nativeSize") < position.index("if (!enabled)")
assert "widget.transform = savedTransform.CGAffineTransformValue" in position
assert "widget.frame = saved.CGRectValue" in position
print("PASS: date/prompt visibility transitions, deferred geometry, and disable restoration")
