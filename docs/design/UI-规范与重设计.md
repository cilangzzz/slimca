# Slimca UI 规范与重设计（V1 插曲定稿）

> 日期：2026-11-17　|　状态：定稿（待评审拍板实现批次）
> 关联：`docs/design/产品设计文档.md` §4 信息架构 / §8 主题 token / §9 动效系统
> 范围：V1 新增优化体系插曲——①设置/菜单页重设计（移除「升级计划」露出）；②组件切换效果与布局约束体系化；③首页日历去「固定七天」。
>
> **总原则：本插曲不破坏既有 MotionConfig 与三层 token 架构（§8.2/§9.2），只做「补全」**——
> 既有五档时长 + 双弹簧全部保留（其数值均落在 M3 官方 50-1000ms 刻度与国内 Ant/Arco/TDesign
> 100-500ms 区间交集内，见 §1.1/§2.1 背书）；新增 token（间距尺度、触碰目标、状态层、
> 展开/收起曲线对）一律取官方刻度值。所有数字均有来源，推导项显式标注。

---

## 1. 规范摘录表（每条注来源）

### 1.1 动效时长档（官方刻度对照）

| 体系 | 档位 | 数值 | 来源 |
|---|---|---|---|
| M3（旧版 easing+duration） | short1-4 | 50 / 100 / 150 / 200ms | m3.material.io/styles/motion/easing-and-duration/tokens-specs；androidx compose material3 `MotionTokens.kt`（数值逐项一致）；material-web v0_192 `_md-sys-motion.scss` |
| M3 | medium1-4 | 250 / 300 / 350 / 400ms | 同上 |
| M3 | long1-4 | 450 / 500 / 550 / 600ms | 同上 |
| M3 | extra-long1-4 | 700 / 800 / 900 / 1000ms | 同上 |
| M3 官方用法示例 | — | 选择控件 200ms+standard；FAB→Sheet 400ms+emphasized；Card→全屏 500ms+emphasized；环境型轮播 1000ms+emphasized | 同上 |
| Ant Design | fast/mid/slow | 0.1 / 0.2 / 0.3s（motionUnit=0.1 ×1/×2/×3） | ant-design 仓库 `seed.ts` + `genCommonMapToken.ts`（源码验证） |
| Arco | @transition-duration-1..5 | 100 / 200 / 300 / 400 / 500ms | arco-design 仓库 `default.less`（源码验证） |
| TDesign 移动端 | base/moderate/slow | 100 / 120 / 140ms；参考区间移动端 100-400ms | tdesign.tencent.com/design/motion（官网摘录，未源码复核，落地前 devtools 复核） |
| Apple HIG Motion | — | **刻意不给毫秒数**，只有定性原则：有目的、可取消、跟随手势、高频交互不加动效、反馈「brevity and precision」 | developer.apple.com/design/human-interface-guidelines/motion（2026-09-09 版） |

**Slimca 落点**：现有 dur.xs60 / s120 / m180 / l280 / xl450 —— 60ms 落 M3 short1-2 档间、120ms=TDesign moderate 同值、180ms 落 short4-medium1 档间、280ms 落 medium1-2 档间、450ms=M3 long1 同值。**全部在官方刻度邻域内，保留不改**（改档会连带 §9.3 十条转场与 `MotionConfig.full/reduced/off` 三档全表重刻，收益为零、回归成本高）。

### 1.2 缓动曲线

