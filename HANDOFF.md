# Quart17 交接记录

## 1.0.70（已投真机 iphone-15-pro-max，taildrop rc=0）

- 包：`com.gushi.quart17_1.0.70_iphoneos-arm64e.deb`（920346 B）
- SHA256：`e6ed1e04a14ab88e5edae6847e903bb728199a05d8f5c80d09a1ff190954660b`
- 相对 1.0.69 的两处改动：
  1. 新增 hook `NCNotificationListView -_heightForFeaturedLeadingView`（乘 s + `QMarkRowScaled`）——实时活动 / 正在播放那一项的行槽之前走的是这条通道、没被接上，保持原生高度，周围多出约 10% 空白（90% 下实测：行槽 167.00、渲染 149.56）。标记列表是为了让 cell 侧照 cellFrame/s 把 contentView 的 bounds 还原成原生，避免 s²。
  2. `layoutOffsetForViewAtIndex:` 的量测日志改为每个索引只记一次——之前它占 1025/1038 行，把有用读数挤出了轮转。
- 未在模拟器验证（模拟器渲染不出实时活动：手搓 widget 扩展被 chronod 判 `ActivityError.widgetDescriptorNotFound`，foundDescriptors 为空），只能真机看 `featuredH` 读数行。
- 已验读数（真机 1.0.69 日志，用户设置 90%）：卡片 0.896 / 实时活动 0.896（167.00 -> 149.56，360.02 宽）/ Quart17 播放器 playerH=88.00（无 s²）→ 渲染 78.8；通知中心行高 43.9->34.42、分组标题行 56.00->43.90、标题 89.1x26.7、清除按钮 39.7x26.9（模拟器 78.4% 下）。

## 1.0.71（已投真机，taildrop rc=0）—— 纯读数额调整，零行为变更

- 包：`com.gushi.quart17_1.0.71_iphoneos-arm64e.deb`（920662 B）
- SHA256：`bc16e4499cef6cb0e9ce89d992f08dc6ad822da77e426e19f04203b2dd129e71`
- 改动：
  1. **删除** 1.0.70 加的 `NCNotificationListView -_heightForFeaturedLeadingView` hook。真机 1.0.70 日志里 `featuredH` 读数行 **0 条** → 该方法从不被调用，实时活动/正在播放不走这条通道。删它 = 零行为变更（它从未触发），但不该留一条未经验证的缩放路径。
  2. `geom` / `cellLayout` 读数改为**只在落定态记**（`rowsScaled=1`，或该 cell 已排 12 次），并加 `cls=`（cell 类名）、`settled=`、`cellH=`（bounds 高度）字段。
     - 起因：`geom` 原先在**每次** cell 布局后记一次，会记到"数据源缩行高之前"那一版 → `rowH` 是原生值。1.0.69 那份日志里 `rowH=167.00 visH=149.56` 就是这么读到的，据此得出的"实时活动周围多 10% 空白"**结论作废**（行槽可能本来就是缩过的）。
  3. 新增 `NCNotificationMasterList -notificationListView:heightForItemAtIndex:withWidth:` **只记不改**（`heightForItem[Master]` 读数行）：确认实时活动所在的补充视图容器，其行槽是否走这条数据源回调。没有读数之前不在这一层乘 s——顶层容器缩第二次正是过去看门狗崩溃的同源问题。
- 1.0.71 已验读数（1.0.70 日志，用户设置 90%/widthScale 0.8956）：
  - 卡片：`cachedHeight h=67.67 leading=1` → `heightForItem[GroupList] h=67.67 -> 60.60`（0.8956）→ `geom rowH=67.67 visH=60.60 visW=360.02 tf=0.896 sub=NCDimmableView[67.67]` → 行槽与视觉尺寸同系数，卡片正好铺满行槽。
  - 实时活动：`geom rowH=125.00 visH=111.95 visW=360.02 tf=0.896 sub=NCNotificationListSupplementaryHostingView[125.00]` → 宽 402×0.8956、高 125×0.896，与卡片同系数。
  - 播放器：`player platterH=167.00 platterW=402.00 playerH=88.00 s=0.90` → 播放器拿到原生设计高 88（sizeFactor=1），无 s²。
  - 通知中心标题行：`ncHeader h=41.17 w=402.00 subs=NCNotificationListHeaderTitleView[90.8x27.2] NCToggleControl[43.6x30.7]`。
  - 分组折叠行：`grpHeaderH native=51.33 -> 45.97 s=0.90`。
  - `layoutOffset` 只 2 行（1.0.70 的日志瘦身生效；1.0.69 是 1025 行刷屏）。
