import 'package:flutter/material.dart';

/// 账本 Tab 占位页（§4.2：流水列表+分类管理+预算入口+统计入口）。
///
/// W2 起接入手动记账全链路：流水按日分组（§4.3 /ledger）、分类管理
/// （/ledger/categories）、预算设置（/ledger/budgets，P0 含每日目标）、
/// 统计报表（/stats，P1 钱-热量双轴联动，§3.4）。
class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('账本')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('流水列表（W2 接入手动记账全链路）', style: textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '分类管理 · 预算入口 · 统计入口（§4.2）',
              style:
                  textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
