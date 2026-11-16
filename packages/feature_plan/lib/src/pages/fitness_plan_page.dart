/// 健身计划占位页（§3.5 健身计划 P1、§5.5⑧、§11.1 W14 全量上线）。
///
/// W5-6 仅占位：读侧已接通（fitness_plans reactive 流），空库渲染空态
/// 引导文案；排期/模板/组明细（exercise_sets）W14 接入——手动记录的
/// type=template_instance 会话届时经排期生成（§5.5⑦ type 枚举）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_providers.dart';

/// 健身计划占位页。
class FitnessPlanPage extends ConsumerWidget {
  const FitnessPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final plans = ref.watch(fitnessPlansProvider).value;
    // W14 前无写路径：空库渲染空态引导；已有计划属防御路径，仅渲染列表。
    return Scaffold(
      appBar: AppBar(title: const Text('健身计划')),
      body: plans == null
          ? const Center(child: CircularProgressIndicator())
          : plans.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.calendar_month_outlined,
                          size: 48, color: tokens.kcalOut),
                      const SizedBox(height: 12),
                      Text(
                        '健身计划 W14 上线',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '计划模板（动作/组数/重量配比/休息秒）、周排期掩码与'
                        '排期日生成将在 W14 接入（§3.5 健身计划 P1、§5.5⑧⑨）；'
                        '届时排期会话 type=template_instance，与手动记录共用'
                        ' fitness_sessions 行模型（§5.5⑦）。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: plans.length,
                  itemBuilder: (context, index) {
                    final plan = plans[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: tokens.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          title: Text(plan.name,
                              style: TextStyle(
                                  fontSize: 15, color: tokens.onSurface)),
                          subtitle: Text('起始 ${plan.startDate}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: tokens.onSurfaceMuted)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