- 仍待钉死的一项：实时活动所在行的**槽高**是否也按 s 缩（1.0.71 的 `geom ... rowH/cellH` 与 `heightForItem[Master]` 读数可判）。

## 1.0.72（已构建校验，**未投递**：手机 Tailscale offline）—— 修真 bug：实时活动/播放器被放大回 100%

- 包：`C:\db\Quart17\com.gushi.quart17_1.0.72_iphoneos-arm64e.deb`（921240 B）
- SHA256：`73e73402923c5b78bd3f14a89f560b47e1c16a177a2ff173a0f24a135a98bdd8`
- 崩溃自检 PASS；包内确认：`rowScaled=%d` 4 处、`layoutView idx=` 2 处、`heightForItem[Master]` 与 `featuredH native` 各 0 处。
- **根因（1.0.71 日志钉死）**：`contentView.bounds = cellBounds/s` 的还原逻辑原先按**列表级**布尔 `QListRowsAreScaled` 判断 —— 同列表里只要有一行（普通卡片）缩过，实时活动那一类**行高不经数据源回调**的 cell 也会被判定成"行高已缩"，于是内容被除以 s 放大回 186.47，再被 transform 缩回 167：
  - 卡片：`geom rowH=60.60 cellH=60.60 visH=60.60 visW=360.02` → 402×0.8956、67.67×0.8956 ✓
  - 实时活动：`geom rowH=167.00 cellH=167.00 visH=167.00 visW=402.00`、`cellLayout rowsScaled=0 anchorH=186.47` → **渲染 100%** ✗
  - 播放器：`player platterH=167 platterW=402 playerH=88` → 同样 100% ✗（它在那个容器里）
- **修法**：新增 `QRecordScaledRowHeight` / `QCellRowWasScaled` —— 数据源缩过的行高值记进列表上的集合，还原改成"**这一行自己的高度**能在集合里匹配到（±0.75pt）才执行"，列表级布尔只作为快速前置判断。
- 同时删除 `[Master] heightForItemAtIndex:` 读数（实测全是 `h=0.00`，无用）；新增**只记不改**的 `NCNotificationListView -_layoutViewIfNecessaryAtIndex:layoutOffset:startingLayoutOffset:` 读数（`layoutView idx/offset/->`），用于反推实时活动那一行的实际槽高来源 —— 这是最后一项未定性的读数（它不经过任何数据源回调，`_heightForFeaturedLeadingView` 也从不触发）。
- 待投递：手机上线后重跑
  `"/c/Program Files/Tailscale/tailscale.exe" file cp C:/db/Quart17/com.gushi.quart17_1.0.72_iphoneos-arm64e.deb iphone-15-pro-max:`

## 1.0.73（已投真机，taildrop rc=0）—— 缩放层搬到最外层列表容器，修左滑错位

- 包：`C:\db\Quart17\com.gushi.quart17_1.0.73_iphoneos-arm64e.deb`（919964 B）
- SHA256：`5ba6d85aca3a85143244ad84c67fceac41f5e97c10f85bce46d9e1d6caf9f498`
- **真机故障（用户报告）**：轻轻左滑一次会跑偏；通知条左滑删除按钮出现在卡片底部。
  - **根因**：旧方案把 cell 留成全宽（402pt），只把卡片内容用 contentView 的 transform 缩到 s
    （视觉 360pt）。系统的左滑动作按钮、手势提示位移、命中区域都是按 **cell 自己的尺寸** 算的
    → 按钮落在卡片右侧空白里（横向差 (1-s)×宽 ≈ 21~42pt）、高度取自我还原过的 contentView（比
    cell 高 1/s ≈ +7.7pt@90%/+21pt@78%）→ 挂在卡片下方。调参无解，是几何不一致的必然结果。
