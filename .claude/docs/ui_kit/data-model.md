# ui_kit 数据模型 — 设计 token 体系全景

> 记录 token 分层、全量数值、装配管线与持久化形状。组件用法见 [api-components.md](api-components.md)，坑点见 [pitfalls.md](pitfalls.md)。

## 1. 三层架构（§8.2）

```
L1 原始色板   SlimcaPalette（4 组 HCT TonalPalette，0-100 全色阶）
                │  SlimcaTheme.fromPalette(p, brightness)  ← 唯一推导入口（W1 基线表，不含护栏）
                ▼
L2 语义 token  SlimcaTheme（色彩）+ MotionConfig（动效）+ SlimcaSpacing（间距）+ SlimcaSizes（尺寸）
                │  全部为 ThemeExtension，由 buildTheme 挂进 ThemeData
                │  组件层只允许读本层 + ColorScheme/TextTheme
                ▼
L3 组件层     语义组件 / 转场（读取入口 context.slimca / motion / spacing / sizes）
```

双主色锚定（换肤不换认知）：**健康绿色相 150 = 热量（kcalIn/kcalOut/net），暖橘色相 62 = 金额（moneyIn/moneyOut）**。色相在所有主题包、编辑器（`lockedHue`）、动态色映射（kcal/money 不映射平台色）三处强制锁定；danger 色相 27、neutral 色相 250（chroma 8，中性蓝灰）不锚定。

## 2. L1：SlimcaPalette（src/tokens/palette.dart）

| 锚点 | hue | chroma（默认档） | 语义 |
|------|-----|------|------|
| kcal | 150 | 55 | 热量（健康绿） |
| money | 62 | 68 | 金额（暖橘） |
| danger | 27 | 72 | 危险 |
| neutral | 250 | 8 | 背景/正文基底 |

- `SlimcaPalette.defaults`：内置默认色板（`SlimcaTheme.light/dark` 静态基线的推导来源）。
- `SlimcaPalette.fromSeeds({kcalSeed, moneySeed, dangerSeed, neutralSeed})`：种子色 → `TonalPalette.fromHct`（主题编辑器/自定义包入口）。
- 取色：`kcalTone(tone)` / `moneyTone` / `dangerTone` / `neutralTone`（tone 0-100）。

## 3. L2-色彩：SlimcaTheme（src/tokens/slimca_theme.dart）

16 个色彩字段 + 4 个滑杆系数：

| 字段 | 浅色 tone（默认推导） | 深色 tone | 语义 |
|------|------|------|------|
| surface | neutral 98 | neutral 6 | 页面基底 |
| surfaceMuted | neutral 94 | neutral 12 | 次级背景 |
| surfaceCard | neutral 100 | neutral 16 | 卡片底 |
| onSurface | neutral 10 | neutral 90 | 正文 |
| onSurfaceMuted | neutral 40 | neutral 70 | 次级正文 |
| outline | neutral 50 | neutral 50 | 描边 |
| primary / onPrimary | kcal 40 / kcal 100 | kcal 80 / kcal 20 | 交互锚点 |
| kcalIn / kcalOut / net | kcal 40 / 70 / 30 | kcal 80 / 60 / 85 | 热量语义 |
| moneyIn / moneyOut | money 70 / 40 | money 85 / 70 | 金额语义 |
| success / warn / danger | kcal 40 / money 55 / danger 45 | kcal 80 / money 75 / danger 80 | 状态 |

滑杆：`radiusScale` / `density` / `fontScale` / `motionScale`（默认 1.0；motionScale 量程 0.6-1.5 由 MotionConfig 消费）。

关键口径（详见 [pitfalls.md](pitfalls.md) 第 4 条）：
- `SlimcaTheme.light/dark` 静态基线 = `fromPalette` 原始推导，**不含** WCAG AA 护栏（W1 零漂移承诺，与壳层复刻表逐值相等，是 W16 测试锚点）。
- AA 降级只发生在装配出口：`buildTheme` / `ThemeProfile.toSlimcaTheme` / `SlimcaDynamicThemeMapper.map`（第 6 节）。
- `ThemeExtensionTween<T>`：SDK 未内置，自实现 lerp，供单 token 集显式动画。

## 4. L2-动效：MotionConfig（src/tokens/motion_config.dart）

### 4.1 时长 token（full 档原值）

| token | 值 | 用途语义位 |
|------|-----|------|
| durXs | 60ms | 微反馈（按压涟漪） |
| durS | 120ms | chip / 勾选 |
| durM | 180ms | 卡片上浮 |
| durL | 280ms | 抽屉 / 页面 / 共享轴（切日预算 ≤280ms） |
| durXl | 450ms | 落库飞入 / 容器变换（≤450ms） |
| staggerInterval | 80ms | 卡片墙级联间隔 |
| countUpDuration | 800ms | AI count-up |
| themeMorphDuration | 300ms | 主题 morph |
| offFadeDuration | 100ms | off 档统一淡入淡出（不随滑杆缩放） |

