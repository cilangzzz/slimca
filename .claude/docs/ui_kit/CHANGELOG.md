# Changelog — ui_kit

> 模块变更历史。最新变更在最上方。排查问题时优先阅读本文件。
> 基础层模块：本包变更往往影响全部上层包（apps/mobile + 4 个 feature_*），跨模块影响逐条标注。

---

## [2026-11-19] 花瓣形 FAB ShapeBorder + AA 护栏对增补（底栏重设计）

**类型**: feat（用户拍板：凹槽花瓣底栏——评审三方案 43/50 胜出）
**提交**: 待提交（工作区）
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/components/cookie_fab_shape.dart | 新增 | **花瓣形 ShapeBorder（M3 Expressive「cookie」12 瓣，拍板推导）**：scallop 精确相交构造（每瓣一次 Path.arcTo，瓣谷=相邻花瓣圆外交点），瓣数/谷径比固化为几何常量 kSlimcaCookiePetals=12 / kSlimcaCookieValleyRatio=0.86（非动效 token，范本 spring_sheet kSlimcaSheet*）；lerpFrom/lerpTo 回退=t<0.5 硬切（P2 morph 须自行实现）；**有效域 k>cos(π/n)/(1+sin(π/n))**（n=12→k>0.7673，越界=闭式解增根轮廓自交且路径仍闭合连续），getOuterPath 内 debug assert 兜底；ui_kit.dart barrel 登记 |
| test/cookie_fab_shape_test.dart | 新增 6 例 | **几何单测（评审 [13] 补缺）**：12 瓣尖恰落 R（采样 contains）、12 瓣谷恰在 kR、闭合+bounds=外接盒+无 NaN、失效域 assert 触发（k=0.7）、下界附近（0.78）不触发、常量相等性 |
| lib/src/components/calendar_strip.dart | +4/-0 | **周条日格 Text 补 maxLines:1+clip**（新 360dp 冒烟暴露的既有窄屏缺陷）：360dp 下日格宽 30.9 时标签/日期换行令 56 高 Column 溢出 20px；宽屏单行布局零变化 |
| lib/src/tokens/contrast.dart | +28 | **kSlimcaAaPairSpecs 增补 2 对**：「主色钮面/底栏卡面」「底栏描边/底栏卡面」（kAaUiContrast 3.0，置于 onPrimary/primary 锚点对前——primary 降级后 onPrimary 随新值复检）。动机：一体化凹槽底栏后中央按钮由「FAB 独立元素（可豁免）」转入容器类 3:1 校验 |

### 影响范围

- **跨模块（apps/mobile 底栏）**：SlimcaCookieShapeBorder 经 barrel 导出供壳层 FAB 使用；护栏对增补经 buildTheme→enforceSlimcaAa 装配出口自动生效。
- **主题包零降级**：6 内置包 × 明暗的 primary/outline↔surfaceCard **自然达标**（apps/mobile notch_bar_shell_test 不变量锚定）——护栏对为纯增益，不牵动任何主题包主色。
- **帧预算**：形状为静态 Path（无 painter/无 shouldRepaint/无循环动画），帧预算零增量（frame_budget_benchmark_test 全档位回归通过）。
- **评审修复（对抗性评审 15 条确认）**：失效域注释纠偏（原宣称 k∈[0.6,0.92] 对 n≥7 自交）+ debug assert；lerp 回退口径纠偏（硬切非 scale+fade）；注释规范引用改指真实条目（§5 #14/§2.2 增补段）。

### 回滚指南（LOW）

- 回滚：删除 cookie_fab_shape.dart + barrel 两行 + contrast.dart 两对即可；apps/mobile 侧 FAB shape/backgroundColor/foregroundColor 三行随之退化（见 apps-mobile CHANGELOG 同日条目）。
- 检查：flutter analyze 0 issue；ui_kit 全量（含 AA audit 与新增 cookie 几何 6 例）全绿。

## [2026-11-18] 弹层路由 M3 容器口径 + count-up tabular figures（大厂设计规范对齐）

