# ui_kit 坑点清单

> 按跨模块影响排序。API 表面见 [api-components.md](api-components.md) / [api-transitions.md](api-transitions.md)；变更历史见 [CHANGELOG.md](CHANGELOG.md)。

## 1. 禁裸 magic number（最硬的全局禁令，§8.2 第 3 层）

组件层只允许从 `context.slimca / motion / spacing / sizes` + ColorScheme/TextTheme 取样式；**裸色值/裸时长/裸曲线/裸间距/裸尺寸都是违规**。判定细则：

- 已知的合法例外是「几何常量」——上浮距离（floatDistance 24/16）、共享轴位移（30/24/0.92）、呼吸幅度（0.04）等。惯例是**写成构造参数或 static const 并在注释里标明「几何常量，非动效 token」**；新代码照此标注，否则评审按裸值打回。
- 间距按语义位取（`spacing.cardInner`），不要按数值反挑档（`space150`）；「够用原则」space250/space600 仅按 canonical 名取用。
- 跨模块后果：上层包绕过 token 写 magic number 会导致换肤/深浅色/AA 降级全部失效——降级后的 token 值**不会**同步到裸值处。

## 2. MotionLevel=off 是全库硬纪律，违反 = 测试永挂

每个动画路径必须显式 off 分支：时长 `motion.fadeOff`（100ms）、曲线线性、循环动画停转静置、弹簧路由经 `createSimulation` 返回 null。测试用 `pumpAndSettle` 驱动 widget 树，任何缺 off 分支的动画（尤其无限循环）会让 off 档测试永挂。新增转场时对照 [api-transitions.md](api-transitions.md) 第 4 节的降级口径表逐项补齐。

## 3. 曲线判定线：effects 禁过冲 / spatial 可过冲 + 进出场不对称

- **颜色/透明度类动画一律 `curveEffectsStandard`** `Cubic(0.34,0.80,0.34,1.00)`——effects 禁过冲是官方判定线的实现载体；位移/形变类才可用 curveExpand/curveCollapse。
- 展开/进场段 = `curveExpand`（emphasized-decelerate）、收起/出场段 = `curveCollapse`（emphasized-accelerate）——不对称纪律以 Tween 端点 + 方向曲线实现（SlimcaCalendar._settleTo 是范本）。
- 曲线不随 motionScale 滑杆缩放（缩放只作用时长/弹簧），off 档全部线性化——写 `scaled` 或新预设时勿把曲线纳入缩放。

## 4. AA 护栏只在装配出口，light/dark 基线是零漂移锚点

- `SlimcaTheme.light/dark` 静态基线 **不含** WCAG AA 护栏（W1 已知口径：部分外延 tone 不达 AA），这是有意的零漂移承诺——与壳层复刻表逐值相等，是 W16 测试锚点。**不要往 `fromPalette` 里加护栏**，否则基线漂移。
- 护栏降级只发生在三个装配出口：`buildTheme` / `ThemeProfile.toSlimcaTheme` / `SlimcaDynamicThemeMapper.map`。任何自行装配 ThemeData（绕过 buildTheme）的代码都不会有 AA 兜底。
- 主题编辑器展示「草稿真实对比度」要用 `toSlimcaTheme(brightness, enforceAa: false)`，否则审计的是降级后的假值。

## 5. W17 UX 插曲 d6650f8 的破坏性改动（2026-11-18，本模块最近一次 HIGH 风险变更）

