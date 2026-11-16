/// 归属日选择行（§5.1 本地日历日 yyyy-MM-dd + tz_offset_min；可回记）。
///
/// 自 W2 页面私有实现提取为公用（W3-4 确认卡/降级表单复用）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 日期行：点击唤起系统日期选择器（§3.3「账本/日期可调」）。
class CaptureDateRow extends StatelessWidget {
  const CaptureDateRow({super.key, required this.date, required this.onPicked});

  /// 当前归属日文本（yyyy-MM-dd）。
  final String date;
  final ValueChanged<DateTime> onPicked;

  DateTime? _parseDay(String text) {
    final parts = text.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _pick(BuildContext context) async {
    final initial = _parseDay(date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('capture_date_row'),
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 20, color: tokens.onSurfaceMuted),
              const SizedBox(width: 10),
              Text(
                date,
                style: TextStyle(fontSize: 15, color: tokens.onSurface),
              ),
              const Spacer(),
              Text(
                '归属日（可回记）',
                style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