具名语义位：`microFeedback/chipCheck/cardFloat/drawer/page/sharedAxis/containerTransform/heroFlight/cascadeInterval/countUp/themeMorph/fadeOff`——业务按用途取值，防错档。

### 4.2 弹簧（SlimcaSpring：整定时长 + 阻尼比表达）

| token | 整定 | ζ | 用途 |
|------|------|-----|------|
| springSnappy | 220ms | 1.0（不回弹） | 交互跟随（抽屉 ≤280ms 预算内收敛） |
| springSoft | 400ms | 0.85（微回弹） | 容器变形 / 环推进 |

数学口径：ζ·ωn·T=2π ⇒ 整定时刻残差 ≈ e^(-2π) ≈ 0.19%。API：`description` / `simulation(start,end,velocity)`（拖拽速度继承）/ `curve`（`SpringCurve` 解析二阶响应，与 simulation 数值一致）/ `scaled` / `lerp`。

### 4.3 曲线 token

| token | 值 | 判定线（详见 pitfalls 第 3 条） |
|------|-----|------|
| curveEaseOutExpo | Curves.easeOutExpo | count-up |
| curveStandard | Curves.easeInOutCubic | 共享轴 / 页面级 |
| curveEmphasized | Curves.easeInOutCubicEmphasized | 容器变换 |
| curveExpand | Cubic(0.05,0.7,0.1,1.0)（M3 emphasized-decelerate） | 展开/进场段（spatial，可过冲） |
| curveCollapse | Cubic(0.3,0.0,0.8,0.15)（M3 emphasized-accelerate） | 收起/出场段（spatial） |
| curveEffectsStandard | Cubic(0.34,0.80,0.34,1.00)（M3 Expressive effects） | 颜色/透明度类动画专用，**禁过冲** |

### 4.4 档位与缩放

- `MotionLevel { off, reduced, full }`；`off` = 全部转场 100ms 线性淡入淡出 + 曲线线性化；`reduced` = 时长 ×0.6（曲线本体不变）；滑杆 `motionScale` 量程 0.6-1.5，只缩放时长/弹簧（`offFadeDuration` 恒 100ms）。
- 合成入口：`MotionConfig.forLevel(level, motionScale:)`（off 不叠滑杆）；`scaled(factor)` 缩放后按毫秒粒度取整（168ms×1.3 → 218ms）。
- 常量：`MotionConfig.full / reduced / off` 三预设 + `MotionConfig.of(context)`（与 `context.motion` 同回退逻辑）。

## 5. L2-约束 token：SlimcaSpacing 与 SlimcaSizes（W17 插曲新增）

### 5.1 SlimcaSpacing（8 档，全部 M3 官方刻度值）

| canonical | 值 | 梯度别名 | 语义位 |
|------|-----|------|------|
| space50 | 4 | xs | 色点直径、微内衬 |
| space100 | 8 | s | 基线：目标间最小间距 ≥8、图标-文字间 |
| space150 | 12 | m | **cardInner**：卡内 padding / 分组卡 tile 水平 |
| space200 | 16 | l | **inline**：行内水平 / 卡间 |
| space250 | 20 | — | 宽松备选档（仅按 canonical 名取用） |
| space300 | 24 | xl | **groupGap** 与 **pageMargin**：组间 / 页边 |
| space400 | 32 | xxl | **sectionGap**：区块间 |
| space600 | 48 | — | 大区段（亦 minTouchTarget 量级） |

### 5.2 SlimcaSizes（全部官方刻度值或显式标注的推导值）

| 字段 | 值 | 依据 |
|------|-----|------|
| minTouchTarget | 48 | 触屏命中下限（M3/flutter kMinInteractiveDimension） |
| pointerTarget | 44 | 指针目标下限 |
| targetGap | 8 | 相邻目标最小间距 |
| iconVisual / iconVisualMax | 24 / 40 | 图标视觉尺寸 / 上限 |
| rowSingleLine / rowTwoLine / rowThreeLine | 56 / 72 / 88 | 行高（flutter list_tile 口径，不用 dense） |
| dayCellVisual | 40 | 月格视觉 40×40（material-web token） |
| weekStripHeight | 72 | 周条折叠态高度（推导值，已标注） |
| radiusCard / radiusGroupCard | 16 / 12 | 卡片 / 分组卡圆角（M3 shape large/medium） |
| monthGridMaxRows | 6 | 月网格最多 6 行 |
| stateLayerHover/Focus/Pressed/Dragged | 0.08/0.10/0.10/0.16 | 状态层透明度四档（用 on 色、一次只叠一层） |

## 6. 装配管线与 AA 护栏