| 曲线 | cubic-bezier / Flutter 实现 | 用途 | 来源 |
|---|---|---|---|
| M3 standard | (0.2, 0.0, 0, 1.0) | 小而简单的工具型过渡 | m3.material.io motion tokens-specs |
| M3 emphasized | Flutter 内置 `Curves.easeInOutCubicEmphasized`（ThreePointCubic，Android 路径 M0,0 C0.05,0 0.133,0.06 0.167,0.4 C0.208,0.82 0.25,1） | 容器变换/大形变；CSS/iOS 无对应时官方指定退回 standard | 同上 + flutter `curves.dart`（源码验证） |
| M3 emphasized-decelerate | (0.05, 0.7, 0.1, 1.0) | 展开/进场段 | MotionTokens.kt |
| M3 emphasized-accelerate | (0.3, 0.0, 0.8, 0.15) | 收起/出场段 | MotionTokens.kt |
| M3 standard-decelerate / accelerate | (0,0,0,1) / (0.3,0,1,1) | 降级备用 | MotionTokens.kt |
| M3 spring→曲线等价表（新版物理体系） | Expressive default spatial = (0.38, 1.21, 0.22, 1.00) 500ms；fast spatial = (0.42, 1.67, 0.21, 0.90) 350ms；Standard spatial = (0.27, 1.06, 0.18, 1.00) 350/500/750ms；effects（fast/default/slow）= (0.31,0.94,0.34,1.00) 150ms / (0.34,0.80,0.34,1.00) 200ms / (0.34,0.88,0.34,1.00) 300ms | spatial 用于位置/旋转/尺寸/圆角（**允许过冲**）；effects 用于颜色/透明度（**禁止过冲**）——这是「哪些动画该有回弹」的官方判定线 | m3.material.io/styles/motion/overview/specs（原表逐字提取） |
| antd easeOutQuint | (0.23, 1, 0.32, 1) | count-up/上浮收尾 | ant-design `seed.ts`（源码验证） |
| Arco overshoot | (0.3, 1.3, 0.3, 1) | 非弹簧回弹备选 | arco-design `default.less` |
| Apple 侧 | HIG 无数字口径；唯一官方弹簧 API = SwiftUI `Spring(duration:bounce:)`（示例 0.5/0.3），`.smooth/.snappy/.bouncy` 常量值官方文档未公布（社区熟知 0.5/0.0、0.3/0.15、0.5/0.3，**PLAUSIBLE，落地前用 SDK swiftinterface 复核**） | iOS 端时长借 M3 档位不与 HIG 冲突（Apple 仅要求 brevity/cancellable/跟手） | developer.apple.com/documentation/swiftui/spring |
| Flutter 页面转场（Zoom builder 源码） | 前进 scale 0.85→1.00、返回 1.10→1.00，曲线 fastOutExtraSlowIn TweenSequence；新页淡入 Interval(0.125,0.250)；scrim 0→0.60 Interval(0.2075,0.4175)；predictive back 450ms + `easeInOutCubicEmphasized`、旧页缩至 0.90 | 抄进自定义 PageRouteBuilder 的官方参数 | flutter `page_transitions_theme.dart`（源码验证） |

**Slimca 落点**：`curveStandard=Curves.easeInOutCubic`（共享轴）保留；`curveEmphasized=Curves.easeInOutCubicEmphasized`（容器变换）保留——后者即 M3 emphasized 官方指定实现。**新增**展开/收起曲线对（§2.2）：展开用 emphasized-decelerate (0.05,0.7,0.1,1)、收起用 emphasized-accelerate (0.3,0.0,0.8,0.15)，即 TDesign「进场 ease-out / 出场 ease-in」不对称规则的 M3 官方实现；同时补进 §9.1 作出/入场不对称纪律（出场不排队、整块消失，antd motion spec 原文）。

### 1.3 间距尺度（8dp 基准全档）

| token | 值 | 备注 | 来源 |
|---|---|---|---|
| M3 space0/25/50/75/100 | 0 / 2 / 4 / 6 / 8dp | space100=8dp 为基线 | m3.material.io/styles/spacing/tokens（官方枚举 18 值：0/2/4/6/8/10/12/14/16/20/24/32/36/40/48/56/64/72） |
| M3 space125/150/175/200 | 10 / 12 / 14 / 16dp | 16dp = M3 Expressive small button padding（原 24dp 改 16） | 同上 + m3.material.io/components/buttons/specs |
| M3 space250/300 | 20 / 24dp | 24dp = 官方 search 容器水平 margin（聚焦收窄 12dp） | m3.material.io/styles/spacing/overview |
| M3 space400/500/600 | 32 / 40 / 48dp | 区段间/页边大档 | spacing/tokens |
| TDesign Flutter spacers | 8 / 12 / 16 / 24 / 32 / 48 / 80 | 与 M3 档位同刻度，Flutter 端可直接对齐 | tdesign-flutter `t_spacers.dart`（源码验证） |
| 官方纪律 | — | 「组件少用 margin，优先 padding+gap」 | m3.material.io/styles/spacing/overview |

**Slimca 落点（新 spacingScale，§2.2）**：卡内 12 / 卡间与行内水平 16 / 分组间 24 / 页边 16-24 / 区块间 32——全部落在 M3 刻度，不发明新值。现有代码 12/16/20 间距已合规；主要违规项是页边距与触控间距（§5 审计）。

### 1.4 触碰目标与状态层

| 项 | 数值 | 来源 |
|---|---|---|
| 触摸目标（触屏） | ≥48×48dp（≈9mm，推荐 7-10mm；24dp 图标+留白凑 48dp 目标） | m3.material.io/foundations/designing/structure |
| 指针目标（鼠标/笔） | ≥44×44dp | 同上 |
| 目标间距 | ≥8dp | 同上 |
| Flutter 常量 | `kMinInteractiveDimension=48.0`（注释直引 material.io 无障碍规范） | flutter `constants.dart`（源码验证） |
| iOS 命中区 | ≥44×44pt（visionOS 60×60pt）；iOS/iPadOS 默认 44×44pt、最小 28×28pt | HIG buttons + HIG accessibility（2026-09-09 版） |
| 状态层透明度 | hover 0.08 / focus 0.10 / pressed 0.10 / dragged 0.16 / disabled 0.38（内容色）；状态层用 on 色、一次只叠一层；状态层视觉直径 40dp < 交互目标 48dp | m3.material.io/foundations/interaction/states/state-layers |
| lists 规格页 CSS 口径（并录） | hover 8% / active 10% / pressed 12%（rgb(31 25 35 / …)） | m3.material.io/components/lists/specs 页内 CSS 提取 |
| 按压形状 morph | M3 Expressive 允许按压 round→square；主 CTA 可用，列表行只做透明度变化 | m3.material.io/components/buttons/specs、icon-buttons/specs |

