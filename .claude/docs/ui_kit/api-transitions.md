# ui_kit 转场库 — P0 关键转场清单

> 全部转场只引用 MotionConfig token（时长/弹簧/曲线），不写裸值；**每条转场都有 MotionLevel=off 显式降级分支（100ms 线性淡入淡出）**，保证 pumpAndSettle 必然收敛。
> token 数值与帧预算见 [data-model.md](data-model.md) 第 4/8 节；进出场曲线判定线见 [pitfalls.md](pitfalls.md) 第 3 条。

## 1. 路由级转场

### SlimcaSharedAxisPageRoute / SlimcaSharedAxisPage（shared_axis.dart）

MD3 共享轴路由转场（日切换/平级详情，§9.3#2）：时长 durL 280ms + curveStandard；X/Y/Z 三轴；被覆盖路由向反方向「层级后退」（位移 24 / 缩放 0.96）。off 档 → 100ms fade。

- `SlimcaSharedAxisPageRoute`：直接 `Navigator.push` 或注入自定义 Route 的场景。
- `SlimcaSharedAxisPage`：**go_router 接线件**——go_router `pageBuilder` 契约要求返回 `Page` 而非 Route（W15 集成修复的产物），`createRoute` 内部构造上面的 PageRouteBuilder；`name/arguments/restorationId` 直通 Page 基类。

```dart
// go_router 用法
GoRoute(
  path: '/detail',
  pageBuilder: (context, state) => SlimcaSharedAxisPage(
    key: state.pageKey, name: state.matchedLocation,
    builder: (context) => const DetailScreen(),
  ),
);
```

### SlimcaSpringSheetRoute / showSlimcaSpringSheet（spring_sheet.dart）

录入抽屉弹簧 bottomSheet（§9.3#3）：经 Flutter 3.32 `TransitionRoute.createSimulation` 钩子驱动，springSnappy（220ms ζ=1.0）满足「打开到可输入 ≤280ms」；`dismissVelocity` 字段为拖拽关闭的速度继承入口（pop 前写入，弹簧带初速度重开）；off 档返回 null simulation → 线性 100ms fade。

```dart
await showSlimcaSpringSheet(context: context, builder: (context) => CaptureSheet());
```

## 2. Widget 级转场

| 转场 | 文件 | 手段与要点 |
|------|------|------|
| **SlimcaStaggerItem** | stagger.dart | 冷启动卡片墙级联：第 index 张延迟 index×cascadeInterval(80ms) 后上浮（TweenAnimationBuilder 窗口内重映射，收尾曲线 **curveExpand**）；off 档 → 100ms 淡入无位移；`floatDistance` 为几何常量（缺省 24，确认卡内 16） |
| **SlimcaSharedAxisSwitcher** | shared_axis.dart | AnimatedSwitcher 封装：换 child（key 不同）即触发对称位移淡切（仪表盘左右滑切日/月网格翻月）；时长缺省 durL、曲线 curveStandard；transitionBuilder 内动画已被 switchInCurve 弯过，不再叠加 |
| **SlimcaThemeMorph** | theme_morph.dart | 主题切换全屏 morph：`AnimatedTheme` 包装（SDK ThemeData.lerp 对 ColorScheme/extensions 各自 lerp），时长 themeMorph 300ms + curveStandard；业务只需在主题源变化时更新 `data`，300ms 无闪跳 |
| **SlimcaSharedAxisTransition** | shared_axis.dart | 可复用单侧插值 builder：`animation` 0→1 进场形态，离场传反向驱动动画自动呈现退场；`curve` 参数仅在动画未预弯时传（防双重缓动）；几何常量：进场位移 30、退场位移 24、Z 轴起点 0.92 |

```dart
// 级联卡片墙
for (var i = 0; i < cards.length; i++)
  SlimcaStaggerItem(index: i, child: cards[i]);

// 切日内容切换
SlimcaSharedAxisSwitcher(
  key: ValueKey(selectedDate),
  child: DashboardBody(date: selectedDate),
);
```

## 3. 微动效

| 组件 | 文件 | 规格 |
|------|------|------|
| **SlimcaCountUp** | count_up.dart | 数字 count-up：IntTween 800ms + curveEaseOutExpo；目标值变化从当前值续播；`format` 覆盖展示（缺省 toString）；off → 100ms 线性 |
| **SlimcaMoneyCountUp** + **SlimcaMoneyText** | money_count_up.dart | 金额侧复用 CountUp 骨架：`amountMinor` 整数分 → `SlimcaMoneyText.format`（¥+千位分组+恒 2 位小数，负值带符号，全程整数运算禁浮点）；`income` 取色 moneyIn / moneyOut（双主色锚定） |
| **SlimcaBreath** | breath.dart | 解析中呼吸态（零 spinner）：opacity/scale 双通道循环，整周期=4×durL（1120ms）；`scaleAmplitude` ≤0.2（assert 防抖动）、`opacityFloor` 下限；`breathing=false` 或 off 档 → 100ms 单次淡入静置；RepaintBoundary 隔离 + TickerMode 离屏暂停 |
| **SlimcaConfidenceDot** | confidence_dot.dart | 置信度三色点：≥0.8 success / 0.5-0.8 warn / <0.5 danger（复用 SlimcaTheme 状态 token）；pulse 周期 chipCheck（durS），scale 1+0.4×easeInOut repeat(reverse)；`pulse=false` 或 off 档静置 |
| **SlimcaHero** + **SlimcaSpringRectTween** | hero_flight.dart | 落库卡片飞入仪表盘槽位（§9.3#5）：Hero 轨迹走 springSoft 弹簧 Rect 插值；飞行时长随路由 transitionDuration（宿主路由用 durXl 档）；off 档 → 普通 Hero 线性 |

```dart
// AI 返回的确认卡金额行
SlimcaMoneyCountUp(amountMinor: 600, income: false);

// AI 等待区（抽屉原地转确认卡前）
SlimcaBreath(breathing: pending, child: InputBubbleSkeleton());
```

## 4. 全局降级口径对照（MotionLevel=off）

| 场景 | off 档行为 |
|------|------|
| 路由转场（共享轴/弹簧抽屉/主题 morph） | 100ms fadeOff 淡入淡出（弹簧抽屉经 createSimulation 返回 null） |
| Widget 切换（级联/共享轴 switcher） | 100ms 淡入、无位移 |
| 循环动画（呼吸/pulse） | 停止循环 → 100ms 单次淡入后静置 |
| count-up / Hero | 100ms 线性 / 普通 Hero 线性插值 |
| 日历组件族（形变/锚定回位/选中变色） | 100ms + 曲线线性化（curveEffectsStandard 已线性化档位处理） |

新增任何动画代码都必须补 off 分支——判定与写法见 [code-patterns.md](code-patterns.md) 步骤 4。
