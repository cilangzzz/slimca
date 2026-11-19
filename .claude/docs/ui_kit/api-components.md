# ui_kit 组件清单 — 语义组件（按组件域分组）

> 全部组件从 `package:ui_kit/ui_kit.dart` barrel 导出；内部实现只经 `context.slimca/motion/spacing/sizes` 取样式。
> 转场库另见 [api-transitions.md](api-transitions.md)；token 数值见 [data-model.md](data-model.md)。

## 1. 仪表盘域

### SlimcaCalorieRing（src/components/calorie_ring.dart）

今日热量环：单环 + 摄入弧 + 消耗内弧 + 超支红色段。环推进走 springSoft；`TweenAnimationBuilder` 目标变化时从当前值续播（份量滑杆联动）。

| 参数 | 说明 |
|------|------|
| kcalIn / kcalOut / budget | 三值必填；net=kcalIn−kcalOut，fraction=net/budget（钳 0-1.6，>1 部分走 danger 超支段） |
| size / strokeWidth | 缺省 160 / 12 |
| **sweepEntrance** | 关键变体：`true`（缺省）首挂载从 0 扫到目标（§9.3#4 sweep 填充）；`false` 首帧直达——仪表盘切日等「入场已有级联承担」的场景避免环二次 sweep |
| center | 环心内容插槽（净热量/「今日还能吃」） |

```dart
SlimcaCalorieRing(kcalIn: 1200, kcalOut: 400, budget: 2000,
    sweepEntrance: false, center: Text('800 kcal'));
```

## 2. 录入/确认域

### SlimcaConfirmCard（src/components/confirm_card.dart）

「先拍后改」确认卡容器。职责边界：只提供 surfaceCard 卡面 + 插槽级联入场（复用 SlimcaStaggerItem）；置信度点/热量环/金额 count-up 由业务插槽组装；多行状态机归 feature_capture（见 [../feature_capture/README.md](../feature_capture/README.md)）。

| 参数 | 说明 |
|------|------|
| slots | 内容插槽列表，按 index×cascadeInterval 级联上浮入场 |
| header / footer | 卡头（置信点+标题）/ 卡尾（确认/取消），静态在场不参与级联 |
| padding | 缺省 `SlimcaSpacing.space200`（16，卡内基线）——W17 起杜绝组件层裸间距 |
| cascade | `false` → 插槽直接在场（预览/降级） |
| floatDistance | 上浮距离 16（几何常量，小于卡片墙的 24） |

```dart
SlimcaConfirmCard(
  header: Row(children:[SlimcaConfidenceDot(confidence: .92), Text('已识别')]),
  slots: [ringRow, moneyRow, gridRow],
  footer: confirmButtons,
);
```

## 3. 日历域（W17 插曲 d6650f8 全新 API）

三个组件 + 一个内部工具（calendar_utils.dart **不进公开 API**）。共同契约：
**选中日单一真值归宿主 provider**（三个组件都不维护日期选中态）；`today` / `weekStart` 可注入保证测试确定性；日期算术在 UTC 域、展示回调在本地 y/m/d 日界（详见 [pitfalls.md](pitfalls.md) 第 6 条）。

### SlimcaCalendar（组合容器，src/components/calendar.dart）

周条 + 垂直手势展开月网格的高度形变容器（形变式，淘汰 modal 弹窗）。两轴手势分工：水平=切日/翻周/翻月（token 不变），垂直=展开/收起（durL 280ms + curveExpand/curveCollapse 曲线对；透明度交叉淡化走 curveEffectsStandard）。

| 参数 | 说明 |
|------|------|
| selectedDate / onDaySelected | 选中日真值与回调（周条/月网格共用） |
| recordCounts | 有记录日→条数（月格 Compact 色点） |
| onWeekChanged | 折叠态翻周回调（宿主「今天」pill 浮现用） |
| **expanded / onExpandedChanged** | 受控开关：null=非受控内部自管；非 null=宿主持有（如首页「月历」图标展开）。受控变更不回发事件防环 |
| today / weekStart | 测试注入；weekStart 1-7（DateTime.weekday 口径），缺省取 MaterialLocalizations |

高度形变几何全部 token 推导：折叠 72（weekStripHeight）→ 展开 48+40+48×6=376。拖拽跟手，松手按速度（fling）/过半判定补间；手势 arena 被拒绝时只在真实拖拽中回当前态且不回发事件。

### SlimcaCalendarStrip（无限周条 v2，src/components/calendar_strip.dart）

PageView 无限双向翻周（双向各 5000 周 ≈ ±96 年）。关键手势语义：**横滑=翻周不切日**（与卡片墙切日手势解耦），**点格=切日**。外部选中日切到别的周时自动以 SharedAxis token（durL+curveStandard）锚定回目标周（今日锚定簇）。视觉：选中日=primaryContainer 填充、今天=primary 文字+4dp 今日点；选中态变色 durM+curveEffectsStandard。

