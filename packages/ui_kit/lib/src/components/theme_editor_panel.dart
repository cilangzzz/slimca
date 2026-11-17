import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../tokens/build_theme.dart';
import '../tokens/contrast.dart';
import '../tokens/motion_config.dart';
import '../tokens/slimca_theme.dart';
import '../tokens/theme_presets.dart';
import '../tokens/theme_profile.dart';
import 'calorie_ring.dart';

/// 主题编辑器面板（§8.4 主题编辑器 P1，路由 /settings/theme 容器变换进入）。
///
/// 能力清单（§8.4 表）：
/// - 种子色取色：四通道（热量/金额/危险/中性）预设色板 chips + 滑杆微调；
///   kcal/money 色相锁定 150°/62°（§8.2 双主色锚定），仅开放饱和度/明度；
/// - 对比度护栏：WCAG AA 实时校验反馈条——主体为生效 token（护栏兜底后）
///   的逐对实测；原始草稿中被自动降级的对数以提示条呈现（§8.3 透明化）；
///   不达标红字提示且禁止保存（保存闸门读生效 token 审计结果）；
/// - 形状密度：圆角/密度/字重/动效强度四滑杆（§8.2/§8.3 量程）；
/// - 实时预览：仪表盘微缩版（热量环 + 支出 + 待办 + 净热量），浅/深可切换；
/// - 命名与同步：包名编辑与草稿回调（入库 theme_profiles 由宿主层经 outbox
///   同步，§5.6⑳；本组件不直接触库）。
///
/// 滑杆改动即回调 [ThemeEditorPanel.onChanged]（实时换肤/草稿持久化）；
/// [ThemeEditorPanel.onSave] 仅在 AA 全达标时可触发（保存按钮禁用态表达）。
class ThemeEditorPanel extends StatefulWidget {
  const ThemeEditorPanel({
    super.key,
    required this.initial,
    this.onChanged,
    this.onSave,
    this.showPreview = true,
  });

  /// 初始草稿（内置包或已有自定义包）。
  final ThemeProfile initial;

  /// 草稿变更回调（每次滑杆/选色/命名改动触发，宿主可实时换肤）。
  final ValueChanged<ThemeProfile>? onChanged;

  /// 保存回调（AA 全达标才可达）。
  final ValueChanged<ThemeProfile>? onSave;

  /// 是否渲染仪表盘微缩预览卡（嵌入更复杂编辑页时可关闭）。
  final bool showPreview;

  @override
  State<ThemeEditorPanel> createState() => _ThemeEditorPanelState();
}

