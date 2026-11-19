# Changelog - apps-mobile

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。
> 类型口径：修复→fix、新增/支持→feat、优化→perf、调整/重设计→refactor。

---

## [2026-11-19] 计划 Tab IA 重设计：今日为纲三卡 + 双实现/双服务收敛

**类型**: refactor（用户主诉「计划功能页面很乱，种类很多」；方案经 4 派独立设计 + 双 lens 评审定稿）
**提交**: 待提交（工作区，与 feature_plan 同批）
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/plan/plan_page.dart | 整页重写 | 今日为纲 L0：今日待办卡（实例行勾选+快加轻层+收集箱尾行）/ 今日健身卡（**四态互斥**：训练中横幅>排期行>已练摘要>空态；卡尾「健身计划」「记录健身」）/ 今日存钱卡（目标行**行内一键投币**+行点详情+尾行列表入口）。类名 PlanPage 与全部活 ValueKey 保留（e2e 类型锚/驱动键零改）；§ 锚点文案清除 |
| lib/features/plan/plan_state.dart | 瘦身 | 删 planTodos/planSavingsGoals/activeFitnessPlans 三 provider（读侧收敛 feature_plan providers——双实现消除）；体重常量切 feature_plan（缺省 70，双基线消除）；保留 planSessions/planSchedule/bodyWeightKg |
| lib/features/plan/fitness_log_page.dart | 删除 | 壳版健身表单（4 类型无强度档、钉死选中日、无删除）退役——唯一手记页=feature_plan FitnessLogPage（10 活动×3 强度+按日导航+删除） |
| lib/data/fitness_service.dart | 瘦身 | 删 FitnessService/FitnessSessionInput/fitnessServiceProvider 与 60kg 缺省常量（手动记录写路径唯一=PlanGateway，**submitFitnessSession 补三行 outbox 同事务入队**——同步不再依赖壳层）；保留壳引擎结束汇总用的 estimateBurnKcal/kMetTable |
| lib/data/savings_service.dart | 删除 | 壳层存钱写路径退役（漏斗 savings_goal_created/coin_in 随写路径收敛迁 PlanGateway） |
| lib/app/providers.dart | 微 | savingsServiceProvider 移除 |
| lib/app/router.dart | 重排 | 删 /plan/fitness；新增 /plan/todos（收集箱）、/plan/savings（存钱目标）；保留 workout/plans |
| lib/app/bootstrap.dart | 微 | createPlanGateway 注入 telemetry（漏斗在网关侧记） |
| lib/features/dashboard/today_dashboard_page.dart | 微 | 存钱空态卡补 onTap→/plan（修复「文案说去计划页却不可点」） |
| lib/features/workout/workout_session_controller.dart | 微 | kDefaultBodyWeightKg 改自 feature_plan（70） |
| test/ 16 文件 | 适配 | 全 SlimcaApp 泵点补 planGatewayProvider override（新 L0 读包 providers）；widget_test/plan_schedule_card/savings_progress_card/e2e_fitness_to_dashboard/e2e_plan_workout_acceptance 断言按新 IA 重写（70kg 基线：210→245、-10→-12；排期双现→单现；投币弹窗流→一键流；漏斗路径迁编辑抽屉） |

### 影响范围

- **用户可见面**: 计划 Tab 同屏功能种类 ~12→3 卡+1 横幅；删除/编辑/收集箱/存钱详情/标记达成/目标删除/会话删除等此前不可达能力全部接通；训练历史从 2 跳图标暗门变 1 跳明面
- **行为变更**: 默认体重 60→70（MET 估算基线）；待办重复档从首屏移入编辑抽屉（轻/重两层，与 capture 通道同构）；投币从弹窗变行内一键（今日已投置灰幂等）
- **已知后续项**: 壳层训练引擎仍为内存累积+显式保存（误杀 App 丢训练）——接 planGateway 逐组落库的持久化升级列独立加固步（最高风险，单独排期）
- **回滚**: revert 壳层 plan_page.dart + router.dart 即回旧四卡；feature_plan 侧删除项无回滚依赖

---

## [2026-11-19] 底栏重设计：凹槽花瓣一体化（凹槽花瓣底栏定型）


