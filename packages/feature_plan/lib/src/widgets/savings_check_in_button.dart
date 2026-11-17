/// 投币打卡按钮（§3.6 存钱目标「投币式打卡」、§5.5⑫ append-only 贡献、
/// §11.2 W13 主线）。
///
/// 状态防重复（§3.6）：当日已有人工投币行（source='manual'，§5.5⑫ v1 补列）
/// → 置灰「今日已投币」；真正的防重复兜底在 DAO 幂等键
/// (goal_id, date, source)——SavingsContributionsDao.append 同日重复追加为
/// no-op（首写胜），双击/竞态不产生重复行。
///
/// 投币动效（§3.6「投币式打卡动效」）：金额经 SlimcaCountUp 递增（§9.3#4
/// count-up token）、目标进度环 springSoft 续播（progress_ring.dart）——
/// 均复用 ui_kit 既有动效 token，本组件不引入新时长。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../plan_providers.dart';
import '../rrule.dart';

/// 打卡按钮测试锚点（`savings_check_in_$goalId`）。
Key savingsCheckInKey(String goalId) => ValueKey('savings_check_in_$goalId');

/// 投币打卡按钮（当日贡献；§3.6）。
class SavingsCheckInButton extends ConsumerWidget {
  const SavingsCheckInButton({
    super.key,
    required this.goal,
    this.expanded = false,
  });

  /// 目标行（§5.5⑪）：格子推算与幂等键三元组的目标 id 来源。
  final cdb.SavingsGoal goal;

  /// true=撑满可用宽度（详情页主按钮形态）。
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final gateway = ref.read(planGatewayProvider);
    final today = featureLocalToday();
    // 当日人工投币行（§5.5⑫ source='manual'）：非空=今日已投币（§3.6 状态
    // 防重复）；流直驱——append 落行后本按钮自动翻到置灰态。
    final contribution =
        ref.watch(todayManualContributionProvider((goal.id, today))).value;
    final step = gateway.savingsStepForDay(goal: goal, day: today);

    // 未开跑（day < started_on）或 rhythm 不可推算：无格子可投。
    if (step == null) {
      return _button(
        key: null,
        onPressed: null,
        label: '未开始',
        icon: Icons.savings_outlined,
        foreground: tokens.onSurfaceMuted,
      );
    }
    final alreadyDone = contribution != null;
    return _button(
      key: alreadyDone ? null : savingsCheckInKey(goal.id),
      onPressed: alreadyDone
          ? null
          : () => gateway.contributeToGoal(goalId: goal.id, date: today),
      label: alreadyDone
          ? '今日已投币'
          : '投币 ${(step.amountMinor / 100).toStringAsFixed(2)} 元',
      icon: alreadyDone ? Icons.check_circle_outline : Icons.savings,
      foreground: alreadyDone ? tokens.onSurfaceMuted : null,
    );
  }

  Widget _button({
    required Key? key,
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    Color? foreground,
  }) {
    final button = FilledButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    return expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
