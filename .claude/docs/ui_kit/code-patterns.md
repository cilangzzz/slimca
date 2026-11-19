# ui_kit 编码模式 — 新增组件/Token 的标准步骤与约束规则

> 本模块的扩展面有三个：新增语义组件（最常见）、新增 token（较罕见，需先判断层级）、新增转场。
> 组件清单见 [api-components.md](api-components.md) / [api-transitions.md](api-transitions.md)。

## 一、新增一个标准语义组件（完整步骤）

以「新增 src/components/xxx.dart」为例，每一步都有既有组件作参照：

### 步骤 1：落位与命名

- 文件放 `lib/src/components/`（视觉组件）或 `lib/src/transitions/`（动画手段）；文件头 doc-comment 标注对应设计规范章节（如「UI-规范与重设计.md §4.2」）与职责边界（尤其写清**什么归宿主层**——参照 SlimcaConfirmCard 对「多行状态机归 feature_capture」的划界）。
- 类名 `Slimca` 前缀 + PascalCase（`SlimcaMenuTile`）；私有部件 `_` 前缀（`_MonthCell`、`_StripCell`）。

### 步骤 2：经 BuildContext 扩展读 token，零裸值

```dart
final SlimcaTheme tokens = context.slimca;      // 色彩
final MotionConfig motion = context.motion;     // 时长/弹簧/曲线
final SlimcaSpacing spacing = context.spacing;  // 间距（cardInner/inline/groupGap…按语义位取）
final SlimcaSizes sizes = context.sizes;        // 尺寸（minTouchTarget/radiusGroupCard…按用途取）
```

- 间距/尺寸按**语义位**取（`spacing.cardInner` 而非 `spacing.space150`），防错档；别名 xs/s/m/l/xl/xxl 也可用。
- 色彩只从 SlimcaTheme 语义字段或 `Theme.of(context).colorScheme` 派生槽位取；文字样式从 `textTheme` 派生后 copyWith 颜色。

### 步骤 3：参数设计

- 必填数据走构造参数；回调命名 `onXxx`（`onDaySelected` / `onExpandedChanged`）。
- **可注入的确定性参数**：涉及「今天」「周起始」的组件加 `DateTime? today` / `int? weekStart`（缺省取运行当天 / MaterialLocalizations）——测试注入固定值（calendar_test 的固定用法）。
- 受控/非受控双模式：可展开/可切换类组件用 `bool? xxx`（null=非受控内部自管）+ `ValueChanged<bool>? onXxxChanged`，受控同步时**不回发事件防环**（SlimcaCalendar.didUpdateWidget 口径）。
- 单一真值外移：日期选中态等业务状态不留组件内（日历组件族共同契约）。

### 步骤 4：动效接线（含 off 分支）

- 时长/曲线只从 motion 取语义位（`motion.durM` / `motion.sharedAxis` / `motion.curveEffectsStandard`），弹簧走 `motion.springSnappy.curve` / `.simulation`。
- **每个动画路径必须有 off 分支**：

```dart
if (motion.level == MotionLevel.off) {
  // 100ms 线性淡入淡出（fadeOff），无位移/无循环——pumpAndSettle 必须可收敛
}
```

- 曲线判定线：颜色/透明度动画 → `curveEffectsStandard`（禁过冲）；展开/进场 → `curveExpand`、收起/出场 → `curveCollapse`；页面级 → `curveStandard`；count-up → `curveEaseOutExpo`。
- 循环动画（呼吸/pulse）用 AnimationController.repeat(reverse) 并依赖 TickerMode 离屏自动暂停；在 `didUpdateWidget`/`didChangeDependencies` 里刷新启停（参照 SlimcaBreath._refresh）。
- 目标值变化的续播用 `TweenAnimationBuilder`（begin 仅作用首挂载）；静态子树经 `child` 参数透传只 build 一次；重绘区域包 `RepaintBoundary`。
- 纯几何量（上浮距离、位移幅度）不是动效 token——写成参数并注释「几何常量，非动效 token」（先例：`floatDistance`、共享轴 30/24/0.92）。

### 步骤 5：约束落地（命中/视觉/状态层/无障碍）

