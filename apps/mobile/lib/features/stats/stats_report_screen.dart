/// 统计报表壳层装配屏（§4.3 /stats「统计报表（周/月/年+双轴联动）」P1、
/// §11.2 W15 任务 1「报表页入口与路由」）。
///
/// 职责（§10.4 壳负责装配——页面本体在 feature_ledger `ReportPage`，本屏
/// 只做壳层接缝，不实现任何报表逻辑）：
/// - 注入 feature_ledger `ReportRepository`（day_summary 直读 + entry_lines
///   兜底，§5.6⑬）；
/// - W15 任务 4：report_viewed 漏斗在报表打开时记（props 空，§3.9 隐私
///   口径——埋点属壳层关注点，页面保持无遥测依赖）；
/// - 「看当日」下钻接线（§3.4「点图元 morph 下钻到当日记录」P1 的壳侧
///   落点）：桶键=日档 `yyyy-MM-dd` → 仪表盘选中日置位 + 回唯一首页。
library;

import 'dart:async';

import 'package:feature_ledger/feature_ledger.dart' show ReportPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../dashboard/dashboard_state.dart' show selectedDateProvider;
import '../../telemetry/w15_funnel_events.dart';

/// 统计报表屏（路由 /stats 的 builder 目标）。
class StatsReportScreen extends ConsumerStatefulWidget {
  const StatsReportScreen({super.key});

  @override
  ConsumerState<StatsReportScreen> createState() => _StatsReportScreenState();
}

class _StatsReportScreenState extends ConsumerState<StatsReportScreen> {
  @override
  void initState() {
    super.initState();
    // W15 任务 4：报表查看漏斗首步（页首帧即记；无内容字段，§3.9）。
    unawaited(
      ref
          .read(telemetryServiceProvider)
          .funnel(W15TelemetryFunnel.reportViewed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportPage(
      // 报表仓库（feature_ledger W15；周期切换/图表/双轴联动由页面承担）。
      repository: ref.watch(reportRepositoryProvider),
      // 「看当日」下钻（§3.4 P1 morph 的壳接线）：桶键=日档 yyyy-MM-dd
      // （年档=yyyy-MM 月桶，parse 取当月 1 日近似归属）→ 仪表盘选中日
      // 置位（SelectedDate 内部归一化为本地日历日）并回唯一首页
      // （§4.1 原则 1，任何页面 ≤2 次点击回仪表盘）。
      onEditEntry: (String bucketKey) {
        final DateTime? date = DateTime.tryParse(bucketKey);
        if (date == null) {
          return;
        }
        ref.read(selectedDateProvider.notifier).select(date);
        GoRouter.of(context).go('/');
      },
    );
  }
}