**类型**: refactor
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/transitions/spring_sheet.dart | +60/-6 | **弹层路由容器 M3 化（§8.1 大厂设计规范.md）**：拖拽把手 32×4dp（onSurfaceVariant，新 `SlimcaSheetGrabber`）+ 顶部圆角 28dp（M3 extraLarge，`RoundedRectangleBorder`+antiAlias）+ modal 内容最大宽 640dp（ConstrainedBox）；常量 `kSlimcaSheetHandle*/CornerRadius/ModalMaxWidth` 落 ui_kit（D1 token 层）。**全部经 SlimcaSpringSheetRoute 的弹层（capture/plan 编辑器/主题编辑器等）自动对齐，无需逐个回改（§8.2#7）** |
| lib/src/transitions/count_up.dart | +12/-3 | 数字排版强制 tabular figures（§5.4 双账数字等宽对齐纪律，拍板 + M2/HIG）——count-up 跳动位数不抖动；SlimcaMoneyCountUp 经委托自动继承 |

### 影响范围

- **跨模块（全部弹层宿主）**：所有 `showSlimcaSpringSheet` 弹层视觉变化——顶部多 14px 把手区、顶角变圆、宽屏（>640）内容居中限宽。触控命中不受影响（把手非交互）。
- **tabular figures**：全部 count-up 数字（确认卡热量/金额、仪表盘联动处）等宽渲染；静态金额大字（CaptureAmountDisplay）同提交另行补齐。
- **帧预算**：纯静态容器/字形变化，无动效路径变更（MotionLevel=off 纪律不受影响）。

### 回滚指南（MEDIUM）

- 回滚：revert spring_sheet.dart buildPage 与 count_up.dart 两处。
- 检查：ui_kit transitions_smoke_test、各弹层宿主（capture/plan/settings）冒烟。

---


**类型**: feat
**提交**: d6650f8
**风险**: HIGH

### 变更文件（ui_kit 16 个文件，+2601/-7）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/components/calendar.dart | +283/-0 | 新增 SlimcaCalendar：周条↔月网格垂直手势形变容器（拖拽跟手+松手补间，curveExpand/curveCollapse 曲线对；受控/非受控 expanded 双模式） |
| lib/src/components/calendar_strip.dart | +281/-0 | 新增 SlimcaCalendarStrip v2：PageView 无限双向翻周（±5000 周），横滑=翻周不切日，今日锚定回位（SharedAxis token） |
| lib/src/components/calendar_utils.dart | +53/-0 | 新增内部纯日期算术工具（UTC 域运算防 DST，不进公开 API） |
| lib/src/components/month_grid.dart | +331/-0 | 新增 SlimcaMonthGrid：受控月网格（视觉 40/命中 48、≤3 Compact 色点、星期标签 ExcludeSemantics） |
| lib/src/components/menu.dart | +216/-0 | 新增菜单组件族 SlimcaMenuGroup/SlimcaMenuTile/SlimcaMenuPill（行高 56/72、destructive 危险项红字） |
| lib/src/components/confirm_card.dart | +10/-4 | 缺省 padding 改引 SlimcaSpacing.space200（杜绝组件层裸间距字面量） |
| lib/src/tokens/slimca_spacing.dart | +170/-0 | 新增约束 token 层 SlimcaSpacing（8 档官方刻度 + xs/s/m/l/xl/xxl 别名 + 5 语义位） |
| lib/src/tokens/slimca_sizes.dart | +217/-0 | 新增 SlimcaSizes（命中/行高/日历/圆角/状态层四档 17 字段） |
| lib/src/tokens/motion_config.dart | +58/-1 | MotionConfig 新增 curveExpand/curveCollapse/curveEffectsStandard 三个必填曲线 token（构造签名变化） |
| lib/src/tokens/build_theme.dart | +18/-1 | buildTheme 挂 SlimcaSpacing/SlimcaSizes 扩展 |
| lib/src/transitions/stagger.dart | +4/-1 | 级联收尾曲线改引 curveExpand（进出场不对称纪律） |
| lib/ui_kit.dart | +9/-0 | barrel 登记新组件与约束 token 导出 |
| test/calendar_test.dart 等 4 个测试 | +951/-0 | calendar_test 464 / menu_test 184 / motion_curves_test 147 / spacing_sizes_test 156 |