**Slimca 落点**：Android 优先统一 48dp 目标 + 8dp 间距；iOS 端命中区按 44pt（Flutter `IconButton` 等默认 48 已达标，无需分端特殊化，仅在自绘小控件注意）。状态层四档透明度全局统一，**不再逐组件手调按压色**——这是「组件切换效果没经过设计」的直接解药。disabled 口径：内容色 38%（states 页）为准，icon-buttons 页 10% 层并录备查。

### 1.5 行高与列表约束

| 项 | 数值 | 来源 |
|---|---|---|
| ListTile 行高（Flutter 实现，本项目以源码为准） | 1 行 56 / 2 行 72 / 3 行 88dp；dense 48 / 64 / 76dp | flutter `list_tile.dart`（源码验证；与 M3 spec 常见引用 96 有差异，以 Flutter 实现为准） |
| leading/trailing 视觉高度上限 | 40dp（dense 32）；可点击 leading/trailing 必须 ≥48×48 | 同上 + `constants.dart` |
| M3 菜单 tile | 高 56dp、选中指示器 StadiumBorder 336×56、tilePadding 水平 12dp、抽屉宽=屏宽−56dp 上限 320dp | flutter `navigation_drawer.dart` / `drawer.dart`（源码验证，引 material.io specs） |
| M3 日期格 | 视觉 40×40（material-web date-picker token）、命中 48×48（a11y 页原文 "Touch targets are 48x48dp"）；行高 48dp、内边距 4px、月网格最多 6 行 | flutter `calendar_date_picker.dart`（直引 m3.material.io date-pickers/specs）+ material-web v0_192 `_md-comp-date-picker-modal.scss`（日格 40×40、头部 120px、modal 容器 360×568） |
| M3 组件尺寸 | NavigationBar 容器 80 / active indicator 32；FAB 56×56 图标 24；Switch 轨道高 32 手柄 16；底部抽屉 drag handle 4×32 | material-web 组件 token 源文件（_md-comp-navigation-bar / -fab-primary / -switch / -sheet-bottom） |
| 列表性能 | 长列表 ListView.builder + 固定行高传 itemExtent/prototypeItem（异构用 itemExtentBuilder） | docs.flutter.dev cookbook long-lists |
| RefreshIndicator | displacement=40、strokeWidth=2.5、触发阈值 0.25×容器 extent、snap 150ms / scale 200ms | flutter `refresh_indicator.dart` + `progress_indicator.dart`（源码验证） |

### 1.6 无障碍硬阈值

| 项 | 数值 | 来源 |
|---|---|---|
| 正文对比度 | ≥4.5:1（大字 ≥18pt/24px 或 ≥14pt bold ≥3:1） | WCAG 2.2 SC 1.4.3 |
| 非文本 UI 组件/图形 | ≥3:1 → 主题编辑器校验补一条：热量环、置信度点按 3:1 校验而非 4.5 | WCAG 2.2 SC 1.4.11 |
| 交互触发动效可关闭 | SC 2.3.3；视差滚动被点名为非必要动效 | WCAG 2.2 SC 2.3.3 |
| 系统减弱动效信号 | `MediaQueryData.disableAnimations`（Android「移除动画」）与 `dart:ui AccessibilityFeatures.reduceMotion`（iOS 独立开关）；框架隐式动画自动遵守，**自定义显式动画必须自查降级** | api.flutter.dev MediaQueryData.disableAnimations |
| Apple Reduce Motion 官方五条降级 | ①收紧 spring 弹性（减 bounce）②动画直接跟随手势③不做 z 轴深度动画④x/y/z 位移转场改 fade⑤不动画 blur 进出 | HIG accessibility |

**日历对比度**：M3 date picker accessibility 页硬指标——日期文字对比度 ≥4.5:1（进 §3 组件参数）。

---

## 2. MotionConfig 补全（不破坏原则）

### 2.1 既有 token 保留判定（结论：全保留）

