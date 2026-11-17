/// 主题编辑面板壳层接线（§11.2 W16 任务 1「设置页主题编辑器入口
/// （ThemeEditorPanel 接入）」+ 任务 4「6 主题包选择 UI（网格预览，当前高亮）
/// + dynamic_color 开关（默认关，手动主题优先）」）。
///
/// 分层（§10.4）：ui_kit `ThemeEditorPanel`（§8.4 编辑器本体：取色/四滑杆/
/// WCAG AA 反馈条/实时预览/命名/保存闸门——不触库）+ 本壳的宿主职责：
/// - **6 内置包网格**（ui_kit `kSlimcaPresetThemeProfiles` 直渲，首帧零异步
///   §2.3）与自定义包卡（theme_profiles 流 §5.6⑳），当前包高亮描边+对勾；
/// - **dynamic_color 开关**（§8.3 Android 12+ Material You，默认关=手动主题
///   优先；开启后 ui_kit SlimcaDynamicThemeMapper 仅映射 primary/neutral
///   两源，双主色语义锚定不变）；
/// - **深浅覆盖**（跟随系统/浅色/深色，§8.3）；动效等级在 ui_kit 编辑器内
///   （§9.2 MotionLevel），经 onChanged 同步 settings ⑲ 即改即生效；
/// - **保存入库**：编辑器 onSave 草稿 → 复制为新自定义包（UUIDv7 行 id，
///   §5.1）→ theme_profiles 行 + 同事务 outbox（§6.2，经
///   DriftThemeProfileRepository → SyncOutboxWriter）→ 切换当前包。
///
/// 全部样式读语义 token/MotionConfig（§8.2 第 3 层约束：禁裸色值/裸时长）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        MotionConfig,
        MotionLevel,
        SlimcaTheme,
        SlimcaThemeBuildContext,
        ThemeEditorPanel,
        ThemeProfile,
        kSlimcaPresetThemeProfiles,
        showSlimcaSpringSheet;

import '../../app/providers.dart';
import '../../theme/theme_profiles.dart' show themeProfileFromRow;
import '../../theme/theme_providers.dart';
import '../../theme/theme_settings.dart';

/// 唤起主题编辑面板（§9.3#3 弹簧 bottomSheet 同款路由；编辑器打开漏斗
/// theme_editor_opened 由设置页入口埋点，§11.2 W16 任务 5）。
Future<void> showThemeEditorPanel(BuildContext context) {
  return showSlimcaSpringSheet<void>(
    context: context,
    motion: MotionConfig.of(context),
    builder: (_) => const ThemeEditorSheet(),
  );
}

/// 主题编辑面板壳（ui_kit ThemeEditorPanel 的宿主容器）。
class ThemeEditorSheet extends ConsumerStatefulWidget {
  const ThemeEditorSheet({super.key});

  @override
  ConsumerState<ThemeEditorSheet> createState() => _ThemeEditorSheetState();
}