### 影响范围
- **API**: 日历/菜单域组件全量替换为 v2 API；MotionConfig 构造签名新增 3 必填参数（手工构造 MotionConfig 的外部代码会编译失败）。破坏性改动明细见 [pitfalls.md](pitfalls.md) 第 5 条。
- **跨模块**: 同提交亦改 feature_dashboard（9 个文件，仪表盘接新日历）与 apps/mobile（8 个文件，壳层装配+设置页+测试手势口径）；全仓 771 例测试全绿。
- **数据模型**: 无（纯 UI 层）。
- **配置**: 无。

### 回滚指南（HIGH）
- 回滚: `git revert d6650f8` —— 但该提交与 feature_dashboard/apps/mobile 的接线在同仓库互相依赖，单独 revert ui_kit 文件会导致壳层编译失败；需整提交回滚并连带回滚两个消费包。
- 检查文件: lib/src/tokens/slimca_spacing.dart、slimca_sizes.dart、motion_config.dart、lib/src/components/calendar*.dart、menu.dart、ui_kit.dart。
- 副作用: 回滚后 MotionConfig 失去曲线对 token，周条回退前代设计；feature_dashboard 的日历接线与设置页菜单需同步回旧 API（该提交内已一并包含）。

---

## [2026-11-17] fix(deps): pin dynamic_color 1.8.1，修复 release 构建必挂的上游脚本 bug

**类型**: fix
**提交**: 9e57aa4
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +5/-1 | dynamic_color 精确 pin 1.8.1 并写明理由注释：1.9.0 android/build.gradle.kts 未应用 kotlin 插件却用 kotlin{} 扩展 + 硬编码 AGP 8.13.1（release 构建必挂）；2.x 需 material_color_utilities ^0.13.0 与 Flutter 3.32 钉定 0.11.1 冲突 |

### 影响范围
- **API**: 无。
- **跨模块**: 无（仅本包 pubspec；但全仓 release 构建依赖此 pin，误升级会只在 release 挂、debug 正常）。
- **数据模型/配置**: 依赖锁变化随 pubspec.lock 全仓生效。

---

## [2026-11-17] W16 主题编辑器+6 主题包+dynamic_color+端侧小票 OCR（M3 闸门：V1 收官）

**类型**: feat
**提交**: 11b5ce2
**风险**: HIGH

### 变更文件（ui_kit 16 个文件，+2657/-20 为整提交合计）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/components/theme_editor_panel.dart | +738/-0 | 新增 ThemeEditorPanel：四通道种子取色（kcal/money lockedHue 锁 150°/62°）+ AA 实时反馈条 + 四滑杆 + MotionLevel 选择 + 仪表盘微缩预览；草稿回调不触库 |
| lib/src/tokens/theme_profile.dart | +394/-0 | 新增 ThemeProfile 主题包模型：toSlimcaTheme/toMotionConfig 派生 + toTokensJson/toJsonRow（键名对齐 core_db theme_profiles 行）+ 四滑杆构造期钳制 |
| lib/src/tokens/contrast.dart | +237/-0 | 新增 WCAG AA 护栏：computeContrastRatio/resolveAaSafeColor（tone 轴双向搜索）+ kSlimcaAaPairSpecs 10 关键对 + auditSlimcaAa（只读）/enforceSlimcaAa（幂等降级） |
| lib/src/tokens/dynamic_color.dart | +148/-0 | 新增 SlimcaDynamicThemeMapper（accent/neutral 两源映射，kcal/money 不映射）+ SlimcaDynamicColorBuilder + 可注入 CorePaletteLoader |
| lib/src/tokens/theme_presets.dart | +136/-0 | 新增 6 内置主题包（墨/纸/霓虹/奶油/森野/曜黑）+ seedFromHct |
| lib/src/tokens/slimca_theme.dart | +16/-1 | 公开 fromPalette 推导入口（供主题包层复用，替代壳层复刻副本） |
| lib/src/tokens/build_theme.dart | +8/-1 | 装配出口接 enforceSlimcaAa 兜底 |
| lib/src/tokens/motion_config.dart | +3/-1 | MotionConfig.scaled 时长缩放改毫秒粒度取整（168×1.3→218ms） |
| pubspec.yaml | +3/-0 | 新增 dynamic_color 1.8.1 依赖 |
| lib/ui_kit.dart | +7/-0 | barrel 登记 W16 导出 |
| test/contrast_test.dart 等 6 个测试 | +977/-17 | contrast 182 / dynamic_color 204 / theme_editor 167 / theme_presets 131 / theme_profile 261 / w34_components ±22 |