- **新结构**：transform 从"每个 cell 的 contentView"上移到 **最外层 `NCNotificationListView`**
  （`QOutermostListContainer`，祖先里没有别的 NCNotificationListView 的那个）。
  - cell 自身就是 s 倍宽 → 左滑动作按钮 / 手势 / 命中区域与渲染同一套几何 ✓
  - 行距、分组标题行、「通知中心」标题与叉号、实时活动、Quart17 播放器全部在容器坐标系内，
    自动同系数（"间距也一起缩"达成）✓
  - **不再修改任何视图的 bounds** → 旧方案里"还原 contentView + 在布局过程中重排子树"整套删除
    （那正是看门狗崩溃的来源），崩溃面变小 ✓
  - `QCanOwnTransform` 只接管 identity 或我们自己设过的 transform，系统在用的（非 identity）不碰；
    接管/未接管都会在日志里留痕。
- 同时停掉：数据源行高缩放（`heightForItemAtIndex:` 两个 hook 改回原生）、`_headerViewHeight`、
  `+headerHeightWithWidth:...`、头部叶子 `QScaleHeaderContents`、`toggleControlPair`。
  这些辅助函数用 `__attribute__((unused))` 标记保留（若新方案在真机上不成立，要能快速回退旧路径）。
- 验证方式说明：模拟器侧未能验证（未留存模拟器构建流程；且本机经 SSH 合成的手势事件被 macOS 拦下、
  设备休眠时 `simctl io screenshot` 报 `Error creating the image`）。本版依据 = 崩溃自检 PASS +
  代码审查 + 真机实测。
- 待真机确认：左滑是否对齐、删除按钮是否贴卡片右侧、卡片间距是否跟着缩；日志看
  `container cls=... frame=... tf=0.90` 与卡片/实时活动的 `geom`。

## 实验 A 失败并回撤（大封面展开态改由 Quart 自绘）
试过：artworkSide 解开 60pt 上限 + 展开不隐藏 Quart 封面/进度环 + 原生封面图 alpha=0（保留点击）。
结果：真机效果更差，用户要求回撤。源码已用 `_snapshots/preA_0924_235200/revert.sh` 逐字节还原，手机端回退到 2.2.2。
结论：展开态不适合从"隐藏自己、让系统显示"改成"自己画"——系统那层展开呈现（标签/按钮/布局）仍在，改单点不成立。

## 2.2.3（已投真机，taildrop rc=0）—— 修大封面展开后播放器退回原生

- 包：`com.gushi.quart17_2.2.3_iphoneos-arm64e.deb`（956,932 B）
- SHA256：`6ff7046b03eb9ee9951e54071a9379657f6f6c4b60f586897a084b07e3a11404`
- 改动：`Tweak.xm` 1 行（`!mediaPlatter` → `!mediaPlatter && !player`）
- **真机故障（用户报告）**：点击小封面弹出大封面后，锁屏底部播放器变回原生样式。
- **根因**：大封面展开时 MediaRemoteUI 拆除紧凑场景 → PLPlatterView 内的 `_UISceneLayerHostContainerView` 消失 → `layoutSubviews` 触发 → `QFind(self, @"_UISceneLayerHostContainerView")` 返回 nil → `mediaPlatter` 为 NO → 2.2.2 新增的 `!mediaPlatter` bailout 分支无条件执行，设 `self.layer.opacity = 1`，原生 platter 重新可见、Quart 播放器隐藏。
- **修法**：bailout 条件加 `&& !player`——若 PLPlatterView 已关联过 QPlayerView（确定是 Now Playing 宿主），即使场景容器暂时消失也不退回原生。Live Activity（从未创建 player）仍正常走 bailout。