### SlimcaMonthGrid（月网格，src/components/month_grid.dart）

受控 `month`；头部行 `[‹] 月份文案 [›] [今天]`（locale 驱动）+ `headerTrailing` 附加件（组合容器注入「收起」箭头）。翻月=水平拖或箭头 → `onMonthChanged(目标月首日)`，网格经 SlimcaSharedAxisSwitcher 切换。日格：视觉 40（dayCellVisual）/ 命中 48（minTouchTarget）；状态色：今天=primary、选中=primaryContainer 覆盖今日、域外日=onSurfaceMuted；有记录日 ≤3 个 secondaryContainer 色点+溢出空心环；星期标签行 ExcludeSemantics（不可聚焦）。

```dart
SlimcaCalendar(
  selectedDate: ref.watch(selectedDateProvider),
  onDaySelected: ref.read(selectedDateProvider.notifier).select,
  recordCounts: counts,
  expanded: expanded, onExpandedChanged: (v) => state = v,
);
```

## 4. 菜单域（W17 插曲重设计）

规格（§4.2 定稿）：行高 56/72（不用 dense）、leading 图标 24 视觉包 48 命中容器、tile 水平 12（cardInner）、标题 Title Medium、副标题 onSurfaceMuted、按压=InkWell 默认 state layer（不逐行调色）、分组卡圆角 12（radiusGroupCard）+ surfaceCard。

| 组件 | 用途 | 关键参数 |
|------|------|------|
| SlimcaMenuGroup | 分组卡（可选分组头 + ClipRRect 卡体，涟漪不出卡） | `header`（null=无头）/ `tiles`（行组件列表） |
| SlimcaMenuTile | 标准行 | `title` / `subtitle`（传则升 72 两行档）/ `leading` / `trailing`（状态类宿主自传 Switch/pill）/ `showChevron`（导航类渲染 24dp chevron）/ **`destructive`**（danger 红字危险项；宿主需配独立分组+具体动词确认弹窗）/ `onTap` |
| SlimcaMenuPill | 一行小字状态 pill（如 Pro 状态） | `label`；surfaceMuted 底+onSurfaceMuted 字；显隐逻辑归宿主 |

组间 24 / 页边 24（space300）由宿主页面用 SlimcaSpacing 排布，组内行间 0（行高自撑）。

## 5. 主题编辑域

### ThemeEditorPanel（src/components/theme_editor_panel.dart，W16，738 行）

主题编辑器面板（路由 /settings/theme 容器变换进入）。能力与参数：

| 参数 | 说明 |
|------|------|
| initial | 初始草稿（内置包或已有自定义 ThemeProfile） |
| onChanged | 每次滑杆/选色/命名改动回调（宿主实时换肤/草稿持久化） |
| onSave | 保存回调——**AA 全达标且包名非空才可达**（按钮禁用态表达，红字提示呈现失败对数） |
| showPreview | 仪表盘微缩预览开关 |

内部结构：
- AA 反馈条：主体=生效 token（护栏兜底后）逐对实测；原始草稿被自动降级的对数以提示条呈现（§8.3 透明化）。审计入口 `auditSlimcaAa` 只读、`enforceAa:false` 分支取草稿真实对比度。
- 四通道种子取色（热量/金额/危险/中性）：预设 chips + 色相/饱和度/浅深明度滑杆；kcal/money **lockedHue 锁定 150°/62°** 只开放饱和度明度；浅/深共享色相饱和度、明度各自独立。
- 四滑杆：圆角 0-2 / 密度 0.8-1.2 / 字重 0.85-1.3 / 动效强度 0.6-1.5（量程常量见 ThemeProfile/MotionConfig）+ MotionLevel 三段选择（关/减弱/完整）。
- 实时预览 `_MiniDashboardPreview`：草稿生效 token 装配独立 Theme（所见即装配所得），静态样本值。
- **不直接触库**：入库 theme_profiles 由宿主层经 outbox 同步（§5.6⑳）。

## 组件域与消费方对照

| 域 | 主要消费方 | 搭配转场 |
|------|------|------|
| 仪表盘 | feature_dashboard | SlimcaStaggerItem / SlimcaSharedAxisSwitcher |
| 录入/确认 | feature_capture | SlimcaBreath / SlimcaCountUp / SlimcaMoneyCountUp / SlimcaConfidenceDot / SlimcaHero |
| 日历 | feature_dashboard | SlimcaSharedAxisSwitcher（翻月） |
| 菜单 | apps/mobile 设置页 | — |
| 主题编辑 | apps/mobile 设置流 | SlimcaThemeMorph / SlimcaDynamicColorBuilder |