- **日历组件族全量替换**：旧固定七天周条被三组件体系取代——`SlimcaCalendarStrip` v2 是 PageView 无限翻周，**横滑=翻周不切日**（与卡片墙切日手势解耦）；点格=切日；选中日真值归宿主 provider。宿主若仍按旧口径「横滑切日」接线会双重语义打架。
- **菜单页 API 全新**：`SlimcaMenuGroup / SlimcaMenuTile / SlimcaMenuPill`；设置页行组件从 SwitchListTile 口径改为自定义 Tile（photo_burn_setting_test 因此改用 Switch 断言）。
- **MotionConfig 构造签名新增 3 个必填曲线参数**（curveExpand/curveCollapse/curveEffectsStandard）——直接 `MotionConfig(...)` 手工构造（而非走 forLevel/三预设）的外部代码会编译失败。
- **SlimcaConfirmCard 缺省 padding 改引 SlimcaSpacing.space200**（数值同为 16，视觉不变但来源变了）。
- **SlimcaStaggerItem 收尾曲线改 curveExpand**（原直线重映射）——级联进场观感变化。
- 同提交 16 个文件 +2601/-7，波及 apps/mobile（8 文件）与 feature_dashboard（9 文件）；回滚指南见 [CHANGELOG.md](CHANGELOG.md) 该条目。

## 6. 日历日期算术的时区纪律（UTC 域 vs 本地日界）

- calendar_utils.dart（内部工具，不进公开 API）的约定：**算术在 UTC 域**（`slimcaUtcDate` → 增减天数 → `slimcaLocalFromUtc`），UTC 无夏令时、Duration 天数精确；**展示/回调只在本地日界**（y/m/d，`slimcaDateOnly`）。
- `recordCounts` 键必须本地日界归一化——SlimcaMonthGrid 内部会对入参再归一化一次，但宿主侧 day_summary 直出口径也应归一；混用带时刻的 DateTime 键会静默匹配失败（色点不显示，无异常）。
- 翻周页码换算依赖「UTC 天数差恰为 7 的整数倍」；自造周算术若在本地域做，DST 两天会错位一周。

## 7. dynamic_color 必须精确 pin 1.8.1（升级禁令）

1.9.0 的 android/build.gradle.kts 有上游 bug（未应用 kotlin 插件却用 kotlin{} 扩展、自带 buildscript 硬编码 AGP 8.13.1）——**release 构建必挂**；2.x 需 material_color_utilities ^0.13.0，与 Flutter 3.32 钉定的 0.11.1 冲突。待 Flutter SDK 升级后再评估（2026-11-17 实测，commit 9e57aa4）。误升级会只挂 release、debug 正常，难排查。

## 8. MotionConfig.scaled 的毫秒取整与滑杆合成

滑杆系数可产生非整毫秒时长（168ms×1.3=218.4）——`scaled` 统一按毫秒粒度取整，保证装配时长落在 token 表值粒度；`offFadeDuration` 固定 100ms 不参与缩放；off 档不叠加滑杆。比较 MotionConfig 相等性时注意 lerp 中曲线/档位按 t≤0.5 取 a 否则取 b（离散字段惯例），不要按逐字段插值理解。

## 9. 手势与生命周期坑（日历/周条实测踩过）

- **SlimcaCalendarStrip._lastSelected 必须急切初始化**：`late x = widget.selectedDate` 声明初始化器在首次读取（didUpdateWidget，widget 已换新）才求值，首帧外部变更与初始值恒等、锚定回位永不触发——已在 initState 显式初始化，重构时勿改回 late 初始化器。
- **SlimcaCalendar._settleTo 必须重置 _dragging**：否则 `_currentFraction` 恒返回 _dragFraction，settle 补间永不生效（形变冻结在松手位置）。
- 拖拽起手冻结形变分数须在 `controller.stop()` **之前**读（停走补间后 isAnimating=false，读数失真）。
- `onVerticalDragCancel` 会被未起手的落败指针触发（日格点按等）——只在真实拖拽被抢占时回补间，且**不回发 onExpandedChanged（防幽灵通知）**。
- 命中区与视觉间距的取舍：360dp 宽 7 列物理上无法同时满足 48 命中与 8dp 命中间距——**命中优先**，视觉间距由装饰 margin 承担（InkWell customBorder 只影响 ink 形状不影响命中）。

## 10. 金额一律整数分，禁浮点（§5.1）

`SlimcaMoneyText.format` 全程整数运算（分→元只做整除+补零），与 core_db money 行、feature_capture 编辑回填同口径。上层展示金额时不要引入 double 中间值（精度损失会污染统计与同步）。