class _ThemeEditorSheetState extends ConsumerState<ThemeEditorSheet> {
  /// 网格卡数据：内置包=ui_kit 清单直渲（首帧零异步）；自定义包=
  /// theme_profiles 行解码（§5.6⑳；坏 tokens 行不展示——不猜、不崩，§6.1）。
  List<_PackCardData> _packCards(List<db.ThemeProfile>? rows) {
    final Brightness brightness = Theme.of(context).brightness;
    final List<_PackCardData> cards = <_PackCardData>[
      for (final ThemeProfile preset in kSlimcaPresetThemeProfiles)
        _PackCardData(
          id: preset.id,
          name: preset.name,
          isPreset: true,
          tokens: preset.toSlimcaTheme(brightness),
        ),
    ];
    for (final db.ThemeProfile row in rows ?? const <db.ThemeProfile>[]) {
      if (row.isPreset || row.deletedAt != null) {
        continue; // 内置包恒走 ui_kit 清单（包定义常量，跨设备一致）。
      }
      final ThemeProfile? profile = themeProfileFromRow(row);
      if (profile != null) {
        cards.add(_PackCardData(
          id: profile.id,
          name: profile.name,
          isPreset: false,
          tokens: profile.toSlimcaTheme(brightness),
        ));
      }
    }
    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final ThemeSettings settings = ref.watch(themeSettingsControllerProvider);
    final ThemeProfile current =
        ref.watch(resolvedThemeProfileProvider);
    final List<db.ThemeProfile>? rows =
        ref.watch(themeProfilesStreamProvider).value;

    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 头部（标题 + 关闭；tooltip 与录入抽屉同款「关闭」）。
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '主题',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                // ── 6 内置包 + 自定义包网格（§11.2 W16 任务 4；当前高亮）。
                _PackGrid(
                  currentPackId: settings.packId,
                  packs: _packCards(rows),
                  onSelect: _selectPack,
                  onDeleteCustom: _deleteCustomPack,
                ),
                const SizedBox(height: 8),
                // ── dynamic_color 开关（§8.3，默认关=手动主题优先）。
                SwitchListTile(
                  key: const Key('theme_dynamic_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.wallpaper_outlined),
                  title: const Text('Material You（dynamic_color）'),
                  subtitle: const Text(
                    'Android 12+ 系统取色仅映射主色/中性两源（§8.3），热量绿/'
                    '金额橘语义锚定不变；关闭（默认）=手动主题优先；iOS/旧机型'
                    '自动回退手动主题包',
                  ),
                  value: settings.dynamicColorEnabled,
                  onChanged: (bool enabled) => _guard(
                    () => ref
                        .read(themeSettingsControllerProvider.notifier)
                        .setDynamicColorEnabled(enabled),
                  ),
                ),
                const SizedBox(height: 8),
                // ── 深浅覆盖（§8.3：跟随系统 + 手动覆盖）。
                _ThemeModeSegment(
                  settings: settings,
                  onSelected: (ThemeMode mode) => _guard(
                    () => ref
                        .read(themeSettingsControllerProvider.notifier)
                        .setThemeMode(mode),
                  ),
                ),
                const SizedBox(height: 12),
                // ── §8.4 编辑器本体（ui_kit ThemeEditorPanel 接入）：草稿=
                //    当前包；选包切换经 ValueKey 重置草稿；保存=复制为新自定义
                //    包入库（§5.6⑳ theme_profiles + §6.2 outbox）。
                ThemeEditorPanel(
                  // 面板 State 以 initial 为草稿起点；换包（initial.id 变化）
                  // 需要全新草稿 → ValueKey 重建（ui_kit 面板不自行重置草稿）。
                  key: ValueKey<String>('theme_editor_${current.id}'),
                  initial: current,
                  onChanged: _onDraftChanged,
                  onSave: _saveDraftAsCustom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 选择主题包（§11.2 W16 任务 2：ThemeProfile provider 链路入口）。
  ///
  /// 高亮/主题即时反映由面板 watch 控制器状态驱动；morph 由 main.dart 的
  /// SlimcaThemeMorph 消费新 ThemeData（§9.3#10）。
  Future<void> _selectPack(_PackCardData pack) async {
    await _guard(
      () => ref
          .read(themeSettingsControllerProvider.notifier)
          .selectPack(pack.id, source: pack.isPreset ? 'preset' : 'custom'),
    );
  }

  /// 删除自定义包（§5.6⑳ 内置包不可删；软删墓碑 §5.1，delete 语义出网）。
  Future<void> _deleteCustomPack(_PackCardData pack) async {
    if (pack.isPreset) {
      return;
    }
    await _guard(
      () => ref.read(themeProfileRepositoryProvider).softDelete(pack.id),
    );
  }

  /// 草稿变更（ui_kit 面板 onChanged）：动效档位同步 settings ⑲（§5.6⑲
  /// 设备本地偏好，§8.1「动效与主题同源同发」即改即生效）；其余滑杆/取色
  /// 仅影响编辑器内预览与保存草稿，不落库。
  Future<void> _onDraftChanged(ThemeProfile draft) async {
    final MotionLevel current = ref.read(themeSettingsControllerProvider).motionLevel;
    if (current == draft.motionLevel) {
      return;
    }
    await _guard(
      () => ref
          .read(themeSettingsControllerProvider.notifier)
          .setMotionLevel(draft.motionLevel),
    );
  }

  /// 保存草稿为自定义包（§8.4「命名与同步」）：草稿复制（新 UUIDv7 行 id、
  /// is_preset=false）→ theme_profiles 行 + 同事务 outbox（§6.2）→ 切换。
  Future<void> _saveDraftAsCustom(ThemeProfile draft) async {
    await _guard(() async {
      final db.ThemeProfile row = await ref
          .read(themeProfileRepositoryProvider)
          .saveCustom(
            name: draft.name.trim(),
            tokensJson: jsonEncode(draft.toTokensJson()),
            motionLevel: draft.motionLevel.name,
            sort: 100,
          );
      await ref
          .read(themeSettingsControllerProvider.notifier)
          .selectPack(row.id, source: 'custom');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存并应用「${row.name}」（随同步走）')),
      );
    });
  }

  /// 写路径护栏（§6.1）：状态先行、落库失败仅 SnackBar（不回滚页面态，
  /// 下次启动按落库值装配，本地件自愈口径——与设置页开关同款）。
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败（本地保留本次选择）：$error')),
      );
    }
  }
}

