/// 分类选择器（§3.3「分类九宫格快选」的 W2 手动路径形态、§5.4⑤ 分类）。
///
/// 分类色引用语义 token 名（categories.color_token，§8.2「主题可换肤的
/// 工程前提」），渲染时映射到 SlimcaTheme 语义色——组件层禁止裸色值。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';

/// 分类 chip 组（横向 Wrap；再次点击已选 chip = 取消选择）。
class CaptureCategoryPicker extends StatelessWidget {
  const CaptureCategoryPicker({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CaptureCategoryOption> options;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  /// color_token（语义 token 名，§5.4⑤）→ SlimcaTheme 语义色。
  ///
  /// 未知 token 名回退中性色：换肤/新增 token 时组件不崩（§8.2 第 3 层只读
  /// 第 2 层的防御性回退）。
  Color _semanticColor(SlimcaTheme tokens, String colorToken) =>
      switch (colorToken) {
        'kcalIn' => tokens.kcalIn,
        'kcalOut' => tokens.kcalOut,
        'net' => tokens.net,
        'moneyIn' => tokens.moneyIn,
        'moneyOut' => tokens.moneyOut,
        'success' => tokens.success,
        'warn' => tokens.warn,
        'danger' => tokens.danger,
        'primary' => tokens.primary,
        _ => tokens.onSurfaceMuted,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    if (options.isEmpty) {
      return Text(
        '暂无分类，可直接保存（分类管理 W2 后续接线）',
        style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _CategoryChip(
            option: option,
            selected: option.id == selectedId,
            semanticColor: _semanticColor(tokens, option.colorToken),
            onTap: () => onSelected(option.id == selectedId ? null : option.id),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.option,
    required this.selected,
    required this.semanticColor,
    required this.onTap,
  });

  final CaptureCategoryOption option;
  final bool selected;
  final Color semanticColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return AnimatedContainer(
      duration: motion.chipCheck, // §9.2 dur.s chip 微交互
      curve: motion.springSnappy.curve,
      decoration: BoxDecoration(
        color: selected ? semanticColor.withValues(alpha: 0.14) : tokens.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? semanticColor : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('capture_category_${option.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 语义色小圆点 + 首字（分类 icon 名映射归分类管理，W2 后续接线）
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: semanticColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    option.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: semanticColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  option.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? semanticColor : tokens.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