- 命中目标 ≥ `sizes.minTouchTarget`（48）；视觉尺寸另计（日格 40 视觉+48 命中，视觉-命中差即 M3「内边距 4px」口径）。
- 状态层用 on 色一次只叠一层（stateLayer 四档透明度）；按压反馈优先 InkWell 默认实现，不逐行调色。
- 无障碍：完整语义标签（`Semantics(label: formatFullDate(day))`）；纯装饰行 ExcludeSemantics（星期标签行）；图标按钮带 tooltip。

### 步骤 6：导出与测试

- barrel 登记一行：`lib/ui_kit.dart` 加 `export 'src/components/xxx.dart';`（分组注释放对应域段）。
- 测试放 `test/xxx_test.dart`：正常档断言 + **off 档 pumpAndSettle 收敛用例** + 手势/受控同步边界；涉及手势的用例注意拖拽首段位移并入 drag start 的口径（见 calendar_test 的多段短位移手法）。
- 验收：`flutter analyze` 0 issue；`flutter test packages/ui_kit` 全绿。

## 二、新增 Token 的层级判断

| 需求 | 落点 | 步骤 |
|------|------|------|
| 新颜色语义 | SlimcaTheme 字段 + `_fromPalette` 推导表 | 加字段 → copyWith/lerp/==/hashCode 四处同步 → 两 brightness 各定 tone → **勿动 light/dark 静态基线**（W1 零漂移）→ 视用途决定是否加入 kSlimcaAaPairSpecs 护栏清单 |
| 新动效参数 | MotionConfig | 加字段 → full/reduced/off 三预设给值（off 档一律线性化）→ copyWith/lerp/==/hashCode 同步 → 曲线不参与 scaled 缩放（时长才缩放） |
| 新间距档 | SlimcaSpacing | 只取 M3 官方刻度值；加 canonical 字段 + 别名/语义位 getter；lerp 用 lerpDouble |
| 新尺寸档 | SlimcaSizes | 官方刻度值或显式标注「推导值非规范原文」；int 字段 lerp 按 t≤0.5 取整防碎片高度 |
| 新转场 | src/transitions/ | 手段 = TweenAnimationBuilder/AnimatedSwitcher/PageRouteBuilder/createSimulation 之一；必接 token + off 分支；barrel 导出 |

ThemeExtension 契约四件套（copyWith / lerp / == / hashCode）缺一不可——lerp 用于主题 morph，==/hashCode 影响 AnimatedTheme 是否触发重建。

## 三、装配侧扩展模式

- **壳层接新主题源**：settings 流 → `ThemeProfile` → `toSlimcaTheme(brightness)` + `toMotionConfig()` → `buildTheme(...)` → 交给 `SlimcaThemeMorph`（AnimatedTheme 承担 300ms morph）。业务侧不自行装配 ThemeData。
- **接入平台动态色**：外包一层 `SlimcaDynamicColorBuilder(profile:, builder:, loader:)`；测试注入 Fake loader（真实平台通道禁止进单测）。
- **新内置主题包**：走 `_preset` 工厂（theme_presets.dart）——kcal/money 色相锚定 150/62 不动，只配 chroma 与 neutral 色相；id 以 `preset-` 前缀且稳定（随 theme_profiles 同步入库）。
- **新护栏关键对**：kSlimcaAaPairSpecs 加 SlimcaAaPairSpec（label/threshold/fg/bg/apply）；护栏只在装配出口（buildTheme/toSlimcaTheme/map）生效，审计入口 auditSlimcaAa 只读。

## 四、组件层约束规则清单（评审 checklist）

1. 禁裸色值/裸时长/裸曲线/裸间距/裸尺寸——只读四个 context 扩展 + ColorScheme/TextTheme。
2. 间距/尺寸按语义位取值，不按 canonical 数值硬挑档。
3. 颜色/透明度动画禁过冲曲线；进出场不对称（expand=进场 ease-out / collapse=出场 ease-in）。
4. 每个动画路径有 off 分支，时长 fadeOff=100ms、曲线线性。
5. 循环动画包 RepaintBoundary、依赖 TickerMode 暂停、静态子树走 child 缓存。
6. 命中 ≥48 / 视觉另计；相邻目标间距 ≥8（targetGap）。
7. 状态层一次只叠一层；按压反馈不逐行调色。
8. 「今天」/「周起始」/locale 相关取值可注入或走 MaterialLocalizations，不硬编码。
9. 业务状态（选中日等）单一真值外移，组件受控。
10. doc-comment 标注规范章节号与职责边界（宿主层分工写清）。
