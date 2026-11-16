/// 存钱目标占位页（§3.6 存钱目标 P1 钩子、§5.5⑪⑫、§11.1 W13 全量上线）。
///
/// W5-6 仅占位：读侧已接通（目标 + Σ贡献进度 reactive 流，§5.5⑫
/// append-only 聚合），空库渲染空态引导文案；写路径（新建目标/打卡/365
/// 周存钱法格子）W13 接入——表结构与同步真值表 W1 已冻结（§10.4）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_providers.dart';

/// 存钱目标占位页。
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final goals = ref.watch(savingsGoalsProvider).value;
    if (goals == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('存钱目标')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // W13 前无写路径：空库渲染空态引导；已有目标属防御路径，仅渲染列表。
    return Scaffold(
      appBar: AppBar(title: const Text('存钱目标')),
      body: goals.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.savings_outlined,
                      size: 48, color: tokens.moneyOut),
                  const SizedBox(height: 12),
                  Text(
                    '存钱目标 W13 上线',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tokens.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '目标金额、每日/每周打卡、365 与 52 周存钱法格子将在 W13 接入'
                    '（§3.6 存钱目标 P1）；数据表 savings_goals / '
                    'savings_contributions 已建（§5.5⑪⑫），进度=Σ贡献，'
                    'append-only 免同步冲突（§6.1）。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: tokens.onSurfaceMuted),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: goals.length,
              itemBuilder: (context, index) {
                final view = goals[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: tokens.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      title: Text(view.goal.name,
                          style: TextStyle(
                              fontSize: 15, color: tokens.onSurface)),
                      subtitle: Text(
                        '${view.contributedYuan} / ${view.targetYuan} 元'
                        '（${(view.progress * 100).toStringAsFixed(0)}%）',
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