```
ThemeProfile（主题包）                       SlimcaDynamicColorBuilder（平台动态色）
  toSlimcaTheme(brightness)                    loadPlatformCorePalette() → CorePalette?
  = fromSeeds → fromPalette ─┐                        │
                             ▼                        ▼
  手写 SlimcaTheme ────→ enforceSlimcaAa（幂等降级）──→ buildTheme ──→ ThemeData
                             │                        │  ColorScheme.fromSeed(tokens.primary)
                             │                        │  .copyWith(secondary=moneyOut, error=danger…)
                             │                        └─ extensions: SlimcaTheme/MotionConfig/Spacing/Sizes
                             ▼
                  auditSlimcaAa（只读审计 → 编辑器反馈条）
```

- **护栏关键对 10 个**（`kSlimcaAaPairSpecs`）：正文×(卡面/页面底)、次级正文×卡面、moneyIn/moneyOut/kcalIn/kcalOut/net/danger×卡面（阈值 4.5）+ onPrimary×primary（UI 阈值 3.0）；warn/success 是图形语义不进护栏。算法：`computeContrastRatio`（WCAG 相对亮度）+ `resolveAaSafeColor`（HCT tone 轴双向逐级搜索最近安全 tone，保色相饱和度）。
- `ColorScheme` 只以 `tokens.primary` 为种子 fromSeed 补齐派生槽位，再用语义 token 覆盖关键槽位；`secondary = moneyOut`（暖橘=金额）。
- dynamic_color 两源映射（`SlimcaDynamicThemeMapper.map`）：accent → primary/onPrimary；neutral(+Variant) → 背景/正文/描边；**kcal/money/success/warn/danger 一律不映射**；出口过护栏；palette 为 null（iOS/旧机型/通道异常）原样回退手动种子。

## 7. ThemeProfile 主题包模型与持久化形状

字段：`id`（调用方生成 UUIDv7）/ `name` / `lightSeeds` + `darkSeeds`（各为 `SlimcaSeedSet` 四色）/ `radiusScale`(0-2) / `density`(0.8-1.2) / `fontScale`(0.85-1.3) / `motionScale`(0.6-1.5，构造期钳制) / `motionLevel` / `fontId?` / `isPreset` / `sort` / `pureBlackDark`（曜黑 AMOLED：深色下 surface=纯黑、muted=neutral 8、card=neutral 12）。

两种序列化形状：
1. **tokens JSON**（`toTokensJson/fromTokensJson`）：`{light:{kcal,money,danger,neutral ARGB}, dark:{…}, radiusScale, density, fontScale, motionScale, pureBlackDark}`。
2. **行形状**（`toJsonRow/fromJsonRow`）：`{id, name, tokens(字符串), motionLevel, fontId, isPreset, sort}` —— 键名与 core_db `theme_profiles` drift 行一一对应；**同步公共列（createdAt/updatedAt/deletedAt/hlc/revision/schemaVer/deviceId）不在此携带，由 core_db 同步层补齐**。tokens 值兼容字符串（行形状）与 Map（直传 payload）。

内置 6 主题包（`kSlimcaPresetThemeProfiles`，id 稳定、随 theme_profiles 同步入库）：
`preset-mo 墨` / `preset-zhi 纸` / `preset-neon 霓虹` / `preset-cream 奶油` / `preset-senye 森野` / `preset-yaohei 曜黑(pureBlackDark)`。全部 kcal hue=150、money hue=62，只调 chroma（45-80）与 neutral 色相（70-265）；浅色侧种子 tone 40±5、深色侧 80±5。查找：`presetThemeProfileById`；HCT 造色：`seedFromHct(hue, chroma, tone)`。

## 8. 动效帧预算（§2.3 token 与预算的对应关系）

| 交互 | 预算 | token 落点 |
|------|------|------|
| 切日（共享轴） | ≤280ms | durL=280ms + curveStandard |
| 打开录入抽屉到可输入 | ≤280ms | springSnappy 整定 220ms |
| 落库 Hero 飞入 | ≤450ms | durXl=450ms + springSoft 轨迹 |
| AI count-up | 800ms | countUpDuration + curveEaseOutExpo |
| 主题 morph | 300ms | themeMorphDuration + curveStandard |
| 周条↔月网格形变 | 280ms | durL + curveExpand/curveCollapse |
| AI 等待骨架出现 | ≤100ms | SlimcaBreath 即时在场（无 spinner） |

性能纪律：动画子树包 `RepaintBoundary`（环/呼吸）；循环动画依赖 `TickerMode` 离屏自动暂停；静态子树经 TweenAnimationBuilder/AnimatedBuilder 的 `child` 参数只 build 一次；**MotionLevel=off 时全部路径必须收敛到 100ms fade（pumpAndSettle 必然可收敛）**。