| 既有 token | 现值 | 官方刻度锚 | 判定 |
|---|---|---|---|
| dur.xs 60ms | 微反馈 | M3 short1-2（50-100）档间 | 保留 |
| dur.s 120ms | chip/勾选 | =TDesign moderate；short3-4 档间 | 保留 |
| dur.m 180ms | 卡片上浮 | short4-medium1（200-250）邻域 | 保留 |
| dur.l 280ms | 抽屉/页面/共享轴 | medium1-2（250-300）档间 | 保留（TDesign 移动端参考区间 100-400ms 内） |
| dur.xl 450ms | 落库飞入/容器变换 | =M3 long1 450ms 同值 | 保留（M3 Card→全屏示例 500ms+emphasized，450 同档相邻，不追平） |
| spring.snappy 220ms ζ1.0 | 交互跟随不回弹 | M3 Standard fast spatial 350ms 曲线 (0.27,1.06,0.18,1.00) 为等价参考 | 保留 |
| spring.soft 400ms ζ0.85 | 容器变形/环推进 | M3 Expressive default spatial 500ms 曲线 (0.38,1.21,0.22,1.00) 为等价参考（轻微过冲，语义一致） | 保留 |
| staggerInterval 80ms | 级联间隔 | 落 short2（100ms）档内 | 保留 |
| countUpDuration 800ms | AI count-up | =M3 extra-long2 800ms 同值；曲线可换 antd easeOutQuint (0.23,1,0.32,1) 收尾更顺（现 easeOutExpo 亦合规，P2 择一） | 保留 |
| themeMorphDuration 300ms | 主题 morph | =M3 medium2 300ms 同值 | 保留 |
| offFadeDuration 100ms | off 降级淡入淡出 | =M3 short2 100ms 同值（调研二确认此值正确） | 保留 |
| MotionLevel off/reduced/full + 0.6x-1.5x 滑杆 | §9.2/§8.3 | 与 Apple Reduce Motion 五条同构（§2.3） | 保留 |

### 2.2 新增 token 表（增量补全，进三层架构）

**进 ui_kit token 层**（第 2 层语义 token / MotionConfig 增量字段，第 3 层组件只引用）：

| 新 token | 值 | 语义 | 来源 |
|---|---|---|---|
| `SlimcaSpacing`（新 ThemeExtension 或 SlimcaTheme 增量字段） | space50=4 / space100=8 / space150=12 / space200=16 / space250=20 / space300=24 / space400=32 / space600=48 | 间距只取 M3 刻度 8 档（够用原则，不搬全 18 档） | M3 spacing/tokens + TDesign t_spacers |
| `minTouchTarget` | 48dp | 全局触碰底线（常量进 ui_kit） | M3 structure + flutter kMinInteractiveDimension |
| `stateLayerHover/Focus/Pressed/Dragged` | 0.08 / 0.10 / 0.10 / 0.16 | 状态层透明度统一四档（on 色叠加，一次一层） | M3 state-layers |
| `curveExpand`（MotionConfig 增量） | `Cubic(0.05, 0.7, 0.1, 1.0)`（emphasized-decelerate） | 展开/进场段（周条→月网格、条目级联进场收尾） | MotionTokens.kt |
| `curveCollapse`（MotionConfig 增量） | `Cubic(0.3, 0.0, 0.8, 0.15)`（emphasized-accelerate） | 收起/出场段 | MotionTokens.kt |
| `curveEffectsStandard`（MotionConfig 增量） | `Cubic(0.34, 0.80, 0.34, 1.00)` 200ms（expressive default effects） | 颜色/透明度类动画专用（禁过冲判定线的实现载体） | m3 motion/overview/specs |

新增曲线对在 `MotionConfig.reduced` 下随 0.6x 时长照常缩放；在 `off` 档照既有惯例线性化为 `Curves.linear`（不改 offFadeDuration=100ms 语义）。

**进组件默认值**（不造 token，框架默认即合规）：ListTile 行高 56/72、Switch 轨道/手柄、NavigationBar 80/32、RefreshIndicator 40/2.5、IconButton 48 命中、InkWell 状态层（Flutter 默认 overlay 透明度与 8/10/16% 口径一致，自绘组件才需显式引用 token）。

### 2.3 MotionLevel 降级映射（Apple Reduce Motion 五条 → Slimca 实现）

| HIG 原则 | Slimca 落法 |
|---|---|
| 收紧 spring 弹性 | MotionLevel=reduced 已 ×0.6 缩短整定时长（等效减 bounce）；full 档 spring.soft ζ0.85 保持 |
| 动画跟随手势 | 录入抽屉弹簧 sheet 速度继承已有（§9.3#3）；周条↔月网格展开手势驱动进度（拖拽跟手，松手才补 280ms 补间） |
| 不做 z 轴深度动画 | Zoom 转场（scale 深度感）在 reduced 档换 fade；predictive back 缩放同理 |
| x/y/z 位移转场改 fade | MotionLevel=off 全部转场 100ms 淡入淡出（既有语义，已对齐 HIG 第④条） |
| 不动画 blur 进出 | off/reduced 档禁 blur 过渡（§8.3「去视差/去模糊」已有，补录此条为 HIG 出处） |

系统开关接线：`MediaQuery.of(context).disableAnimations || AccessibilityFeatures.reduceMotion` → 强制 MotionLevel.reduced（0.6x + 去视差去模糊）。off 档映射 Android「移除动画」。

---

## 3. 首页日历重设计定稿（痛点③）

### 3.1 选型与理由

