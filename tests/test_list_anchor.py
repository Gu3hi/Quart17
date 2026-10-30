"""Top-anchored notification list: scope, request preservation, restoration and settings wiring."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
source = (root / "springboard/Tweak.xm").read_text(encoding="utf-8")
player = (root / "QPlayerView.m").read_text(encoding="utf-8")
prefs = (root / "preferences/QRootListController.m").read_text(encoding="utf-8")

scope = source.split("static BOOL QIsCoverSheetRootList(", 1)[1].split("static BOOL QListAnchoredToTop(", 1)[0]
gate = source.split("static BOOL QListAnchorEnabled(", 1)[1].split("static id QListResponder(", 1)[0]
collapsed = source.split("static BOOL QListCollapsed(", 1)[1].split("static BOOL QListAnchoredToTop(", 1)[0]
anchored = source.split("static BOOL QListAnchoredToTop(", 1)[1].split("static CGFloat QCoverSheetContentBottom(", 1)[0]
apply = source.split("static void QApplyListAnchor(UIView *list) {", 1)[1].split("static void QScheduleListScaling(", 1)[0]
group = source.split("%group QScale", 1)[1].split("%end\n%end", 1)[0]
hook = group.split("%hook NCNotificationListView", 1)[1]

# Only the root cover-sheet list moves; nested stack lists and other windows are untouched.
assert 'isEqualToString:@"NCNotificationListView"]) return NO;' in scope
assert 'QHasAncestor(list, @"CSCoverSheetViewBase")' in scope and "!list.window" in scope
assert '[qSettings[@"masterEnabled"] boolValue]' in gate and '[qSettings[@"notificationsFromTop"] boolValue]' in gate

# Collapsed states stay native: the folded stack at the bottom and the hidden count. Only the expanded list anchors.
assert "QListAnchorEnabled(list) && !QListCollapsed(list)" in anchored
assert "@selector(notificationListHidden)" in collapsed
for sel in ("masterList", "incomingSectionList", "isSectionListCurrentlyGroupedWithContentShown",
            "isSectionListViewGroupedWithContentShown"):
    assert f"@selector({sel})" in collapsed, sel
assert "respondsToSelector:selector" in source.split("static BOOL QSend(", 1)[1].split("}", 1)[0]
# Folding keeps the measured edge (only turning the option off drops it), and transitions re-apply at once.
assert "if (!QListAnchorEnabled(list))\n            objc_setAssociatedObject(list, QListAnchorBottomKey, nil" in source
section = source.split("%hook NCNotificationStructuredSectionList", 1)[1].split("%end", 1)[0]
assert "setSectionListViewGroupedWithContentShown:(BOOL)grouped" in section and "QApplyListAnchor(list)" in section
hidden_hook = source.split("- (void)_setNotificationListHidden:(BOOL)hidden forReason:(id)reason {", 1)[1].split("}", 1)[0]
assert "QApplyListAnchor(list)" in hidden_hook

# The system's request is kept and restored exactly when the option is turned off.
setter = hook.split("- (void)setLayoutFromBottom:(BOOL)layoutFromBottom {", 1)[1].split("- (void)", 1)[0]
assert "QListRequestedFromBottomKey, @(layoutFromBottom)" in setter and "%orig(NO)" in setter
assert "if (!QListAnchoredToTop((UIView *)self)) {\n        %orig;\n        return;" in setter
assert "[list setLayoutFromBottom:requested.boolValue]" in apply
assert "QListRequestedFromBottomKey, nil" in apply
assert "respondsToSelector:@selector(setLayoutFromBottom:)" in apply
for event in ("didMoveToWindow", "layoutSubviews"):
    assert "QApplyListAnchor((UIView *)self)" in hook.split("- (void)" + event, 1)[1].split("%end", 1)[0], event

# The top inset follows the visible widgets/date/clock and only ever moves the list up.
inset = source.split("static CGFloat QAnchoredTopInset(", 1)[1].split("static UIViewController *QCombinedListController(", 1)[0]
assert "MIN(nativeTop, bottom.doubleValue - 8)" in inset and "if (!bottom) return nativeTop;" in inset
# No live measurement in the inset path: scrolling moves the widgets and would feed back into the inset.
assert "QCoverSheetContentBottom" not in inset
rest = source.split("static BOOL QListAtRest(", 1)[1].split("static UIViewController *QCombinedListController(", 1)[0]
for flag in ("!scroll.tracking", "!scroll.dragging", "!scroll.decelerating", "scroll.contentOffset.y + scroll.contentInset.top"):
    assert flag in rest, flag
assert "if (QListAtRest(scroll) && now - last.doubleValue > 0.5)" in apply
assert apply.index("QListAtRest(scroll)") < apply.index("QCoverSheetContentBottom(list)")
assert "QListAnchorBottomKey, nil" in apply
bottom = source.split("static CGFloat QCoverSheetContentBottom(", 1)[1].split("static UIView *QCoverSheetRootListIn(", 1)[0]
for name in ("CSProminentEmptyElementView", "CSProminentSubtitleDateView", "CSProminentTimeView", "QLockClockLabelKey"):
    assert name in bottom, name
combined = source.split("%hook CSCombinedListViewController", 1)[1].split("%end", 1)[0]
assert "- (UIEdgeInsets)_listViewDefaultContentInsets" in combined
assert "QListAnchoredToTop(list)) insets.top = QAnchoredTopInset(list, insets.top)" in combined
# Re-inset is rate limited, skipped while the user scrolls, and also runs when the option is turned off.
refresh = source.split("static void QRefreshListInsets(", 1)[1].split("static void QApplyListAnchor(", 1)[0]
assert "!scroll.tracking && !scroll.decelerating" in refresh

# Measurement only while the date view rests in place, visible rows only, no descent into hidden subtrees.
assert "!CGAffineTransformIsIdentity(dateView.transform) || fabs(dateView.frame.origin.y) > 0.5) return NAN;" in bottom
# Descend past zero-alpha containers (the widget row lives under one); stop only at hidden subtrees.
assert bottom.index("if (node.hidden) continue;") < bottom.index("[queue addObjectsFromArray:node.subviews]")
assert bottom.index("[queue addObjectsFromArray:node.subviews]") < bottom.index("if (node.alpha < 0.01 || CGRectIsEmpty(node.bounds)) continue;")
assert "fabs(cached.doubleValue - bottom) > 1" in apply

# Header push: scaled only upward and only when anchored, so it is fully gone at the system's
# "date hidden" resting offset; native layout and pull-down stretch keep the system's own values.
push = source.split("static CGPoint QAnchoredDateOffset(", 1)[1].split("static void QRefreshListInsets(", 1)[0]
assert "offset.y <= 0" in push and "!QListAnchoredToTop(list)" in push
assert "defaultRestingOffsetExcludingAdjunct" in push and "contentInset.top" in push
assert "MAX(1, (bottom.doubleValue + 12) / hiddenPush)" in push
cover = source.split("%hook CSCoverSheetView", 1)[1].split("%end", 1)[0]
assert "%orig(QAnchoredDateOffset((UIView *)self, offset), scale);" in cover
assert "%orig(QAnchoredDateOffset((UIView *)self, offset));" in cover

# Small clock: the bottom widget row is re-positioned even while faded out by a scroll push.
clock = source.split("static void QStyleLockClock(UIView *dateView) {", 1)[1].split("static void QRestyleLockClockForWidget", 1)[0]
assert 'isEqualToString:@"CSProminentEmptyElementView"] && !node.hidden) {' in clock
assert "else if (node.bounds.size.height >= 60) bottomWidgets = node;" in clock
frame_hook = source.split("%hook CSProminentEmptyElementView", 1)[1].split("%end", 1)[0]
# The deferred retry is coalesced and rate limited, so a frame tug-of-war cannot spin the main thread.
assert "dispatch_async" not in frame_hook
assert "if (qLockClockRetryPending || now - qLockClockRetryAt < 0.3) return;" in frame_hook
assert frame_hook.index("qLockClockRetryPending = YES;") < frame_hook.index("dispatch_after(")
assert "qLockClockRetryPending = NO;" in frame_hook and "QRestyleLockClockForWidget(weakSelf);" in frame_hook

# Switching between the native stack and the anchored list always re-insets (deferred, coalesced), so an
# expanded list never keeps the native resting offset (which reads as a pull-down and drops the clock).
flip = apply.split("if (list.layoutFromBottom) {", 1)[1].split("}", 1)[0]
assert "QScheduleListInsetRefresh(list);" in flip
assert "QScheduleListInsetRefresh(list);\n    }\n}" in apply
schedule = source.split("static void QScheduleListInsetRefresh(", 1)[1].split("static void QApplyListAnchor(", 1)[0]
assert "objc_getAssociatedObject(list, QListInsetPendingKey)) return;" in schedule
assert "dispatch_async(dispatch_get_main_queue()" in schedule and "QRefreshListInsets(strongList);" in schedule

# Settings reach the live list without a respring, and default to the native layout.
changed = source.split("static void QChanged(", 1)[1].split("static void QLaunchPlayingBundle", 1)[0]
assert "QApplyListAnchor(list);" in changed
assert '@"notificationsFromTop": @NO' in player
items = plistlib.loads((root / "preferences/Resources/NSettings.plist").read_bytes())["items"]
switch = next(i for i in items if i.get("key") == "notificationsFromTop")
assert switch["cell"] == "PSSwitchCell" and switch["default"] is False
assert '@"通知从顶部开始": @"Start notifications at top"' in prefs
assert '@"notificationsFromTop": @"arrow.up.to.line"' in prefs
print("PASS: root-list scope, preserved system request, restoration, live settings and preference wiring")