// ── 包网格（§11.2 W16 任务 4）────────────────────────────────────────

/// 网格卡数据（内置包=ui_kit 清单；自定义包=theme_profiles 行解码）。
class _PackCardData {
  const _PackCardData({
    required this.id,
    required this.name,
    required this.isPreset,
    required this.tokens,
  });

  final String id;
  final String name;
  final bool isPreset;

  /// 该包在当前亮度下的语义 token（预览样色 + 选中判定共用）。
  final SlimcaTheme tokens;
}

/// 主题包网格（2 列；当前包高亮描边 + 对勾，§11.2 W16 任务 4「当前高亮」）。
class _PackGrid extends StatelessWidget {
  const _PackGrid({
    required this.currentPackId,
    required this.packs,
    required this.onSelect,
    required this.onDeleteCustom,
  });

  final String currentPackId;
  final List<_PackCardData> packs;
  final void Function(_PackCardData pack) onSelect;
  final void Function(_PackCardData pack) onDeleteCustom;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: <Widget>[
        for (final _PackCardData pack in packs)
          _PackCard(
            key: Key('theme_pack_card_${pack.id}'),
            data: pack,
            selected: pack.id == currentPackId,
            tokens: tokens,
            onSelect: () => onSelect(pack),
            onDelete: pack.isPreset ? null : () => onDeleteCustom(pack),
          ),
      ],
    );
  }
}

/// 包卡（预览条 = 包 surface 底 + kcal/money/primary 三色样；§8.2 双主色锚定
/// 的可视化预览）。
class _PackCard extends StatelessWidget {
  const _PackCard({
    super.key,
    required this.data,
    required this.selected,
    required this.tokens,
    required this.onSelect,
    required this.onDelete,
  });

  final _PackCardData data;
  final bool selected;
  final SlimcaTheme tokens;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme pack = data.tokens;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(12 * tokens.radiusScale),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          borderRadius: BorderRadius.circular(12 * tokens.radiusScale),
          border: Border.all(
            color: selected ? tokens.primary : tokens.outline,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: tokens.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    key: Key('theme_pack_selected_icon'),
                    size: 18,
                  ),
                if (!selected && onDelete != null)
                  IconButton(
                    tooltip: '删除自定义包',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const Spacer(),
            // 预览条（包语义 token 直渲——surface 底 + 三语义色，§8.2）。
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: pack.surface,
                borderRadius: BorderRadius.circular(8 * tokens.radiusScale),
                border: Border.all(color: tokens.outline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  _bar(pack.kcalIn), // 热量绿（§8.2 锚定语义）
                  const SizedBox(width: 6),
                  _bar(pack.moneyOut), // 暖橘（§8.2 锚定语义）
                  const SizedBox(width: 6),
                  _bar(pack.primary), // 品牌主色
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color) => Container(
        width: 28,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
      );
}

// ── 深浅覆盖（§8.3）────────────────────────────────────────────────

/// 深浅覆盖段选择器（跟随系统/浅色/深色，§8.3；动效档位由 ui_kit 编辑器
/// 内 MotionLevel 段承担，经 onChanged 同步 settings ⑲）。
class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({required this.settings, required this.onSelected});

  final ThemeSettings settings;
  final void Function(ThemeMode mode) onSelected;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '深浅色',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: tokens.onSurfaceMuted),
        ),
        const SizedBox(height: 6),
        SegmentedButton<ThemeMode>(
          key: const Key('theme_mode_selector'),
          segments: const <ButtonSegment<ThemeMode>>[
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              label: Text('跟随系统'),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              label: Text('浅色'),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              label: Text('深色'),
            ),
          ],
          selected: <ThemeMode>{settings.themeMode},
          onSelectionChanged: (Set<ThemeMode> selection) {
            if (selection.isNotEmpty) {
              onSelected(selection.first);
            }
          },
        ),
      ],
    );
  }
}
