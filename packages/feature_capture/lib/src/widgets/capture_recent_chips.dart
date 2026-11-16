/// 最近记录 chips（§2.4-1「最近记录 chip 复记 ≤5 秒」：一键带入，日期刷新
/// 到今天、份量金额可微调；W3-4 主线取最近 5 条横滑，条数见
/// [kRecentChipLimit]）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';

/// 横滑 chip 行：每条展示原标题 + 热量/金额摘要，点选整卡预填（§2.4）。
class CaptureRecentChips extends StatelessWidget {
  const CaptureRecentChips({
    super.key,
    required this.entries,
    required this.onSelected,
  });

  final List<CaptureRecentEntry> entries;
  final ValueChanged<CaptureRecentEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '最近记录（点选复记，§2.4）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.onSurfaceMuted,
            ),
          ),
        ),
        SizedBox(
          height: 64,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, // 横滑（§2.4）
            child: Row(
              children: [
                for (final entry in entries)
                  _RecentChip(
                    entry: entry,
                    onTap: () => onSelected(entry),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.entry, required this.onTap});

  final CaptureRecentEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: motion.chipCheck, // §9.2 dur.s chip 微交互
        curve: motion.springSnappy.curve,
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.outline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('capture_recent_chip_${entry.entryId}'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.summary.isEmpty ? '（无产出明细）' : entry.summary,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