### 影响范围
- **API**: 新增主题装配层全套 API（ThemeProfile/护栏/dynamic_color/ThemeEditorPanel）；SlimcaTheme.fromPalette 由私有转公开。
- **跨模块**: 同提交亦改 core_ai（15 个文件，含 ReceiptDateTime occurredAtMsUtc 日偏移 bug 修复）与 apps/mobile（14 个文件，壳层 profile→buildTheme 装配链）；ui_kit 测试 58→125 例。
- **数据模型**: ThemeProfile.toJsonRow 键名与 core_db `theme_profiles` drift 行一一对应（id/name/tokens/motionLevel/fontId/isPreset/sort）——改任一侧必须同步另一侧。
- **配置**: pubspec 新增 dynamic_color（后由 9e57aa4 pin）。

### 回滚指南（HIGH）
- 回滚: `git revert 11b5ce2` —— 同提交深度耦合 core_ai 与 apps/mobile（壳层 theme_providers 直接调用 toSlimcaTheme/toMotionConfig），需整提交回滚。
- 检查文件: lib/src/tokens/theme_profile.dart、contrast.dart、dynamic_color.dart、theme_presets.dart、lib/src/components/theme_editor_panel.dart。
- 副作用: 回滚后失去主题自定义能力与 AA 护栏兜底（手写 token 不达标将直接上线）；settings 流的主题装配链需回退 W15 前口径。

---

## [2026-11-17] W15 多账本+预算体系+统计报表（周/月/年+钱-热量双轴）

**类型**: feat
**提交**: fd9d619
**风险**: MEDIUM

### 变更文件（ui_kit 侧）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/transitions/shared_axis.dart | +39/-0 | 新增 SlimcaSharedAxisPage：共享轴转场的 Page 包装（createRoute 注入 PageRouteBuilder）——go_router pageBuilder 契约要求返回 Page 而非 Route，原实现直接回 PageRouteBuilder 编译报错（集成修复） |

### 影响范围
- **API**: 新增 SlimcaSharedAxisPage（go_router pageBuilder 接线件）。
- **跨模块**: 同提交主要改 feature_ledger（17 个文件）/apps/mobile（16 个文件）/core_db（8 个文件，含 drift readNullable<Object> 类型坑修复）——/stats 统计报表路由以 SlimcaSharedAxisPage 进入。
- **数据模型**: core_db 侧查询变更（报表桶序列 per-账本分支 SQL），ui_kit 不涉。
- **配置**: 无。

---

## [2026-11-16] W3-4 AI 双解析闭环（文本路径）：core_ai 管线 + capture 确认卡 + ui_kit 呼吸态/count-up/确认卡

**类型**: feat
**提交**: 5b456e3
**风险**: MEDIUM