**选定组合：周条（改造为无限横滑）＋ 垂直手势展开月网格（形变式，非翻页）＋ 今日锚定簇，三视图共享 `selectedDateProvider` 单一真值。**

淘汰/搁置项与理由：

| 备选 | 判定 | 理由 |
|---|---|---|
| 固定七天横条（现状） | 淘汰 | 无限翻周都没有（`_WeekStrip` 固定 7 格 Row，today_dashboard_page.dart:145-218，注释自述月历下钻未实现）——「只有七天太死板」的根源 |
| M3 modal date picker 全屏弹窗 | 淘汰作首页形态 | 首页日历是常驻导航组件不是表单输入；modal 解剖（headline+星期标签+前后月箭头+48dp 格）只借其结构进月网格 |
| TDesign switchMode 翻页式切换 | 搁置 | 翻页式无高度形变连贯性，与「周条即月网格折叠态」的体验差一档 |
| Things 3 粒度递进列表（近 7 日逐日/远期按周/月分组） | P1 放统计/计划页 | 与首页卡片墙语义重叠；首页以「月网格+卡片墙=agenda」构图解决密度（Google Calendar 月网格下方当日聚合列表为业界共识构图——月网格只替换现周条位置，卡片墙即天然 agenda，无需另造列表） |
| 横屏进周视图（Apple/Fantastical 双官方） | P2 彩蛋 | 不在 V1 范围 |

**为什么选形变式**：①手势样板有官方背书——Fantastical DayTicker（flexibits.com 官方帮助原文）：周条横滑换日且下方 schedule 同步、周条**下拉展开迷你月历**、月历左右滑翻月仍同步 schedule；②实现方案成熟——table_calendar 的 `CalendarFormat{week, twoWeeks, month}` + `onFormatChanged` 高度形变（56→28×行数）是 Flutter 生态事实标准；③与既有转场投资正交——水平=切日/翻周/翻月（走 §9.3#2 SharedAxis），垂直=形态切换（新曲线对），两轴手势不打架；④单选中日状态驱动一切（Fantastical 原文语义）：切视图永不产生第二次日期选择。

### 3.2 交互规格

**手势阶梯**（对齐 Fantastical，不引入 modality 冲突）：

| 手势 | 作用 | 动效 |
|---|---|---|
| 周条/月网格 水平拖（或点格） | 切日（周条）/ 翻月（月网格） | SharedAxis X 轴，dur.l 280ms + curveStandard（现 §9.3#2 token 不变） |
| 周条 下拉（或点月历图标） | 折叠态 → 月网格展开 | 高度形变 280ms（=dur.l）+ curveExpand (0.05,0.7,0.1,1)；拖拽阶段跟手，松手补间（HIG「跟随手势」） |
| 月网格 上拉（或点收起箭头） | 月网格 → 折叠周条 | 280ms + curveCollapse (0.3,0.0,0.8,0.15) |
| 月网格 再下拉到底 | （P2）全屏月历视图 | 500ms emphasized 容器变换，V1 不做 |
| 点任意日格 | selectedDate ← 该日；卡片墙即时随 key 切换（`SlimcaSharedAxisSwitcher` 既有机制） | 与切日同一转场，无第二次选择 |

**与现有手势的区分**：现页面 `onHorizontalDragEnd`（velocity>120 切日，today_dashboard_page.dart:69-78）保留在卡片墙区域；周条自身改为 `PageView` 无限横滑**翻周**（offset 无界双向），点格才切日——横滑在周条上=翻周、在卡片墙上=切日，与 Fantastical「周条横滑换日+下方同步」略有出入，取更保守的「翻周不切日」，避免与卡片墙切日手势在同一屏幕上双重语义打架（此条为设计决策，标注非规范出处）。

**今日锚定簇**（Notion Calendar 官方帮助：前后箭头夹 Today 按钮）：月网格头部行 `[‹] 2026年11月 [›] [今天]`；周条折叠态头部=现 `_DateHeader` 大字右侧追加「今天」pill，**横滑离开今天后浮现**（轻量可见性，800ms 内自动出现不做常驻）；点击=selectedDate 重置到今天 + 卡片墙滚顶，附 280ms SharedAxis 回位（与转场 #2 同 token）。

**月格信息密度三档**（Apple 日历官方 Compact/Stacked/Details，iPhone User Guide 原文；V1 只做 Compact）：
- Compact（默认）：每格 ≤3 个色点+溢出点（色点=当天有记录，上限 3 为常见实现观察，标注推导非规范）；
- Stacked（P1）：每条记录一个色条（ledger 分类色）；
- Details（P2）：格内显示标题文字。

### 3.3 组件参数（定稿数值）