**类型**: refactor（用户拍板：中央「+」与 NavigationBar 不搭配 → 不规则花瓣按钮 + 凹槽承接）
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/app/router.dart | SlimcaShell 重构 | **凹槽花瓣底栏**：bottomNavigationBar 由裸 NavigationBar 换 BottomAppBar（color=surfaceCard、shape=CircularNotchedRectangle 框架凹槽零自绘、**notchMargin 显式 6**（框架默认 4，固化拍板口径 → 凹槽半径 34）、**clipBehavior antiAlias**（缺省 Clip.none 下 NavigationBar 不随凹槽裁剪，选中 pill 悬画进缺口污染间隙环）、elevation 显式 level0）内嵌 NavigationBar（类型/80dp/4 destination 逐字不动，仅背景透明+elevation 0）；FAB 保类型/tooltip/onPressed 遥测链/hero 全不动，仅 +shape=SlimcaCookieShapeBorder +显式 primary/onPrimary |
| test/notch_bar_shell_test.dart | 新增 6 例 | 壳结构唯一性（FAB/NavigationBar/BottomAppBar 全树恰一+花瓣形状+tooltip）· FAB 抽屉链不回归 · 凹槽缺口点击不误触 body/**不切 Tab**（三 Tab 标签各恰一断言——评审 [11] 补强，机制注释纠偏：缺口 hitTest 按路径拒绝→穿透由 body 吸收）· 360dp 窄屏冒烟（凹槽/pill 贴边档构建收敛）· 6 包×明暗 AA 自然达标不变量（含 dynamic_color/自定义包范围注记）· MotionLevel=off 档真壳 pumpAndSettle（坑点 11 锚点） |
| lib/features/dashboard/today_dashboard_page.dart 等 7 处 | 底 padding 裸 96→token | 96 重推为 space600+rowSingleLine+space200=120（settings 为 +space300 口径），清裸值（§2.2 禁裸尺寸）；清中央花瓣按钮凸出栏体（cradle 间隙约 34）净空。涉及 dashboard/ledger/plan/settings/budget_settings + feature_ledger category_manage/ledger_manage（均壳层悬浮面） |

### 影响范围

- **测试**：11 个既有测试文件对 FAB/NavigationBar/'记一件事'/destination 的语义查找 **0 行改动**（保类型策略）——apps/mobile 143 例全量回归通过。
- **行为**：中央「+」仍是唯一录入入口，onPressed 遥测链（funnel captureOpen→showCaptureChannelsSheet）零改动；capture 抽屉本体零改动。
- **主题**：颜色全走 SlimcaTheme token（primary/onPrimary/surfaceCard），6 主题包 + dynamic_color + 曜黑档下形状/配色随 ThemeMorph lerp 自动跟随；曜黑 surfaceCard 近糊死时 outline 描边兜底已入护栏对。
- **规范文档**：UI-规范与重设计.md §5 #14 + §2.2 增补、大厂设计规范.md §6 决策 3 + §7.2 决策同批改写（含拍板推导标注）。
- **评审修复（对抗性评审 15 条确认）**：notchMargin 显式 6 纠偏（框架默认实为 4，注释/文档 34/6dp 口径由显式传参固化为真）；clipBehavior antiAlias 补（pill 悬画进缺口）；缺口点击用例机制注释纠偏 + Tab 稳定断言补强；注释规范引用改指真实条目（产品设计文档 §4.1 原则 2=「底部 4 Tab+中央悬浮+」为既有真实出处，保留）。

### 回滚指南（MEDIUM）

- 回滚：revert router.dart SlimcaShell 段（BottomAppBar→裸 NavigationBar、FAB 去 shape/显式色）；7 处 padding revert 为 const fromLTRB。
- 检查：notch_bar_shell_test 6 例 + widget_test/e2e_* 冒烟；**遗留真机项**：360dp 眼检凹槽贴边（≤340dp 档 pill 顶角 2-4dp 裁切缺口观感确认）、6 主题包+dynamic_color+曜黑全档切换眼检。

## [2026-11-19] 首页日历接入 SlimcaCalendar（支持展开选日期）

**类型**: feat（用户拍板：首页日历组件支持展开选择具体日期）
**提交**: 待提交（工作区）
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/dashboard/dashboard_state.dart | +19 | `recordedDaysProvider`（day_summary 投影 watch，「有记录」口径与 feature_dashboard watchRecordedDays 同款）——月格色点数据源 |
| lib/features/dashboard/today_dashboard_page.dart | +24/-81 | 自绘 `_WeekStrip` 移除，换 ui_kit `SlimcaCalendar` 组合容器（§3 定稿：折叠=周条，垂直下拉/箭头展开月网格选择具体日期；受控展开态 `_calendarExpanded`；色点经 recordedDaysProvider 直出） |

### 影响范围
- **行为**：首页日历支持展开选择任意日期（此前自绘周条仅能点当周七日、无月历下钻）；展开/收起 280ms 高度形变 + SharedAxis 翻月（ui_kit §3 全套手势/转场纪律自带）。
- **数据**：色点流 = day_summary 投影 watch（既有表，零迁移）。
- **同步**：无写路径变更。

### 回滚指南（LOW）
- 回滚：revert 两文件（自绘 _WeekStrip 随 revert 恢复）。

---

## [2026-11-18] 首页去 Slimca 标题 + AI 服务用户自设配置（默认空=离线桩）

**类型**: feat（用户拍板三项：金额滚动直输见 feature_capture CHANGELOG）
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/dashboard/today_dashboard_page.dart | +3/-1 | 首页 AppBar 移除「Slimca」标题（用户拍板，状态栏下直接呈现卡片墙） |
| lib/settings/ai_api_setting.dart | 新增 | AI 配置（base/key/model）settings 表读写（§5.6⑲ 本地件、永不同步——key 只存本机）+ `configured` 标记（从未保存过→dart-define 开发联调回退） |
| lib/features/settings/ai_api_editor_sheet.dart | 新增 | 「AI 服务」编辑面板（弹簧抽屉）：三字段（key obscure）+ 保存 → settings 落库 + aiApiConfigProvider 写回（captureParserProvider 响应式重装，下一次解析生效） |
| lib/features/settings/settings_page.dart | +22/-0 | 新分组「AI 服务」入口行（副标题=已配置/未配置状态） |
| lib/app/providers.dart | +22/-0 | `aiApiConfigSeedProvider` + `AiApiConfigController`（Notifier，Riverpod 3 口径） |
| lib/app/bootstrap.dart | +30/-8 | 预载 AI 配置注入 seed；captureParserProvider overrideWithValue → **overrideWith 响应式装配**（watch 配置 → TelemetryCaptureParser/RawInputGate/createCaptureParser 链重建；用户未保存过 → 传 null 回落 dart-define） |
| test/ai_api_setting_test.dart | 新增 | settings 读写回环 + configured 标记 + provider 装配（缺省/seed/save） |
| test（widget_test/e2e_record/e2e_ledger） | +30/-18 | 键盘点按改金额 enterText（feature_capture 键盘移除）；「Slimca」标题断言改 findsNothing |

### 影响范围
- **AI 解析链路**：用户配置后即用 OpenAI 兼容 adapter（保存即时生效，controller 逐次 `ref.read captureParserProvider` 天然换装）；默认空 → 离线确定性桩（HeuristicFakeLlmAdapter）。dart-define 降级为「从未保存过时的开发联调回退」。
- **凭据安全**：key 存 settings 表（本地件、永不同步 §5.1/§3.7），编辑面板 obscure 不明文回显。
- **测试口径**：金额直输 enterText（capture_amount_display key 保留在字段上）；首页无「Slimca」文本。

### 回滚指南（MEDIUM）
- 回滚：revert 上表文件；captureParserProvider 恢复 overrideWithValue 静态装配。
- 回归：ai_api_setting_test / widget_test / e2e_record / e2e_ledger / capture_parser_factory_test。

---

## [2026-11-18] 录入通道抽屉统一高度 + 拍照单一入口（稳定输入面）

**类型**: refactor（UX 修复）
**提交**: 待提交（工作区）
**风险**: LOW

### 变更文件（git diff --numstat 口径）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/capture/capture_channels_sheet.dart | +74/-40 | 抽屉包 `captureSheetHeight` 统一高度 SizedBox（视口 62%、带限 480–640）+ viewInsets 键盘避让；**通道切换条挪到抽屉底部 + 三段 Expanded 等宽**（此前仅「拍」被拉伸致大小不一）；写通道传 showPhotoEntry=false |
| lib/features/capture/photo_capture_panel.dart | +83/-16 | 确认卡阶段改经 CaptureConfirmStage（卡面滚动 + 动作页脚钉底，CTA 恒可见）；**取景引导卡扩展吃满（整卡可点）+ 主操作贴底**；拍通道单一入口（showGalleryEntry=false，全宽「拍照识别」） |
| lib/features/capture/voice_capture_panel.dart | +68/-33 | 确认卡阶段改经 CaptureConfirmStage；**转写卡常驻扩展吃满（空态占位）+ 麦克风簇贴底**（source=voice 提交口不变）；确认阶段传面板 `errorText`（语音提交失败就地提示，不再静默） |
| test/capture_sheet_uniform_size_test.dart | 新增 211 行 | 守护测试：独立/通道抽屉装载帧、档位切换、写↔说↔拍切换全程同高；键盘弹出外框恒定 + 钉底 CTA 让出键盘；拍照入口唯「拍」通道单一按钮 |
| test/e2e_photo_capture_test.dart、test/widget_test.dart | +14/-9 | 相册 e2e 改拍照路径（漏斗 from_camera=true 口径）；拍通道断言无相册按钮（单一入口） |

### 影响范围
- **行为（三轮定稿）**：写/说/拍通道切换、单边档位切换、AI 阶段流转均不改变抽屉尺寸；各状态内容填充统一高度框（composer 扩展输入面 / 转写卡 / 取景卡扩展，稀疏操作贴底，长内容滚动 + CTA 钉底）——无空白死角；通道切换条贴底三等宽；键盘弹出时内容区按 viewInsets 收缩、钉底 CTA 恒在键盘上方（Android 15+ edge-to-edge 口径）。
- **大厂设计规范对齐（第四轮，见 docs/design/大厂设计规范.md）**：弹层容器 M3 化经 ui_kit 路由全局生效（把手 32×4/顶圆角 28/限宽 640）；通道分段与单边开关触控 40→48（minTouchTarget）；capture 域 CTA 按钮胶囊（StadiumBorder）；错误行统一 CaptureErrorText（颜色+图标双编码，D8）；金额大字与 count-up tabular figures（§5.4）；字阶对齐（分组头 Label Large 14/20/500、input 16、文本框 56dp）；新改区域间距/圆角/图标 token 化（SlimcaSpacing/Sizes，D1）。
- **单一入口（两轮收紧）**：写通道 AI 输入区不再内嵌拍照入口（归「拍」通道）；「拍」通道内只剩取景卡 + 全宽「拍照识别」单按钮，相册选择不再并列露出（相册路径语义保留在控制器与包测试）。
- **跨模块**：依赖 feature_capture 同提交改动（captureSheetHeight/CapturePage.showPhotoEntry/CaptureConfirmStage，见 feature_capture CHANGELOG）。
- **无动效路径变更**：纯布局约束（MotionLevel=off 纪律不受影响）。

### 回滚指南（LOW）
- 回滚：revert 本工作区 apps/mobile 三处源文件改动（新测试一并删除）。
- 检查文件：capture_channels_sheet.dart / photo_capture_panel.dart / voice_capture_panel.dart。

---


**类型**: refactor
**提交**: d6650f8
**风险**: MEDIUM

### 变更文件（apps/mobile，8 文件 +1027/-359）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/settings/menu_components.dart | +152 | 新增 SlimcaMenuGroup/SlimcaMenuTile 分组卡与行组件（行高 56/72、leading 24、chevron、危险项红字，规格即注释） |
| lib/features/settings/settings_page.dart | +497/-若干 | IA 重排（账号/同步卡→数据与隐私/外观/数据分组→尾部低频组+危险组）；**整块移除「升级 Slimca Pro」付费墙与裸「恢复购买」入口（IAP 抽象代码保留不删）**；版本行接 package_info_plus（FutureBuilder 占位「—」） |
| lib/features/dashboard/today_dashboard_page.dart | +276/-若干 | 仪表盘重排；卡片墙/卡内命中 ≥48 修正；动效全部读 MotionConfig token（修 §9.2 裸时长违规） |
| lib/app/router.dart | +19/-若干 | Tab 结构随重设计微调 |
| pubspec.yaml | +6 | 新增 package_info_plus ^9.0.1 直接依赖 |
| test/settings_menu_test.dart | +336 | 新增菜单页专项验收（无升级计划区块/行触碰目标/undo e2e） |
| test/widget_test.dart、test/photo_burn_setting_test.dart | +94/-若干、+6/-若干 | IA 冒烟重写；SwitchListTile→Switch 行组件口径 |

### 影响范围
- **API/页面**: 设置页结构大改（付费墙移除）；仪表盘布局重排；路由路径未变；
- **跨模块**: ⚠ 同一提交也改了 **packages/ui_kit**（13 文件：日历组件族 SlimcaCalendarStrip v2/月网格/形变容器、SlimcaSpacing/Sizes token 层、curveExpand/curveCollapse 曲线 token）与 **packages/feature_dashboard**（2 文件）——三路集成；
- **数据模型**: 无；**配置**: pubspec 新依赖。

### 回滚注意（MEDIUM）
`git revert d6650f8` 会同时回退 ui_kit 日历族与 token 层——若只需恢复设置页 IA，
应手工还原 settings_page.dart 而非整提交回滚（token 层被 ui_kit 其余组件引用）。

---

## [2026-11-17] chore(release): v1.1.0 — 版本号 bump 至 1.1.0+2

**类型**: chore
**提交**: 6e23f47
**风险**: LOW

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| apps/mobile/pubspec.yaml | +1/-1 | version 1.1.0+1 → 1.1.0+2 |

### 影响范围
仅版本号；无 API/数据模型影响；无跨模块（CHANGELOG 文档在本仓根，不在本模块）。

---

## [2026-11-17] W16 主题编辑器 + 6 主题包 + dynamic_color + 端侧小票 OCR（M3 闸门：V1 收官）

**类型**: feat
**提交**: 11b5ce2
**风险**: HIGH

### 变更文件（apps/mobile，14 文件 +2178/-21）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/theme/theme_providers.dart | +240 | 主题装配链 providers（resolved 包解析→ui_kit 三步→slimcaLight/DarkThemeProvider；platformCorePaletteProvider 默认关零通道调用） |
| lib/theme/theme_settings.dart | +193 | settings ⑲ 四键存取（current_theme_id/motion_level/theme_mode_override/dynamic_color_enabled，坏值逐键自愈） |
| lib/data/theme_profile_repository.dart | +187 | theme_profiles 仓库（行+outbox 同事务、内置包幂等种子、软删墓碑、is_preset 不可删护栏） |
| lib/theme/theme_profiles.dart | +68 | 行↔ui_kit ThemeProfile 映射 + ensurePresetThemeProfiles 6 包种子 |
| lib/features/settings/theme_editor_panel.dart | +471 | 编辑面板壳（6 包网格高亮/dynamic 开关/深浅覆盖/保存=复制新自定义包） |
| lib/features/settings/settings_page.dart | +48 | 主题入口（theme_editor_opened 漏斗） |
| lib/main.dart | +50/-若干 | builder 内 SlimcaThemeMorph 全屏 morph（300ms/off 100ms） |
| lib/app/theme.dart | +19/-若干 | W1 基线主题降级为基准测试装配点 |
| lib/app/bootstrap.dart、lib/app/providers.dart | +22、+16 | 主题预载 override（initialThemeSettingsProvider） |
| lib/telemetry/w16_funnel_events.dart | +22 | theme_editor_opened/theme_changed 常量 |
| pubspec.yaml | +8 | material_color_utilities ^0.11.1 |
| test/theme_chain_test.dart、test/theme_editor_test.dart | +429 | 装配链/编辑器往返 e2e |

### 影响范围
- **API**: 新增主题 providers 全家（README §3 主题域）；MaterialApp theme/darkTheme/morph 接线；
- **跨模块**: ⚠ 同一提交改了 **packages/ui_kit**（15 文件：ThemeProfile 模型/6 内置包/WCAG 护栏/ThemeEditorPanel/SlimcaDynamicThemeMapper）与 **packages/core_ai**（3 文件：ReceiptOcrAdapter 端侧小票 OCR 骨架+dart-define 工厂）；
- **数据模型**: theme_profiles 表首次有写路径（W1 建表冻结后补位，暂驻壳层 data 层，待上移 core_db）；
- **配置**: settings 新增 4 键。

### 回滚指南
- 回滚: `git revert 11b5ce2`（三包同回退）；
- 检查文件: lib/theme/**、lib/data/theme_profile_repository.dart、lib/main.dart（morph 接线）、
  lib/app/bootstrap.dart（initialThemeSettingsProvider override 必须同撤，否则 Provider 未定义编译错）；
- 副作用: revert 后 settings 表残留 4 个主题键（本地件自愈读忽略，无害）；theme_profiles 行残留
  （无消费方，无害）；ui_kit 内置包清单消失→壳层 presetThemeProfileById 引用断（编译期暴露）。

---

## [2026-11-17] W15 多账本 + 预算体系 + 统计报表（周/月/年+钱-热量双轴）

**类型**: feat
**提交**: fd9d619
**风险**: HIGH

### 变更文件（apps/mobile，16 文件 +2580/-76）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/ledger/budget_settings_page.dart | +654 | 预算设置页（每日总额/每日热量/分类每日/月度四区块，budget_set 漏斗） |
| lib/features/ledger/ledger_page.dart | +548/-若干 | 顶栏多账本切换器（切换=默认账本记忆+ledger_switched）+分类筛选条+管理页入口 |
| lib/ledger/multi_ledger_service.dart | +147 | 多账本壳层服务（建档委托 LedgerDao；switchDefaultLedger=指针+**sort 桥接**置首） |
| lib/features/ledger/ledger_state.dart | +144 | LedgerBillQuery 作用域/筛选口径（kcal 视图归集内置账本；口径外行连事件不入列） |
| lib/features/stats/stats_report_screen.dart | +64 | /stats 壳装配屏（注入 ReportRepository+report_viewed+「看当日」下钻） |
| lib/app/router.dart | +28/-若干 | /stats 全屏路由 + /ledger/budgets 子路由（SlimcaSharedAxisPage） |
| lib/features/dashboard/today_dashboard_page.dart、dashboard_state.dart | +149/-若干、+37 | 支出卡接预算快照 v2（余/超支状态色+per-分类行） |
| lib/app/providers.dart、lib/app/bootstrap.dart | +47、+17 | ledgerAdmin/report/ledgerManage 仓库 providers |
| lib/telemetry/w15_funnel_events.dart | +25 | report_viewed/budget_set/ledger_switched |
| pubspec.yaml | +9 | feature_ledger path 依赖 |
| test/dashboard_budget_state_test.dart、test/e2e_ledger_switch_consistency_test.dart、test/stats_report_smoke_test.dart、test/widget_test.dart | +166、+307、+268、+46 | 预算/切换一致性/报表冒烟 |

### 影响范围
- **API**: 路由表新增 /stats、/ledger/budgets；providers 新增 3 仓库；
- **跨模块**: ⚠ 同一提交改了 **packages/core_db**（5 文件：LedgerDao 多账本生命周期、BudgetsDao、budget_snapshot v2）与 **packages/feature_ledger**（4 文件：ReportPage/LedgerManagePage/parseBudgetSnapshot v2）；ui_kit 新增 SlimcaSharedAxisPage（go_router pageBuilder 契约修复）；
- **数据模型**: budgets 写路径收口 BudgetsDao；budget_snapshot v2（daily+monthly 双数组，v1 键形向后兼容）；
- **集成修复**: drift QueryRow 无类型 readNullable 抛错→账本管理流恒空（改 readNullable<String>）；报表 per-账本分支 SQL 占位符数不匹配。

### 回滚指南
- 回滚: `git revert fd9d619`（core_db/feature_ledger/apps-mobile 三处同回退）；
- 检查文件: lib/ledger/multi_ledger_service.dart（settings 默认指针写入）、lib/features/ledger/**、
  lib/app/router.dart（/stats 路由）；
- 副作用: settings 残留默认账本指针（LedgerDao 读侧仍在则无害）；budgets/budget_snapshot v2 行残留
  ——**core_db 同提交回退则 schema 回 v1**，v2 JSON 旧列值由解析器兼容，无需数据迁移。

---

## [2026-11-17] W14 健身计划：模板排期 + 组间计时（锁屏骨架）+ 组明细联动 burn

**类型**: feat
**提交**: b367a6c
**风险**: HIGH

### 变更文件（apps/mobile，22 文件 +3466/-7）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/features/workout/workout_session_controller.dart | +326 | 训练会话控制器（keepAlive Notifier；绝对时刻倒计时+注入时钟；开练/记组/跳过/结束编排） |
| lib/data/workout_log_service.dart | +276 | 训练完成落库（单事务 5 表+outbox+投影；MET=力量中位 5.0） |
| lib/data/workout_models.dart | +181 | exercises 宽容解析（兼容 feature_plan 编辑器对象/裸数组双形状+×10 定点键） |
| lib/features/workout/workout_runner_page.dart | +409 | 训练中页（1s Timer 只做探询+渲染，业务推进在控制器） |
| lib/features/plan/plan_page.dart、plan_state.dart | +242、+80 | 排期卡（isPlanScheduledOn 掩码判定）+「开始训练/模板」入口 |
| lib/features/dashboard/today_dashboard_page.dart | +182 | 训练中态卡（剩余秒/跳过休息/结束保存） |
| lib/workout/ 6 文件 | +407 | KeepAwakeService/WorkoutTimerNotifier 抽象+wakelock_plus/flutter_local 适配器+双 Fake（渠道 workout_timer、固定 id 0x5714、Chronometer 倒计时） |
| lib/app/bootstrap.dart、lib/app/providers.dart、lib/app/router.dart | +22、+45、+19 | keepAwake/workoutTimerNotifier/workoutClock/workoutLogService 装配 + /plan/workout 路由 + planGateway override |
| lib/telemetry/w14_funnel_events.dart | +25 | workout_started/set_logged/workout_completed |
| pubspec.yaml | +12 | feature_plan path 依赖 + wakelock_plus ^1.4.0 |
| test/workout_session_fake_test.dart（+584）、test/e2e_plan_workout_acceptance_test.dart（+382）、test/plan_schedule_card_test.dart（+305）、test/widget_test.dart | +1299 | Fake 计时专项+训练→仪表盘净热量 e2e |

### 影响范围
- **API**: 路由新增 /plan/workout、/plan/plans；providers 新增 4 个训练域注入点；
- **跨模块**: ⚠ 同一提交改了 **packages/feature_plan**（6 文件：模板建档/编辑/PlanGateway）；
- **数据模型**: fitness_sessions（type=template_instance,source=plan）+exercise_sets（weight×10 定点、sort 全局组序）首次写；entries.source 无 plan 枚举→manual（会话行 source 承载计划来源）；
- **remaining**: 锁屏计时/前台服务/真机验收。

### 回滚指南
- 回滚: `git revert b367a6c`；
- 检查文件: lib/app/bootstrap.dart（keepAwake/workoutTimerNotifier override 必须同撤）、
  pubspec.yaml（feature_plan/wakelock_plus 依赖）、lib/app/router.dart（/plan/workout、/plan/plans）;
- 副作用: exercise_sets/fitness_sessions 残留 template_instance 行（读侧消失即不可见，无害）；
  仪表盘训练中态卡回退消失——进行中训练态本就内存态，重启即清。

---

## [2026-11-17] build(android): enable core library desugaring for flutter_local_notifications

**类型**: fix
**提交**: d9b4428
**风险**: MEDIUM

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| apps/mobile/android/app/build.gradle.kts | +6 | isCoreLibraryDesugaringEnabled=true + desugar_jdk_libs 2.1.4（flutter_local_notifications AAR 元数据检查要求） |

### 影响范围
**配置**: Android 构建必需——回退此提交 release/_debug 构建即在 AAR 检查挂。
无 Dart 面/数据模型影响。

---

## [2026-11-17] W13 待办完整版（RRULE+提醒调度）+ 存钱目标（365/52 周/自定义+投币打卡）

**类型**: feat
**提交**: cc86213
**风险**: HIGH

### 变更文件（apps/mobile，21 文件 +2447/-49）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/notifications/ 6 文件 | +718 | ReminderScheduler 抽象+flutter_local 适配器（todo_reminders 渠道、POST_NOTIFICATIONS 运行时请求、UTC 绝对瞬间 zonedSchedule、inexactAllowWhileIdle）+Fake+RRULE 展开（DAILY/WEEKLY/MONTHLY+COUNT/UNTIL/BYDAY 子集，未知部件降级）+ReminderSyncCoordinator（todos 流→规划→通知 id 差异对账） |
| lib/notifications/reminder_planner.dart | +114 | 纯函数规划（窗口 max(锚点,今天)→+30 天、单待办 ≤32 实例、FNV-1a 稳定通知 id） |
| lib/data/savings_service.dart | +174 | 存钱写路径编排（rhythm JSON/slot/建议额、coinIn 幂等返回既有行、漏斗埋点） |
| lib/features/plan/plan_page.dart | +607/-若干 | 计划 Tab 三卡真页（待办重复/提醒选择器+存钱目标卡+投币打卡） |
| lib/features/plan/plan_state.dart | +69 | planTodos/planSessions/planSavingsGoals providers |
| lib/features/dashboard/today_dashboard_page.dart、dashboard_state.dart | +124/-若干、+20 | 存钱进度卡接真数据（savings_progress 快照直出） |
| lib/app/providers.dart、lib/app/bootstrap.dart、lib/main.dart | +56/-若干、+19、+6 | DAO 挂投影+reminderScheduler 装配+reminderCoordinator.start() |
| lib/telemetry/w13_funnel_events.dart | +23 | savings_goal_created/coin_in/todo_recurrence_created |
| android/.../AndroidManifest.xml | +4 | POST_NOTIFICATIONS 权限声明 |
| pubspec.yaml | +8 | flutter_local_notifications ^19 + timezone ^0.10 |
| test/reminder_scheduler_fake_test.dart（+368）、test/savings_progress_card_test.dart（+199）、test/notification_permission_manifest_test.dart（+79）、test/widget_test.dart | +668 | 调度对账/进度卡/manifest 断言 |

### 影响范围
- **API**: providers 新增 todoDao/savings 双 DAO/savingsService/reminderScheduler；
- **跨模块**: ⚠ 同一提交改了 **packages/core_db**（9 文件：**todos 补列 rrule_anchor_date、savings_contributions 补列 source**——schemaVersion 保持 1，beforeOpen PRAGMA 幂等回填）与 **packages/feature_plan**（8 文件：RRULE 五档查询展开）；
- **数据模型**: savings_goals/savings_contributions 首写（append-only 幂按 goal+date+source）；day_summary.savings_progress 投影联动；
- **remaining**: 真实通知触发待真机验收。

### 回滚指南
- 回滚: `git revert cc86213`；
- 检查文件: lib/app/main.dart（reminderCoordinator.start()）、AndroidManifest（权限声明可留）、
  lib/app/providers.dart（投影挂接）；
- 副作用: ⚠ core_db schema 补列已随包回退——旧库文件含新列（PRAGMA 探测幂等，重开不迁移）；
  settings 无新增键；系统侧已调度通知不自动撤销（对账在下次启动重建）。

---

## [2026-11-17] W11-12 拍照通道：双供应商识别管线 + 端侧压缩 + 即焚 + 确认卡复用

**类型**: feat
**提交**: 19d439b
**风险**: HIGH

### 变更文件（apps/mobile，20 文件 +2705/-32）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/ai/photo_parser_factory.dart | +615 | 双供应商工厂+三实现（BaiduDish token→dish v2+内置快表粗估恒 0.35；VisionLlm OpenAI 兼容多段 content+受约束 JSON；OfflineStub 离线桩）+CapturePhotoParserFallback 组合 |
| lib/features/capture/photo_capture_panel.dart | +301 | 「拍」通道面板（入口/呼吸/确认卡复用/降级跨通道接续） |
| lib/photo/photo_attachment_store.dart | +131 | 即焚开关感知附件存储（content_hash 去重补指 entry、焚前留档副本） |
| lib/photo/photo_image_source.dart | +78 | image_picker 薄封装（1280/q80 拾取参数内压缩、取消/权限拒绝返回 null 不抛） |
| lib/photo/photo_compressor.dart | +42 | 规范化收口（mime 归一+sha256 一址两用键；空字节抛错防误命中缓存） |
| lib/settings/photo_burn_setting.dart | +74 | 即焚开关（默认开、坏值回落更严档） |
| lib/features/capture/capture_channels_sheet.dart | +61/-若干 | 通道条加「拍」chip |
| lib/features/settings/settings_page.dart | +49 | 即焚开关 Switch 行 |
| lib/app/bootstrap.dart | +79/-若干 | 拍照 6 注入点装配+附件残留 >7 天清扫+photoArchive 目录 |
| android/.../AndroidManifest.xml | +19 | CAMERA+相册分级权限；android/build.gradle.kts、settings.gradle.kts | +3、+4 | 构建调整 |
| ios/Runner/Info.plist | +6 | 相机/相册用途描述 |
| pubspec.yaml | +12 | image_picker/crypto/http |
| test/e2e_photo_capture_test.dart（+513）、test/photo_host_test.dart（+447）、test/photo_burn_setting_test.dart（+176）、test/photo_permission_manifest_test.dart（+108） | +1244 | 双分支 e2e（raw_input 关/开）、即焚收口、manifest |

### 影响范围
- **API**: capture 注入点 +5（imageSource/compressor/photoParser/attachmentStore/photoTelemetry）；
- **跨模块**: ⚠ 同一提交改了 **packages/core_ai**（14 文件）、**packages/core_db**（10 文件：attachments 表+AttachmentsDao 即焚状态机）、**packages/feature_capture**（2 文件：拍照路径接缝）；
- **数据模型**: attachments 首写（登记即 burned、blob_ref 恒 NULL、不出网）；ai_parses photo 缓存键=压缩产物 sha256；
- **配置**: 权限清单+Info.plist；remaining：百度/Vision 真实凭据联调、真机 ≤15s。

### 回滚指南
- 回滚: `git revert 19d439b`；
- 检查文件: lib/app/bootstrap.dart（拍照 6 注入点+清扫）、AndroidManifest/Info.plist（权限）、
  pubspec.yaml（三插件）；
- 副作用: attachments burned 行残留（blob_ref 恒 NULL 无原图泄漏风险）；photo_archive/ 本机留档
  文件不随回滚删除（需手工清理 support 目录）。

---

## [2026-11-16] W9-10 v1.0 公测就绪：北极星埋点核对 + 帧预算基准 + MVP 期收官（M2 闸门）

**类型**: feat
**提交**: f955652
**风险**: MEDIUM

### 变更文件（apps/mobile，9 文件 +760/-20）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/telemetry/frame_telemetry.dart | +117 | FrameTelemetry（SchedulerBinding 帧回送→批聚合 frameRasterMs/frameDropped；debug 不采） |
| lib/app/bootstrap.dart | +104 | ensureFirstOpenDay（first_open_day D0 锚点+UTC 午末日偏移）+firstOpen/appOpen 漏斗 |
| lib/app/router.dart | +61/-若干 | FAB 补 captureOpen 起点+captureConfirm 终点+capture_open_to_confirm_ms 护栏指标 |
| lib/main.dart | +9 | 非 debug 挂 FrameTelemetry.attach；冷启动漏斗 boot_ms |
| lib/telemetry/telemetry.dart | +2 | FrameStats/FrameTelemetry 导出 |
| test/northstar_telemetry_test.dart（+262）、test/benchmark/frame_budget_benchmark_test.dart（+199）、test/e2e_record_to_dashboard_test.dart | +482 | 北极星漏斗/帧预算基准 |

### 影响范围
- **API**: 无新路由；漏斗事件补「打开」起点；
- **跨模块**: 同一提交改 **packages/core_domain**（1 文件，TelemetryMetricName 收敛）；
- **数据模型**: settings 新键 first_open_day；**配置**: 无。

---

## [2026-11-16] W7-8 同步一期：Supabase 后端接线 + 遥测/raw_input 开关/IAP 骨架

**类型**: feat
**提交**: d13c27d
**风险**: HIGH

### 变更文件（apps/mobile，29 文件 +2657/-51）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/sync/sync_backend_factory.dart | +66 | dart-define 双键齐→SupabaseSyncBackend；缺→LocalLoopbackBackend；describeSyncBackend |
| lib/sync/sync_coordinator.dart | +113 | SyncCoordinator（注册→立即一轮→15min 周期+resumed 触发+重入合并+异常→crash）+SyncLifecycleObserver |
| lib/sync/telemetry_sync_backend.dart | +87 | push/pull 成败漏斗装饰器（异常 rethrow 只旁观） |
| lib/telemetry/file_telemetry_service.dart | +158 | FileTelemetryService（JSONL、串行写队列、TelemetryPrivacy 消毒、crash 只记类型+帧数） |
| lib/telemetry/telemetry.dart、noop_telemetry_service.dart | +22、+38 | 装配 barrel+Noop |
| lib/ai/raw_input_gate_capture_parser.dart | +43 | raw_input 闸门装饰器（关=仅发规范化文本，缓存键不变） |
| lib/ai/telemetry_capture_parser.dart | +83 | 解析漏斗装饰器（请求/成功/失败降级，不再叠 timeout） |
| lib/billing/ 4 文件 | +310 | BillingService 抽象+Fake+双轨 SKU 目录（98/128 买断+12/18 订阅，占位 ID）+注入点 |
| lib/settings/raw_input_setting.dart | +56 | raw_input 开关（默认关） |
| lib/app/bootstrap.dart | +138/-若干 | 装配大扩容（遥测/开关/同步栈/IAP/装饰链） |
| lib/main.dart | +45/-若干 | 崩溃钩子双通道+冷启动漏斗 |
| lib/features/settings/settings_page.dart | +274 | 开关行+同步状态行 |
| pubspec.yaml | +7/-若干 | path_provider/feature_sync |
| test/sync_factory_test.dart（+442）、test/telemetry_file_test.dart（+148）、test/raw_input_switch_test.dart（+276）、test/billing_fake_test.dart（+114）、test/test_support.dart | +1121 | 工厂/落盘/开关/Fake 断言 |

### 影响范围
- **API**: providers 新增 telemetry/rawInputPolicy/syncEngine/syncCoordinator/billing 5 注入点；
- **跨模块**: ⚠ 同一提交改 **packages/feature_sync**（5 文件：SupabaseSyncBackend/引擎）、**packages/core_db**（6 文件：outbox 基座）、**packages/core_domain**（2 文件）、**packages/feature_capture**（1 文件）；
- **数据模型**: settings 新键 raw_input_cloud_enabled；
- **remaining**: 真实 Supabase 端点联调、真实 IAP 待凭据/商店账号。

### 回滚指南
- 回滚: `git revert d13c27d`；
- 检查文件: lib/app/bootstrap.dart（同步栈+装饰链装配）、lib/main.dart（崩溃钩子）、
  pubspec.yaml（path_provider/feature_sync）；
- 副作用: sync_outbox 残留未出队行（回滚后无引擎消费，本地数据不丢）；telemetry_events.jsonl
  留盘（合规材料，可留）。

---

## [2026-11-16] W5-6 记账完整化 + 语音(Fake 链路) + 健身 + 同步引擎（M1 功能项）

**类型**: feat
**提交**: 3022e4d
**风险**: HIGH

### 变更文件（apps/mobile，31 文件 +3581/-2577）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/ai/ai_parser.dart、ai_parser_factory.dart、fake_parser.dart、openai_compat_adapter.dart | **-362、-44、-109、-235** | **壳内 AI 第一版整体删除**——三接缝收敛至 core_ai（三路集成，下移包内） |
| lib/data/ai_capture_service.dart、data/ai_parse_cache.dart | **-420、-100** | 壳内 AI 服务/缓存删除——由 feature_capture CaptureGateway + core_ai 管线接管 |
| lib/features/capture/capture_page.dart | **-570** | 壳内录入页删除——「壳唯一录入 UI=feature_capture CapturePage」纪律落地 |
| lib/ai/capture_parser_bridge.dart、lib/ai/capture_parser_factory.dart | +128、+61 | core_ai 管线→CaptureParser 桥 + dart-define 工厂（SLIMCA_AI_*） |
| lib/data/fitness_service.dart | +350 | 健身手动记录写路径（MET 简表/单事务 3 表+outbox/settings 体重） |
| lib/voice/speech_transcriber.dart | +116 | 语音抽象+FakeTranscriber（语料轮转）+PlatformChannel 桩 |
| lib/features/ledger/ledger_page.dart、ledger_state.dart | +242、+195 | 账本 Tab 真页（按日分组流水+编辑抽屉入口） |
| lib/features/plan/plan_page.dart、plan_state.dart | +365/-若干、+64 | 计划 Tab 真页（待办/健身/存钱骨架卡） |
| lib/app/router.dart、lib/app/bootstrap.dart、lib/app/providers.dart | +48/-若干、+17/-若干、+29/-若干 | 计划/账本真页挂载+装配收敛 |
| pubspec.yaml | +7 | feature_plan/feature_ledger/core_ai path 依赖 |
| test/e2e_voice_capture_test.dart、test/e2e_fitness_to_dashboard_test.dart 等 | +若干 | 语音/健身 e2e |

### 影响范围
- **API**: 壳层 ai/ 表面大幅收缩为「工厂+桥」两点；capture_page.dart 路由面改由 feature_capture 提供；
- **跨模块**: ⚠ 同一提交改 **packages/core_ai**（新建管线）、**packages/feature_plan**（12 文件）、**packages/feature_sync**（7 文件：LocalSyncEngine）、**packages/feature_ledger**（6 文件）、**packages/core_domain/core_ai** 各 1——M1 六包集成；
- **数据模型**: fitness_sessions 首写；
- **回滚注意**: 本提交含**删文件**，revert 会复活壳内 AI 旧实现并与 core_ai 现状冲突——
  不建议整提交回滚；如需回退语音/健身，手工摘除 voice/、fitness_service.dart 与对应装配。

---

## [2026-11-16] W3-4 AI 双解析闭环（文本路径）：core_ai 管线/缓存/FakeParser + 确认卡与降级

**类型**: feat
**提交**: 5b456e3
**风险**: MEDIUM

### 变更文件（apps/mobile，13 文件 +2370/-9）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/ai/ai_parser.dart | +362 | 壳内 LLM 解析第一版（后 W5-6 下移 core_ai） |
| lib/data/ai_capture_service.dart | +420 | AI 记账服务（解析→确认→落库，后由 feature_capture 接管） |
| lib/data/ai_parse_cache.dart | +100 | input_hash 缓存（后下移） |
| lib/ai/openai_compat_adapter.dart、fake_parser.dart、ai_parser_factory.dart | +235、+109、+44 | OpenAI 兼容传输+确定性 Fake+工厂 |
| lib/features/capture/capture_page.dart | +310/-若干 | 确认卡+失败降级接入 |
| lib/app/providers.dart | +21 | 解析器/服务装配 |
| pubspec.yaml | +4 | core_ai path 依赖 |
| test/ai_capture_service_test.dart（+291）、test/ai_parser_factory_test.dart（+202）、test/e2e_ai_confirm_test.dart（+233） | +726 | 工厂/服务/e2e |

### 影响范围
- **API**: 首次出现 AI 装配点（现已被 W5-6 收敛重构，读 code-patterns.md §2.1 现状即可）；
- **跨模块**: ⚠ 同一提交改 **packages/core_ai**（16 文件新建）、**packages/feature_capture**（3 文件）、**packages/ui_kit**（4 文件：呼吸态/count-up/确认卡）。

---

## [2026-11-16] W2 主线：day_summary 投影/仓储/seed + 手动记账 CRUD 全链路 + 仪表盘真页 + Riverpod 接线

**类型**: feat
**提交**: 1ee4ab4
**风险**: HIGH

### 变更文件（apps/mobile，13 文件 +2001/-122）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/app/bootstrap.dart | +165 | **bootstrap() 诞生**（开库/device_id/账本种子/装配清单） |
| lib/app/providers.dart | +51 | **DI 枢纽诞生**（appDatabase/hlcClock/entry/entryLine providers） |
| lib/data/drift_repositories.dart | +433 | DriftEntryRepository/DriftEntryLineRepository（业务行+outbox 同事务、软删墓碑、money 行不可变闸门、supersede 修正链） |
| lib/data/manual_entry_service.dart | +288 | 手动记账写路径（saveNew/editEntry/deleteEntry、kind 推导） |
| lib/common/format.dart | +43 | 分↔元/日历日标签换算 |
| lib/features/dashboard/today_dashboard_page.dart、dashboard_state.dart | +330/-若干、+215 | 仪表盘真页（卡片墙+周历条+reactive stream 聚合） |
| lib/features/capture/capture_page.dart | +272 | W2 表单（编辑路径 showCaptureSheet 前身，后迁 feature_capture） |
| lib/app/router.dart、lib/main.dart | +28/-若干、+11/-若干 | 真页挂载+async main |
| test/e2e_record_to_dashboard_test.dart（+165）、test/widget_test.dart | +280 | 记一笔→仪表盘 e2e |

### 影响范围
- **API**: 壳层 DI/写路径骨架成型——后续所有装配在此之上生长；
- **跨模块**: ⚠ 同一提交改 **packages/core_db**（13 文件：day_summary 投影/DAO）、**packages/feature_capture**（3 文件）、**packages/feature_dashboard**（2 文件）。

### 回滚指南
- 回滚: `git revert 1ee4ab4` 会拆除 bootstrap/DI/仓库骨架——后续 W3-16 全部依赖它，
  **只能整链回退**（W2 起所有提交一起）；单独 revert 必然编译失败。

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: feat
**提交**: 3b1f64c
**风险**: LOW（初始提交，无回滚目标）

### 变更文件（apps/mobile 部分，72 文件 +2480；全仓 11 包同建）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/main.dart、lib/app/router.dart、lib/app/theme.dart | +34、+124、+29 | App 壳骨架（4 Tab StatefulShellRoute + 底栏 + FAB + ui_kit 主题装配点） |
| lib/features/ledger/ledger_page.dart、lib/features/plan/plan_page.dart | +36、+34 | Tab 占位页 |
| android/、ios/ 平台工程 | 其余 | Flutter 平台脚手架 |

### 影响范围
单仓 10 包（core_db/core_domain/core_ai/ui_kit/feature_capture/feature_dashboard/
feature_ledger/feature_plan/feature_sync + apps/mobile）+ server/supabase 同一提交建立；
本模块一切文档描述的现状以此提交为地基。
