import 'package:flutter/material.dart';

/// 我的 Tab 占位页（§4.2：主题/同步状态/AI 开关/数据导出/订阅）。
///
/// 后续接入：主题编辑器（§4.3 /settings/theme，容器变换）、同步状态
/// （/settings/sync）、导出/清空/隐私政策（/settings/export）、订阅
/// （§3.9 双轨 IAP，W8-9 灰度）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('设置（W2+ 逐项接入）', style: textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '主题 · 同步状态 · AI 开关 · 数据导出 · 订阅（§4.2）',
              style:
                  textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