| 项 | 值 | 来源/依据 |
|---|---|---|
| 周条折叠态高度 | 72dp（两行 14/16px 文字+8dp padding；推导值，标注非规范原文） | 容纳星期标签+日期号+今日点（现结构） |
| 周条日格命中 | ≥48×48dp；格间距 ≥8dp（**现 3px 水平 padding 违规，§5 修正**） | M3 触碰目标 + 间距规范 |
| 月网格日期格 | 视觉 40×40dp、命中 48×48dp、月网格最多 6 行 | M3 date-picker token（material-web 40×40）+ a11y 48dp |
| 日期文字对比度 | ≥4.5:1 | M3 date-pickers/accessibility |
| 今天=primary 对比色、选中日=primary container 填充、有记录日=secondary container 色点 | 沿用现 `primaryContainer` 选中语义 + Material 色语义 | M3 date picker guidelines；现代码已用 primaryContainer（合规保留） |
| 星期标签行 | 不可聚焦（accessibility） | M3 modal 解剖 |
| 展开/收起 | dur.l 280ms + curveExpand/curveCollapse（新 token） | M3 emphasized-decel/accel + medium 档 |
| 状态层 | pressed 10% on 色（ InkWell 默认即合规） | §1.4 |

**实现载体建议**：`table_calendar`（CalendarFormat week/month 形变 + onFormatChanged）或在其之上手写保持与 `SlimcaSharedAxisSwitcher` 的 key 语义一致；数据源=现有 `day_summary` 聚合直出（§5.6⑬），月格色点由 `dashboardDayProvider` 扩展月度查询（实现细节留 W17 拆解）。

---

## 4. 菜单/设置页重设计定稿（痛点①）

### 4.1 IA 分组（移除「升级计划」后）

参照 iOS 18 Settings 三层结构（9to5Mac 等评测一致：账号卡顶层→功能分组中层→低频尾部）：

```
我的
├─ 顶部账号/同步卡（非 ListTile）：同步状态只读一行 + 头像位
│   └─ Pro 状态收进此卡一行小字 pill（不占整行；无购买时不显示）
├─ 分组「数据与隐私」：原文上云开关 / 拍照原图即焚开关（现两 SwitchListTile 原样迁入）
├─ 分组「外观」：主题（副标题=当前包名·深浅色，现入口迁入；动效等级并入主题编辑面板内，不单列）
├─ 分组「数据」：同步（现 ListTile 迁入）/ 数据导出
└─ 尾部低频组（与上方隔 Divider）：关于 / 版本 / 清空数据（危险项，§4.3）
```

**「升级计划」移除决策**：`_SectionHeader('升级 Slimca Pro')` + `_PaywallSection` 整块从主列表移除（settings_page.dart:219-227）。**IAP 抽象代码保留不删**（billing_provider/billing_service/sku_catalog 及测试锚点原样），UI 不露出；转化触点收敛到 AI 免费额度耗尽的降级提示（设计文档 §7.4 已有该触点）。调研明确标注：「升级计划」移除属产品决策、无规范出处可引——此为本文件的产品拍板项，非规范引用。

### 4.2 行组件规格（M3 ListTile 口径）

| 项 | 定稿值 | 来源 |
|---|---|---|
| 行高 | 单行 56dp / 两行（标题+副标题）72dp；不用 dense | flutter list_tile.dart |
| leading 图标 | 视觉 24dp，容器按 48dp 命中布局；视觉上限 40 | M3 structure + list_tile.dart |
| 行内水平 padding | 16dp（M3 Expressive small padding）；分组卡内 tile 水平 12dp（NavigationDrawer 口径，二选一：卡内 12、无卡平铺 16——定稿用分组卡→12） | buttons/specs + navigation_drawer.dart |
| trailing | 导航类=chevron_right 24dp；状态类=Switch（轨道 32/手柄 16）或 pill；pill 不进对比度禁区（WCAG 3:1） | 组件 token + WCAG SC 1.4.11 |
| 字号 | 行标题 Title Medium 16/24/500；副标题 Body Medium 14/20/400 onSurfaceVariant；分组头 Label Large 14/20/500 | m3 type scale（lists/specs CSS 提取） |
| 按压反馈 | 统一 pressed state layer 10% on 色（InkWell 默认），不逐行调色 | §1.4 |
| 分组卡 | 圆角 12（M3 shape medium）、卡底 surfaceCard、组间 24dp、页边 24dp（space300）、组内行间 0（由行高自撑） | M3 shape scale + spacing tokens |
| 现页修正 | Divider(height:1) 平铺 → 分组卡；`_SectionHeader` titleSmall → Label Large 14/500 口径 | §5 审计 |

### 4.3 危险项与付费触点

| 项 | 定稿 | 来源 |
|---|---|---|
| 清空数据/解除同步类入口 | 尾部独立分组 + **红色文字按钮**（不做填充块——红色文本弱于主操作的层级原则）+ 与相邻组隔 Divider | HIG Alerts + Refactoring UI 层级原则 |
| 确认弹窗 | Cancel 不做默认按钮 + 按钮用具体动词（「清空」不用「OK」） | HIG alerts |
| 常规单条删除（流水/记录） | 不弹窗，走 snackbar undo（可撤销动作不用 alert）——现 `_EntryTile` 删除立即软删，补 undo | HIG alerts |
| 恢复购买 | 收进「关于」分组仅当已有购买记录时显示状态行；裸入口随付费墙一并移出 | §4.1 决策 |

