import 'package:flutter/material.dart';

/// 计划 Tab 占位页（§4.2：待办/健身/存钱三卡，骨架 P0、完整 P1）。
///
/// W2+ 接入：待办基础（§3.6，done_at 只前进合并）、健身手动记录
/// （§3.5，MET 估算）、存钱目标（§3.6，P1 留存钩子）。
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('计划')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('计划三件套骨架（待办 / 健身 / 存钱）', style: textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '待办与健身 W2+ 接入，存钱目标 P1（§4.2、§3.6）',
              style:
                  textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
