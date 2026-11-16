import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// context.slimca 语义色 token（§8.2）来自 ui_kit 主题扩展。
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../common/format.dart';
import '../../data/manual_entry_service.dart';
import '../dashboard/dashboard_state.dart';

/// 录入抽屉（§3.3 录入抽屉、§9.3#3 弹簧抽屉内容页；§4.2 capture 非路由页面）。
///
/// 职责（§11 W2 手动记账全链路的录入面）：
/// - 新建：标题 + 热量 + 金额一次录完，归属日取仪表盘选中日（§3.2「一切
///   围绕日期」，抽屉从哪天唤起就记到哪天）；
/// - 编辑：预填原事件主干与热量/金额行，保存走修正链（§6.5 金额不可变——
///   confirmed 后金额改写=新增 correction 行，历史永不改写）；
/// - 说/拍两通道 W3-4 语音、W11-12 拍照接入（§11），本页先给禁用反馈。
class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key, this.editEntryId});

  /// 非空=编辑已有事件（今日记录卡点入，§11 W2）；空=新建。
  final String? editEntryId;

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> {
  final _titleController = TextEditingController();
  final _kcalController = TextEditingController();
  final _amountController = TextEditingController();

  /// 归属日（本地日历日）；编辑态取原事件 date（§5.1）。
  DateTime? _date;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final editId = widget.editEntryId;
    if (editId == null) {
      // 新建：归属日=唤起时仪表盘选中日（§3.2）。
      _date = ref.read(selectedDateProvider);
    } else {
      _date = DateTime.now(); // 加载失败兜底；_loadForEdit 会覆写/关闭
      _loadForEdit(editId);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _kcalController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// 编辑态预填（§6.5：主干 title 直改，金额行预填后保存走 correction 链）。
  Future<void> _loadForEdit(String entryId) async {
    final entry = await ref.read(entryRepositoryProvider).findById(entryId);
    if (!mounted) return;
    if (entry == null || entry.isDeleted) {
      // 墓碑/缺失：抽屉直接关闭（§6.5 墓碑拒绝复活）。
      Navigator.of(context).pop();
      return;
    }
    final lines = await ref.read(entryLineRepositoryProvider).findByEntryId(entryId);
    int? kcal;
    int? amountMinor;
    for (final line in lines) {
      if (line.isDeleted || line.status != LineStatus.active) continue;
      switch (line.type) {
        case LineType.calorie:
          kcal ??= line.amount;
        case LineType.money:
          amountMinor ??= line.amount;
        case LineType.burn:
          break; // burn 行随 W3-5 运动记录接入编辑
      }
    }
    if (!mounted) return;
    setState(() {
      _date = DateTime.parse(entry.date);
      _titleController.text = entry.title;
      if (kcal != null) _kcalController.text = '$kcal';
      if (amountMinor != null) _amountController.text = minorToYuanText(amountMinor);
    });
  }

  bool get _hasInput =>
      _titleController.text.trim().isNotEmpty ||
      _kcalController.text.trim().isNotEmpty ||
      _amountController.text.trim().isNotEmpty;

  /// 表单校验文案（null=合法）；金额/热量口径见 §5.1 存储纪律。
  String? get _validationMessage {
    final kcalRaw = _kcalController.text.trim();
    if (kcalRaw.isNotEmpty) {
      final kcal = int.tryParse(kcalRaw);
      if (kcal == null || kcal < 0) return '热量请输入非负整数';
    }
    final amountRaw = _amountController.text.trim();
    if (amountRaw.isNotEmpty && parseYuanToFen(amountRaw) == null) {
      return '金额最多两位小数，如 25.50';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving || _date == null || !_hasInput) return;
    final validation = _validationMessage;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final kcal = int.tryParse(_kcalController.text.trim()) ?? 0;
      final amountMinor = parseYuanToFen(_amountController.text.trim()) ?? 0;
      final input = ManualEntryInput(
        date: formatCalendarDay(_date!),
        title: _titleController.text.trim().isEmpty
            ? '手动记录' // §5.2① title 兜底（手动通道无 AI 生成）
            : _titleController.text.trim(),
        kcal: kcal,
        amountMinor: amountMinor,
      );
      final editId = widget.editEntryId;
      if (editId == null) {
        await ref.read(manualEntryServiceProvider).saveNew(input);
      } else {
        await ref
            .read(manualEntryServiceProvider)
            .editEntry(entryId: editId, input: input);
      }
      if (!mounted) return;
      // 保存成功即收抽屉：§9.3#3 弹簧反向退场由路由自理；仪表盘明细流
      // 即时重发（§11 W2 验收线）。
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '保存失败：$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final validation = _validationMessage;
    final canSubmit = !_saving && _hasInput && validation == null;

    return Padding(
      // 键盘避让由抽屉内容自理（showSlimcaSpringSheet 契约，§9.3#3）。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽把手（§9.3#3 抽屉视觉）。
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 写/说/拍三通道（§3.3）：W2 只通写通道。
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.edit_outlined), label: Text('写')),
                ButtonSegment(value: 1, icon: Icon(Icons.mic_none_outlined), label: Text('说')),
                ButtonSegment(value: 2, icon: Icon(Icons.photo_camera_outlined), label: Text('拍')),
              ],
              selected: const {0},
              onSelectionChanged: (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('语音 W3-4、拍照 W11-12 接入（§11）')),
                );
              },
            ),
            const SizedBox(height: 12),
            // 归属日提示：抽屉从哪天唤起就记到哪天（§3.2）。
            Text(
              _date == null ? '' : '记录到 ${calendarDayLabel(formatCalendarDay(_date!))}',
              style: textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('captureTitleField'),
              controller: _titleController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '记了什么（可选）',
                hintText: '如：公司食堂午饭',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('captureKcalField'),
                    controller: _kcalController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '热量 kcal（可选）',
                      hintText: '如 500',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('captureAmountField'),
                    controller: _amountController,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '金额 元（可选）',
                      hintText: '如 25.50',
                    ),
                  ),
                ),
              ],
            ),
            // 校验/保存错误（§2.3 步 2 内联即时校验，无弹窗打断）。
            if (validation != null || _error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  validation ?? _error!,
                  style: textTheme.bodySmall?.copyWith(color: context.slimca.danger),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('captureSubmitButton'),
              onPressed: canSubmit ? _submit : null,
              // 保存中仅禁用按钮防重复提交；不做 spinner（§2.3 步 0 纪律）。
              icon: const Icon(Icons.check_outlined),
              label: Text(widget.editEntryId == null ? '记一笔' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}