### 4.4 页面转场

| 动作 | 转场 | token |
|---|---|---|
| 行点击 → 二级页（导出等） | SharedAxis | dur.l 280ms + curveStandard（现 /settings/* 路由口径不变） |
| 主题入口 → 主题编辑面板 | 保留现弹簧面板（showThemeEditorPanel）；P1 升容器变换 450ms emphasized（§4.3 路由表既有语义） | spring.snappy / dur.xl |
| 开关/滑杆切换 | effects 类 200ms 无过冲（现 SwitchListTile 框架默认即合规；自绘控件引用 curveEffectsStandard） | M3 选择控件 200ms+standard 口径 |
| 条目级联进场 | 80ms stagger 保留（short 档内） | staggerInterval |
| 抽屉/弹层 | 现弹簧 sheet 不动（速度继承=HIG 可取消+跟手双达标） | spring.snappy |

---

## 5. 组件切换与约束审计清单（逐类修正表）

「归处」列：**token**=进 ui_kit 三层架构（SlimcaSpacing/MotionConfig 增量/新常量）；**默认值**=组件框架默认已合规或组件内固化，不进 token。

| # | 组件（代码位置） | 类别 | 现值 | 规范目标 | 修正动作 | 归处 |
|---|---|---|---|---|---|---|
| 1 | `_DashboardCard`（today_dashboard_page.dart:1001） | 卡片 | radius 16 / padding 16 / surfaceCard | M3 large=16 ✓、space200=16 ✓ | 无需改（合规基线）；卡间距 12（space150）保留 | 默认值（间距取值改引 SlimcaSpacing） |
| 2 | `_WeekStrip` 日格（:145-218） | 日历 | 水平 padding 3px；AnimatedContainer durM 180ms+easeOutCubic | 间距 ≥8dp；选中态=颜色变化（effects 禁过冲） | 间距改 8dp 档（视觉 gap 4 + 命中留白）；动画合规保留；补无限翻周 PageView | token（minTouchTarget/间距）；默认值（动画） |
| 3 | `_DateHeader`（:101-139） | 卡片 | 裸值 `Duration(milliseconds: 400)` + easeOutBack（**违反 §9.2 lint 禁裸值**） | spring 展开语义 | 改读 `MotionConfig.of(context)`（springSoft.curve 或 durXl+easeOutBack 语义挂 token） | **token（修 lint 违规）** |
| 4 | `_EntryTile`（:905-950） | 列表项 | dense ListTile（48-64 命中 ✓）；删除立即软删无 undo | 行高 56/72 标准档；可撤销删除走 undo | dense→标准 56/72（副标题行）；补 snackbar undo | 默认值（ListTile）；默认值（undo 交互） |
| 5 | 支出卡预算行 InkWell（:597-665） | 列表项 | vertical padding 2 → 命中 <48dp | 命中 ≥48×48 | 包 48dp 最小命中容器（minTouchTarget） | token→组件默认值固化 |
| 6 | `showCaptureSheet`（spring_sheet.dart） | 抽屉 | spring.snappy 220ms ζ1.0、速度继承、可拖拽反向 | HIG 可取消+跟手 ✓ | 保留不动 | —（合规） |
| 7 | 设置页 `Divider(height:1)` 平铺（settings_page.dart:179-257） | 列表容器 | 无分组、无卡片 | 分组卡 12 圆角/组间 24/页边 24 | §4.1 IA 重排 + §4.2 行规格落地 | token（SlimcaSpacing/shape） |
| 8 | `_SectionHeader`（settings_page.dart:263） | 分组头 | titleSmall | Label Large 14/20/500 | 换 textTheme 口径 | 默认值 |
| 9 | `SlimcaSharedAxisSwitcher/PageRoute`（shared_axis.dart） | 页面转场 | durL 280ms + easeInOutCubic | M3 medium1-2 档间 ✓ | 保留 | —（合规） |
| 10 | `SlimcaCalorieRing`（calorie_ring.dart） | 进度 | spring.soft 400ms ζ0.85 sweep | spatial 类（几何弧）允许过冲 ✓ | 保留 | —（合规） |
| 11 | `_SavingsCard` 进度条（today_dashboard_page.dart:855-868） | 进度 | TweenAnimationBuilder durM+easeOutCubic | effects 类禁过冲 ✓ | 保留 | —（合规） |
| 12 | `SlimcaStaggerItem`（stagger.dart） | 级联 | 80ms 间隔 | short 档内 ✓ | 保留 | —（合规） |
| 13 | `confirm_card` / `theme_editor_panel` | 弹层 | 框架默认过渡 | 弹层 fade/scale short-medium 档；弹层进出场不对称（出快于进） | 补 curveExpand/curveCollapse 进出场对 | token（新曲线对首批使用方） |
| 14 | 底部 NavigationBar（router.dart） | Tab | Flutter M3 默认（容器 80/indicator 32） | 官方值一致 ✓ | 保留 | 默认值 |
| 15 | `RefreshIndicator`（ledger_page 等） | 刷新 | 默认 displacement 40/strokeWidth 2.5 | 官方值一致 ✓ | 保留 | 默认值 |
| 16 | `capture_recent_chips` | chip | chip/勾选 durS 120ms | short 档 ✓；chip 命中 ≥48×48 | 检查 chip 视觉高度与命中区（chip 视觉 32 级 + 外扩命中） | 默认值（命中外扩组件化） |
| 17 | 月历下钻 `/calendar`（§4.3 P0） | 容器变换 | 450ms spring.soft（§9.3#6 未实现） | M3 Card→全屏 500ms+emphasized；现 450=long1 同值 | 按 §3 组合实现时保持 dur.xl 450 + curveEmphasized（easeInOutCubicEmphasized 即 M3 emphasized 官方实现） | token（合规） |
| 18 | 状态层全局 | 反馈 | InkWell 默认 splash | hover 8%/focus 10%/pressed 10%/dragged 16% 统一口径 | 自绘组件显式引用 stateLayer token；框架组件默认已合规 | token（stateLayer 四档） |

**审计结论**：违规项 3 处——①`_DateHeader` 裸时长（lint 应拦未拦，补 lint 规则）；②周条日格间距 3px < 8dp；③支出卡预算行命中 <48dp。其余既有动效/组件全部在官方档位内，本插曲是「补全体系」而非「推翻重做」。

---

## 6. 落地批次建议（W17 插曲拆分）

| 批次 | 内容 | 依赖 |
|---|---|---|
| B1 token 补全 | SlimcaSpacing + minTouchTarget + stateLayer 四档 + curveExpand/curveCollapse/curveEffectsStandard 挂 MotionConfig（full/reduced/off 三档同步）+ §5 #3 lint 修复 | 无 |
| B2 设置页重排 | §4.1 IA 分组卡 + 移除升级计划露出 + 危险项分组 + undo snackbar（IAP 代码保留） | B1 |
| B3 日历重做 | 周条无限翻周 + 垂直展开月网格 + 今日锚定簇 + 月格色点（day_summary 月度查询） | B1 |
| B4 审计清零 | §5 #2/#5 命中与间距修正 + chips 命中外扩 + golden 快照更新（6 包×深浅） | B1-B3 |

每批次过 §9.4 性能预算与 §9.6 golden 三关键帧（0%/50%/100%）CI 闸门，纪律不变。

---

## 附：主要来源清单

- M3 动效：https://m3.material.io/styles/motion/easing-and-duration/tokens-specs · https://m3.material.io/styles/motion/overview/specs · androidx `MotionTokens.kt`（androidx-main）· material-web v0_192 `_md-sys-motion.scss`
- M3 状态层：https://m3.material.io/foundations/interaction/states/state-layers · lists/specs 页 CSS
- M3 间距：https://m3.material.io/styles/spacing/tokens · /overview · TDesign `t_spacers.dart`
- 触碰目标：https://m3.material.io/foundations/designing/structure · flutter `constants.dart` · HIG buttons / accessibility
- 行高列表：flutter `list_tile.dart` / `navigation_drawer.dart` / `drawer.dart` / `calendar_date_picker.dart` / `refresh_indicator.dart` / `page_transitions_theme.dart`（均源码验证）· material-web 组件 token（navigation-bar/fab/switch/sheet-bottom/date-picker-modal）
- 日历：M3 date-pickers（overview/guidelines/specs/accessibility）· HIG pickers · table_calendar README · Fantastical 官方帮助（flexibits.com）· Apple iPhone User Guide（日历密度三档）· Notion Calendar 官方帮助（Today 按钮）
- 国内体系：ant-design `seed.ts`/`genCommonMapToken.ts` · arco `default.less` · tdesign.tencent.com/design/motion（未源码复核，标注）
- 无障碍：WCAG 2.2 SC 1.4.3/1.4.11/2.3.3 · api.flutter.dev `MediaQueryData.disableAnimations` · HIG accessibility（Reduce Motion 五条）
- IA/交互样板：iOS 18 Settings（9to5Mac 等）· HIG alerts · antd motion spec（出/入场不对称）
- 不可验证项（诚实声明）：SwiftUI `.smooth/.snappy/.bouncy` 常量值（官方 JSON 未含数字，PLAUSIBLE）；iOS 默认 layout margin 数值（官方仅配图）；M3 date picker 容器总尺寸与按钮各档高度（仅在规格图内）；周条折叠高度 72dp、月格色点上限 3、周条横滑=翻周不切日——为本文件设计推导，已逐条标注。