class _ThemeEditorPanelState extends State<ThemeEditorPanel> {
  late ThemeProfile _draft = widget.initial;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initial.name,
  );
  Brightness _previewBrightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      // 文本框自身驱动更新（避免 build 内重建 controller 导致光标跳位）
      if (_nameController.text != _draft.name) {
        _update(_draft.copyWith(name: _nameController.text));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ThemeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 宿主切换初始包（如换选内置包）时同步名称框
    if (widget.initial.id != oldWidget.initial.id &&
        widget.initial.name != _nameController.text) {
      _nameController.value = TextEditingValue(
        text: widget.initial.name,
        selection: TextSelection.collapsed(offset: widget.initial.name.length),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 草稿原始语义 token（不过护栏，§8.4 审计「降级前」真实对比度）。
  SlimcaTheme get _rawTokens =>
      _draft.toSlimcaTheme(_previewBrightness, enforceAa: false);

  /// 生效语义 token（护栏兜底后，预览卡所见即装配所得，§8.3）。
  SlimcaTheme get _effectiveTokens => _draft.toSlimcaTheme(_previewBrightness);

  /// 生效 token 的 AA 审计（§8.4 反馈条主体）。
  List<SlimcaAaPairResult> get _audit => auditSlimcaAa(_effectiveTokens);

  /// 原始草稿中不达标、已被护栏自动降级的对数（§8.3 信息提示）。
  int get _degradedCount =>
      auditSlimcaAa(_rawTokens).where((SlimcaAaPairResult r) => !r.pass).length;

  bool get _canSave => _audit.every((SlimcaAaPairResult r) => r.pass);

  void _update(ThemeProfile next) {
    setState(() => _draft = next);
    widget.onChanged?.call(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final List<SlimcaAaPairResult> audit = _audit;
    final int failed = audit.where((SlimcaAaPairResult r) => !r.pass).length;
    // SingleChildScrollView + Column（非懒加载）：编辑器内容量级有限，
    // 全量装配保证预览/断言所见即所得（测试可直接定位任意区块）。
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── §8.4 对比度护栏：AA 实时校验反馈条 ──────────────────────
          _AaFeedbackBar(results: audit, degradedCount: _degradedCount),
          const SizedBox(height: 16),
          // ── 预览亮度切换 + 仪表盘微缩版（§8.4 实时预览）──────────────
          SegmentedButton<Brightness>(
            segments: const <ButtonSegment<Brightness>>[
              ButtonSegment<Brightness>(
                value: Brightness.light,
                label: Text('浅色预览'),
              ),
              ButtonSegment<Brightness>(
                value: Brightness.dark,
                label: Text('深色预览'),
              ),
            ],
            selected: <Brightness>{_previewBrightness},
            onSelectionChanged: (Set<Brightness> s) =>
                setState(() => _previewBrightness = s.first),
          ),
          if (widget.showPreview) ...<Widget>[
            const SizedBox(height: 12),
            _MiniDashboardPreview(
              profile: _draft,
              brightness: _previewBrightness,
              effectiveTokens: _effectiveTokens,
            ),
          ],
          const SizedBox(height: 16),
          // ── §8.4 种子色取色：四通道 ──────────────────────────────────
          for (final _SeedChannel channel in _kSeedChannels)
            _SeedChannelSection(
              channel: channel,
              draft: _draft,
              onEdit: _editChannel,
            ),
          const SizedBox(height: 8),
          // ── §8.4 形状密度：四滑杆（§8.2/§8.3 量程）────────────────────
          _SliderRow(
            label: '圆角',
            detail: 'radiusScale',
            value: _draft.radiusScale,
            min: ThemeProfile.radiusScaleMin,
            max: ThemeProfile.radiusScaleMax,
            divisions: 20,
            onChanged: (double v) => _update(_draft.copyWith(radiusScale: v)),
          ),
          _SliderRow(
            label: '密度',
            detail: 'density',
            value: _draft.density,
            min: ThemeProfile.densityMin,
            max: ThemeProfile.densityMax,
            divisions: 20,
            onChanged: (double v) => _update(_draft.copyWith(density: v)),
          ),
          _SliderRow(
            label: '字重',
            detail: 'fontScale',
            value: _draft.fontScale,
            min: ThemeProfile.fontScaleMin,
            max: ThemeProfile.fontScaleMax,
            divisions: 18,
            onChanged: (double v) => _update(_draft.copyWith(fontScale: v)),
          ),
          _SliderRow(
            label: '动效强度',
            detail: 'motionScale（§8.3 0.6x-1.5x）',
            value: _draft.motionScale,
            min: MotionConfig.motionScaleMin,
            max: MotionConfig.motionScaleMax,
            divisions: 18,
            onChanged: (double v) => _update(_draft.copyWith(motionScale: v)),
          ),
          const SizedBox(height: 8),
          // ── §9.2 MotionLevel（off/reduced/full）──────────────────────
          SegmentedButton<MotionLevel>(
            segments: const <ButtonSegment<MotionLevel>>[
              ButtonSegment<MotionLevel>(
                value: MotionLevel.off,
                label: Text('关'),
              ),
              ButtonSegment<MotionLevel>(
                value: MotionLevel.reduced,
                label: Text('减弱'),
              ),
              ButtonSegment<MotionLevel>(
                value: MotionLevel.full,
                label: Text('完整'),
              ),
            ],
            selected: <MotionLevel>{_draft.motionLevel},
            onSelectionChanged: (Set<MotionLevel> s) =>
                _update(_draft.copyWith(motionLevel: s.first)),
          ),
          const SizedBox(height: 16),
          // ── §8.4 命名与同步：包名编辑（入库由宿主层写 theme_profiles）──
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '主题包名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // ── §8.4 保存：不达标禁止保存（红字提示由反馈条承担）────────────
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _canSave && _draft.name.trim().isNotEmpty
                      ? () => widget.onSave?.call(_draft)
                      : null,
                  child: Text(failed == 0 ? '保存主题包' : '对比度不达标，禁止保存（$failed 对）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 种子色编辑（§8.4 色轮/滑杆 → HCT 实时生成）：浅/深两侧共享色相与饱和度，
  /// 明度各自独立；kcal/money 色相被 [lockedHue] 锁定（§8.2 双主色锚定）。
  void _editChannel(
    _SeedChannel channel, {
    double? hue,
    double? chroma,
    double? lightTone,
    double? darkTone,
  }) {
    final Hct light = Hct.fromInt(channel.pick(_draft.lightSeeds).toARGB32());
    final Hct dark = Hct.fromInt(channel.pick(_draft.darkSeeds).toARGB32());
    final double h = hue ?? channel.lockedHue ?? light.hue;
    final double c = chroma ?? light.chroma;
    final Color newLight = Color(
      Hct.from(h, c, lightTone ?? light.tone).toInt(),
    );
    final Color newDark = Color(Hct.from(h, c, darkTone ?? dark.tone).toInt());
    setState(() {
      _draft = _draft.copyWith(
        lightSeeds: channel.apply(_draft.lightSeeds, newLight),
        darkSeeds: channel.apply(_draft.darkSeeds, newDark),
      );
    });
    widget.onChanged?.call(_draft);
  }
}

/// 种子色通道描述（四通道：热量/金额/危险/中性）。
class _SeedChannel {
  const _SeedChannel({
    required this.label,
    required this.pick,
    required this.apply,
    this.lockedHue,
    required this.chromaMax,
    required this.chips,
  });

  /// 通道名。
  final String label;

  /// §8.2 双主色锚定：非 null 则色相锁定（热量 150 / 金额 62）。
  final double? lockedHue;

  /// 饱和度上限（中性基底保持低饱和，§8.2 中性蓝灰）。
  final double chromaMax;

  final Color Function(SlimcaSeedSet seeds) pick;

  final SlimcaSeedSet Function(SlimcaSeedSet seeds, Color color) apply;

  /// 预设 chips（色相, 饱和度）——色板入口，tone 沿用两侧当前值。
  final List<(double, double)> chips;
}

const List<_SeedChannel> _kSeedChannels = <_SeedChannel>[
  _SeedChannel(
    label: '热量（健康绿）',
    lockedHue: kKcalAnchorHue,
    chromaMax: 80,
    pick: _pickKcal,
    apply: _applyKcal,
    chips: <(double, double)>[(150, 45), (150, 55), (150, 70)],
  ),
  _SeedChannel(
    label: '金额（暖橘）',
    lockedHue: kMoneyAnchorHue,
    chromaMax: 80,
    pick: _pickMoney,
    apply: _applyMoney,
    chips: <(double, double)>[(62, 55), (62, 68), (62, 80)],
  ),
  _SeedChannel(
    label: '危险',
    chromaMax: 80,
    pick: _pickDanger,
    apply: _applyDanger,
    chips: <(double, double)>[(27, 72), (12, 72), (350, 64)],
  ),
  _SeedChannel(
    label: '中性基底',
    chromaMax: 16,
    pick: _pickNeutral,
    apply: _applyNeutral,
    chips: <(double, double)>[
      (250, 8), // 墨
      (80, 6), // 纸
      (70, 10), // 奶油
      (145, 7), // 森野
      (265, 12), // 霓虹
      (250, 4), // 曜黑
    ],
  ),
];

// 静态取值/写回函数（const 通道表不可携带闭包，用具名顶层函数）
Color _pickKcal(SlimcaSeedSet s) => s.kcal;
Color _pickMoney(SlimcaSeedSet s) => s.money;
Color _pickDanger(SlimcaSeedSet s) => s.danger;
Color _pickNeutral(SlimcaSeedSet s) => s.neutral;
SlimcaSeedSet _applyKcal(SlimcaSeedSet s, Color c) => s.copyWith(kcal: c);
SlimcaSeedSet _applyMoney(SlimcaSeedSet s, Color c) => s.copyWith(money: c);
SlimcaSeedSet _applyDanger(SlimcaSeedSet s, Color c) => s.copyWith(danger: c);
SlimcaSeedSet _applyNeutral(SlimcaSeedSet s, Color c) => s.copyWith(neutral: c);

/// 单通道编辑区：预设 chips + （可选）色相滑杆 + 饱和度 + 浅/深明度滑杆。
class _SeedChannelSection extends StatelessWidget {
  const _SeedChannelSection({
    required this.channel,
    required this.draft,
    required this.onEdit,
  });

  final _SeedChannel channel;
  final ThemeProfile draft;
  final void Function(
    _SeedChannel channel, {
    double? hue,
    double? chroma,
    double? lightTone,
    double? darkTone,
  })
  onEdit;

  @override
  Widget build(BuildContext context) {
    final Hct light = Hct.fromInt(channel.pick(draft.lightSeeds).toARGB32());
    final Hct dark = Hct.fromInt(channel.pick(draft.darkSeeds).toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(channel.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            if (channel.lockedHue != null)
              Text(
                // §8.2 双主色锚定：色相锁定文案
                '色相锁定 ${channel.lockedHue!.round()}°',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 预设色板 chips（§8.4 色轮预设；HCT 生成，tone 50 展示色）
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (double, double) chip in channel.chips)
              _SeedChip(
                color: seedFromHct(channel.lockedHue ?? chip.$1, chip.$2, 50),
                selected:
                    (channel.lockedHue ?? light.hue).round() ==
                        (channel.lockedHue ?? chip.$1).round() &&
                    light.chroma.round() == chip.$2.round(),
                onTap: () => onEdit(channel, hue: chip.$1, chroma: chip.$2),
              ),
          ],
        ),
        if (channel.lockedHue == null)
          _SliderRow(
            label: '色相',
            detail: '${light.hue.round()}°',
            value: light.hue,
            min: 0,
            max: 360,
            divisions: 72,
            onChanged: (double v) => onEdit(channel, hue: v),
          ),
        _SliderRow(
          label: '饱和度',
          detail: light.chroma.round().toString(),
          value: clampDouble(light.chroma, 0, channel.chromaMax),
          min: 0,
          max: channel.chromaMax,
          divisions: (channel.chromaMax / 2).round(),
          onChanged: (double v) => onEdit(channel, chroma: v),
        ),
        _SliderRow(
          label: '浅色明度',
          detail: light.tone.round().toString(),
          value: clampDouble(light.tone, 20, 55),
          min: 20,
          max: 55,
          divisions: 35,
          onChanged: (double v) => onEdit(channel, lightTone: v),
        ),
        _SliderRow(
          label: '深色明度',
          detail: dark.tone.round().toString(),
          value: clampDouble(dark.tone, 60, 95),
          min: 60,
          max: 95,
          divisions: 35,
          onChanged: (double v) => onEdit(channel, darkTone: v),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// 预设色板圆片（§8.4 色轮预设入口；选中态描边）。
class _SeedChip extends StatelessWidget {
  const _SeedChip({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }
}

/// 通用滑杆行（§8.4 四滑杆与种子微调共用）。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Slider(
            value: clampDouble(value, min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 108,
          child: Text(
            detail,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// §8.4 AA 校验反馈条：逐对呈现生效 token 的对比度实测值与达标态；不达标
/// 红字提示且保存按钮禁用（由 [ThemeEditorPanel] 装配）。原始草稿中被护栏
/// 自动降级的对数以提示条呈现（§8.3 降级兜底透明化）。
class _AaFeedbackBar extends StatelessWidget {
  const _AaFeedbackBar({
    required this.results,
    required this.degradedCount,
  });

  final List<SlimcaAaPairResult> results;

  /// 原始草稿不达标、已自动降级的对数。
  final int degradedCount;

  @override
  Widget build(BuildContext context) {
    final int failed = results.where((SlimcaAaPairResult r) => !r.pass).length;
    final bool allPass = failed == 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allPass
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            allPass ? 'WCAG AA 全部达标' : 'WCAG AA 不达标（$failed 对）',
            style: TextStyle(
              color: allPass
                  ? Theme.of(context).colorScheme.onSurface
                  // §8.4 不达标红字提示
                  : Theme.of(context).colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (degradedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '原始草稿 $degradedCount 对不达标，'
                '已按护栏自动降级到最近安全 tone（§8.3）',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final SlimcaAaPairResult r in results)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Icon(
                    r.pass ? Icons.check_circle_outline : Icons.error_outline,
                    size: 16,
                    color: r.pass
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.label)),
                  Text(
                    '${r.ratio.toStringAsFixed(2)} : 1'
                    '（≥${r.threshold.toStringAsFixed(1)}）',
                    style: TextStyle(
                      color: r.pass
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// §8.4 实时预览：仪表盘微缩版（§3.2 卡片墙核心要素的缩样）。
///
/// 以草稿生效 token（护栏兜底后）装配独立 Theme，所见即装配所得；
/// 数值为静态样本，预览不参与业务查询。
class _MiniDashboardPreview extends StatelessWidget {
  const _MiniDashboardPreview({
    required this.profile,
    required this.brightness,
    required this.effectiveTokens,
  });

  final ThemeProfile profile;
  final Brightness brightness;
  final SlimcaTheme effectiveTokens;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = buildTheme(
      brightness: brightness,
      semantic: effectiveTokens,
      motion: profile.toMotionConfig(),
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (BuildContext context) {
          // 预览子树内读取语义 token（§8.2 第 3 层只引用语义 token）
          final SlimcaTheme tokens = context.slimca;
          final MotionConfig motion = context.motion;
          final double fontScale = tokens.fontScale;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(12 * tokens.radiusScale),
              border: Border.fromBorderSide(BorderSide(color: tokens.outline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 日期大字（§3.2）
                Text(
                  '11月17日 周一',
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 20 * fontScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // 热量环（§3.2 卡片墙核心视觉，预览静态入场）
                    const SlimcaCalorieRing(
                      kcalIn: 1200,
                      kcalOut: 400,
                      budget: 2000,
                      size: 88,
                      strokeWidth: 9,
                      sweepEntrance: false,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '支出 ¥68.50',
                            style: TextStyle(
                              // §8.2 双主色锚定：暖橘=金额
                              color: tokens.moneyOut,
                              fontSize: 16 * fontScale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '净热量 800 kcal',
                            style: TextStyle(
                              color: tokens.net,
                              fontSize: 14 * fontScale,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '待办 3/5',
                            style: TextStyle(
                              color: tokens.onSurfaceMuted,
                              fontSize: 13 * fontScale,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  // 动效档位提示（§9.2 MotionLevel 挂进主题）
                  '动效：${motion.level.name} · ×${tokens.motionScale}',
                  style: TextStyle(
                    color: tokens.onSurfaceMuted,
                    fontSize: 11 * fontScale,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
