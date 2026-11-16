/// 健身表单控制器（§3.5 健身手动记录、§10.1 Riverpod 3 AsyncNotifier）。
///
/// 与 feature_capture 的 CaptureController 同构（§10.4 同口径）：
/// - family 注入 [FitnessSeed]、autoDispose 跟随页面生命周期；
/// - build 异步装载身体档案体重（§3.5 身体档案 P0，MET 估算输入）；
/// - 提交经 [PlanGateway.submitFitnessSession] 同事务落三行（§5.5⑦），
///   成功返回会话 id；失败写 errorText 返回 null（不打断表单，§3.7）。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_met_table.dart';
import 'plan_gateway.dart';
import 'plan_models.dart';

/// 健身表单控制器 provider（§10.4；用法同 captureControllerProvider）。
final fitnessFormControllerProvider =
    AsyncNotifierProvider.family.autoDispose<FitnessFormController,
        FitnessFormState, FitnessSeed>(FitnessFormController.new);

/// 健身表单控制器：类型/强度/时长/体重/日期/备注的状态机与提交编排。
class FitnessFormController extends AsyncNotifier<FitnessFormState> {
  FitnessFormController(this.seed);

  /// 打开参数（初始归属日；null=今天，§5.1 日期约定）。
  final FitnessSeed seed;

  PlanGateway get _gateway => ref.read(planGatewayProvider);

  @override
  Future<FitnessFormState> build() async {
    final gateway = ref.watch(planGatewayProvider);
    final weight = await gateway.loadBodyWeightKg();
    final now = DateTime.now();
    return FitnessFormState(
      date: seed.initialDate ?? dom.formatCalendarDay(now),
      tzOffsetMin: now.timeZoneOffset.inMinutes,
      activity: kFitnessActivities.first,
      intensity: FitnessIntensity.mid,
      durationText: '',
      weightText: _formatWeight(weight),
    );
  }

  void _apply(FitnessFormState next) => state = AsyncData(next);

  /// 体重展示（整 kg 去尾 0；如 70.0→'70'、72.5→'72.5'）。
  static String _formatWeight(double weight) =>
      weight == weight.roundToDouble()
          ? '${weight.round()}'
          : weight.toStringAsFixed(1);

  /// 选中运动类型（§3.5 内置 MET 表选择）。
  void selectActivity(FitnessActivity activity) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(activity: activity, errorText: null));
  }

  /// 强度档（§3.5 低/中/高）。
  void selectIntensity(FitnessIntensity intensity) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(intensity: intensity, errorText: null));
  }

  /// 时长输入（分钟文本；合法性在 [FitnessFormState.durationMinutes]）。
  void setDurationText(String text) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(durationText: text, errorText: null));
  }

  /// 体重输入（kg 文本；合法性在 [FitnessFormState.weightKg]）。
  void setWeightText(String text) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(weightText: text, errorText: null));
  }

  /// 备注。
  void setNote(String note) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(note: note));
  }

  /// 归属日（本地日历日 yyyy-MM-dd，§5.1：一切聚合按 date 分组）。
  void setDate(DateTime picked) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(date: dom.formatCalendarDay(picked)));
  }

  /// 前后一日导航（±1 天；§3.5 列表按日查看配套）。
  void shiftDate(int days) {
    final current = state.value;
    if (current == null) return;
    final parts = current.date.split('-');
    if (parts.length != 3) return;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return;
    final shifted =
        DateTime(year, month, day).add(Duration(days: days));
    _apply(current.copyWith(
      date: dom.formatCalendarDay(shifted),
      tzOffsetMin: shifted.timeZoneOffset.inMinutes,
    ));
  }

  /// 提交（§3.5「估算 kcal → 一键落库」）：
  /// - 体重有改动先持久化进身体档案（§3.5 settings）；
  /// - 经网关同事务落 entries(kind=fitness) + burn 行 + fitness_sessions
  ///   （§5.5⑦），投影联动重算（§5.6）；
  /// - 成功返回会话 id 并清空时长/备注（便于连续记录）；失败写 errorText
  ///   返回 null（不抛异常打断表单，§3.7 本地优先）。
  Future<String?> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) return null;
    final gateway = _gateway;
    _apply(current.copyWith(submitting: true, errorText: null));
    try {
      final weight = current.weightKg!;
      await gateway.saveBodyWeightKg(weight);
      final sessionId = await gateway.submitFitnessSession(
        FitnessSessionDraft(
          date: current.date,
          tzOffsetMin: current.tzOffsetMin,
          activity: current.activity,
          intensity: current.intensity,
          durationS: current.durationMinutes! * 60,
          weightKg: weight,
          note: current.note.trim().isEmpty ? null : current.note.trim(),
        ),
      );
      _apply(current.copyWith(submitting: false, durationText: '', note: ''));
      return sessionId;
    } catch (_) {
      _apply(current.copyWith(submitting: false, errorText: '提交失败，请重试'));
      return null;
    }
  }
}