### 变更文件（ui_kit 7 个文件，+699/-1）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/transitions/breath.dart | +129/-0 | 新增 SlimcaBreath 解析中呼吸态（周期=4×durL token 推导；off/reduced 降级；RepaintBoundary+TickerMode） |
| lib/src/components/confirm_card.dart | +79/-0 | 新增 SlimcaConfirmCard 确认卡容器（插槽级联入场，复用 SlimcaStaggerItem） |
| lib/src/transitions/money_count_up.dart | +78/-0 | 新增 SlimcaMoneyCountUp + SlimcaMoneyText（整数分格式化，禁浮点） |
| lib/src/components/calorie_ring.dart | +16/-1 | 新增 sweepEntrance 变体（true=首挂载从 0 扫到目标；false=首帧直达，避免入场级联+环二次 sweep） |
| lib/ui_kit.dart | +3/-0 | barrel 登记导出 |
| test/w34_components_test.dart | +389/-0 | 呼吸/确认卡/金额 count-up 组件测试（ui_kit 39→58 例） |

### 影响范围
- **API**: 新增 4 个导出（Breath/ConfirmCard/MoneyCountUp/MoneyText）+ SlimcaCalorieRing.sweepEntrance 参数。
- **跨模块**: 同提交主要改 core_ai（21 个文件，解析管线/缓存/FakeParser）、feature_capture（15 个文件，AI 双解析流状态机）、apps/mobile（13 个文件，dart-define 装配 SLIMCA_AI_BASE/KEY/MODEL——凭据只经 dart-define 键名注入）。
- **数据模型**: 无（core_db 零改动，无需 build_runner）。
- **配置**: apps/mobile 侧 dart-define 装配工厂（ui_kit 不涉）。

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: feat
**提交**: 3b1f64c
**风险**: LOW

### 变更文件（ui_kit 初始 25 个文件，+2544/-0）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/tokens/motion_config.dart | +490/-0 | MotionLevel/SlimcaSpring/SpringCurve/MotionConfig（§9.2 token 表值 + forLevel/scaled） |
| lib/src/tokens/slimca_theme.dart | +297/-0 | SlimcaTheme 语义 token（light/dark 静态基线 + fromPalette 推导 + ThemeExtensionTween） |
| lib/src/components/calorie_ring.dart | +174/-0 | SlimcaCalorieRing 占位实现（单环+摄入弧+消耗内弧+超支段） |
| lib/src/tokens/build_theme.dart | +50/-0 | buildTheme（ColorScheme.fromSeed + 语义 token 覆盖 + extensions 挂载） |
| lib/src/tokens/palette.dart | +59/-0 | SlimcaPalette（双主色锚定 HCT：kcal 150 / money 62 / danger 27 / neutral 250） |
| lib/src/transitions/（7 个文件） | +610/-0 | P0 转场六条：shared_axis 191 / spring_sheet 127 / stagger 68 / confidence_dot 95 / count_up 42 / hero_flight 49 / theme_morph 38 |
| lib/ui_kit.dart + pubspec.yaml + 包基建 | +106/-0 | barrel + workspace 声明 + analysis_options/LICENSE/.gitignore |
| test/（5 个文件） | +725/-0 | motion_config 226 / transitions_smoke 254 / theme_builder 106 / tokens 124 / ui_kit 15（39 例） |

### 影响范围
- **API**: 建立本模块全部初始 API 表面（三层 token + 6 转场 + 热量环）。
- **跨模块**: 单仓 monorepo 初始提交——同提交建立 apps/mobile（72 个文件）、core_db/core_domain/core_ai、4 个 feature 包与 server/supabase 迁移。
- **数据模型**: 无 ui_kit 侧；core_db 同提交建 schema v1（21 表）。
- **配置**: pub workspace + GitHub Actions CI 首建。

---

## 提交演进速览（旧→新）

| 提交 | 里程碑 | ui_kit 测试规模 |
|------|------|------|
| 3b1f64c | W1 地基：三层 token + 6 转场 + 热量环 | 39 例 |
| 5b456e3 | W3-4：呼吸态/确认卡/金额 count-up | 58 例 |
| fd9d619 | W15：SlimcaSharedAxisPage（go_router 接线） | 58 例 |
| 11b5ce2 | W16：主题编辑器/护栏/主题包/动态色 | 125 例 |
| 9e57aa4 | 依赖 pin（构建修复） | 125 例 |
| d6650f8 | W17 插曲：约束 token 层 + 日历/菜单组件族重做 | 173 例 |
