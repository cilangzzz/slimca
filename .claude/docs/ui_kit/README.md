# ui_kit — Slimca UI 基建（基础层·设计系统）

> 包路径 `packages/ui_kit`。定位：把「样式怎么取、动效怎么放、组件怎么长」全部收敛为设计 token 与语义组件。
> 上层包（4 个 feature_* 与 apps/mobile）只允许从本库导出物取样式——禁止裸色值/裸时长/裸间距/裸尺寸（§8.2 第 3 层约束）。

## 模块边界

**提供**：
- 三层设计 token：L1 色板 `SlimcaPalette`（HCT tonal palette）→ L2 语义 token（`SlimcaTheme` 色彩 / `MotionConfig` 动效 / `SlimcaSpacing` 间距 / `SlimcaSizes` 尺寸，全部为 `ThemeExtension`）→ L3 组件经 `BuildContext` 扩展（`context.slimca/motion/spacing/sizes`）读取。
- 主题装配管线：`buildTheme`（装配 ColorScheme + 4 个扩展）、`ThemeProfile` 主题包模型与持久化行形状、6 套内置主题包、dynamic_color 两源映射、WCAG AA 对比度护栏（审计 + 幂等降级）。
- 语义组件 9 个：热量环 / 确认卡容器 / 日历组件族 3 个（+1 个内部日期工具）/ 菜单组件族 3 个 / 主题编辑器面板。
- P0 关键转场 9 族：级联 / 共享轴（路由级+Widget 级）/ 弹簧抽屉 / count-up（热量+金额）/ 呼吸态 / Hero 弹簧飞行 / 主题 morph / 置信度点。

**不提供**：
- 业务状态与数据（无 Riverpod、无 drift、无路由；`ThemeEditorPanel` 只回调草稿，写 `theme_profiles` 归宿主层）；
- 确认弹窗、snackbar undo、页面导航（归 feature_* 与壳层，见 menu.dart 头注释 §4.3）。

**依赖**（pubspec.yaml）：`flutter` + `material_color_utilities ^0.11.1`（HCT）+ `dynamic_color 1.8.1`（精确 pin，升级禁令见 [pitfalls.md](pitfalls.md)）。
零业务依赖：不 import core_db/core_domain——`ThemeProfile` 仅以 JSON 键名约定对齐 core_db 行形状，不做类型耦合（见 [data-model.md](data-model.md)）。

**被消费**：apps/mobile（壳层装配）、feature_dashboard（卡片墙/日历/菜单）、feature_capture（确认卡/呼吸/count-up）、feature_ledger、feature_plan——全部上层包。

## 30 秒上手

```dart
// 1. 壳层装配（apps/mobile/app/theme.dart）：语义 token + 动效档挂进主题
final ThemeData theme = buildTheme(
  brightness: Brightness.light,
  semantic: profile.toSlimcaTheme(Brightness.light),   // 缺省→内置默认
  motion: MotionConfig.forLevel(MotionLevel.full),      // 缺省→full 档表值
);

// 2. 组件层只经 BuildContext 扩展取样式（无裸值）
final SlimcaTheme tokens = context.slimca;
final MotionConfig motion = context.motion;
final SlimcaSpacing spacing = context.spacing;
final SlimcaSizes sizes = context.sizes;
Container(padding: EdgeInsets.all(spacing.cardInner));  // 12，不写 12.0
```

## 目录结构

```
lib/
├── ui_kit.dart            # barrel：全部公开 API 唯一出口
├── src/
│   ├── tokens/            # L1 palette + L2 四扩展 + 装配/护栏/主题包/动态色
│   ├── components/        # 语义组件（calorie_ring/confirm_card/calendar*/menu*/theme_editor_panel）
│   └── transitions/       # P0 转场库（shared_axis/spring_sheet/stagger/count_up/breath/…）
└── test/                  # 15 个测试文件 ≈3020 行（d6650f8 时点 173 例）
    ├── tokens 侧：tokens_test / motion_config_test / spacing_sizes_test / motion_curves_test /
    │   theme_presets_test / theme_profile_test / contrast_test / dynamic_color_test / theme_builder_test
    ├── 组件侧：w34_components_test / calendar_test / menu_test / theme_editor_test
    └── 其他：transitions_smoke_test / ui_kit_test（barrel 冒烟）
```

## 详细文档

| 文档 | 内容 |
|------|------|
| [data-model.md](data-model.md) | token 体系全景：三层架构、色板/语义/间距/尺寸/曲线全量数值、装配管线与 AA 护栏、ThemeProfile 持久化形状、动效帧预算 |
| [api-components.md](api-components.md) | 语义组件清单（按组件域分组）：用途 / 关键变体 / 用法示例 |
| [api-transitions.md](api-transitions.md) | P0 转场库清单：路由级 / Widget 级 / 微动效，含 MotionLevel=off 降级口径 |
| [code-patterns.md](code-patterns.md) | 「新增一个标准组件」完整步骤 + 组件层约束规则清单 + 新增 token 的层级判断 |
| [pitfalls.md](pitfalls.md) | 禁裸 magic number、MotionLevel=off 纪律、曲线判定线、UTC 日界、W17 插曲（d6650f8）破坏性改动等 |
| [CHANGELOG.md](CHANGELOG.md) | 模块变更历史（真实 git 分析，最新在上；排查问题先看这里） |

## 跨模块锚点

- `ThemeProfile.toJsonRow/fromJsonRow` 的 camelCase 键名与 core_db `theme_profiles` 行（drift `ThemeProfile.fromJson`）一一对应；同步公共列（hlc/revision 等）由 core_db 补齐 → 改任一侧必须同步另一侧。详见 [data-model.md](data-model.md) 与 [../core_db/README.md](../core_db/README.md)。
- 壳层装配链（settings 流 → `buildTheme` → `SlimcaThemeMorph` → MaterialApp）见 [../apps-mobile/README.md](../apps-mobile/README.md)。
- 确认卡插槽组装（三色点/count-up/热量环的业务编排）与「多行状态机」边界见 [../feature_capture/README.md](../feature_capture/README.md)。
