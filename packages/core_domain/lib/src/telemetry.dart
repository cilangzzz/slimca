/// 遥测与漏斗埋点抽象（§3.9「监控：崩溃/性能监控+北极星与录入漏斗埋点」、
/// §2.3「北极星与漏斗纪律」、§11.1 W7-8「崩溃/性能与漏斗埋点」）。
///
/// 分层（§10.4）：本文件只定义接口与值对象（纯 Dart、无 Flutter 依赖），
/// 实现归宿主壳层——apps/mobile 提供 [TelemetryService] 的本地 JSONL 落盘
/// 实现（隐私口径见下）与测试用空实现；上传通道 W7-8 不启用（材料归档口径，
/// §3.9 合规专项）。
///
/// **隐私口径（§3.9 / §1.6 合规底线）**：遥测**不含内容字段**——只允许
/// 计数、耗时、错误类型、枚举标签；禁止记录用户原文、标题、备注、金额数值
/// 等业务内容。[TelemetryPrivacy] 是实现方必须经过的统一脱敏闸门。
///
/// 漏斗事件名（[TelemetryFunnel]，§12 验收口径——W8 内测起每周周报的链路）：
/// 冷启动/启动打开 → 首次启动锚 → 录入渠道选择 → 解析请求/成功/失败降级 →
/// 确认 → 同步 push/pull 成败。W9-10 北极星实测（§11.1）三项口径：
/// - **次日留存**：`first_open`（D0 锚，settings 落首次启动日）+ 每次启动
///   `app_open`（带 day_offset）——D1 存在 app_open 即留存，本地 JSONL 周报
///   可算（真机数据待实测）；
/// - **录入漏斗**：`capture_open`（打开）→ `capture_channel_selected`（输入）
///   → `parse_request/success/fallback`（解析）→ `capture_confirm`（确认），
///   护栏「文字路径打开→确认 ≤8s（P50）」经 metric
///   [TelemetryMetricName.captureOpenToConfirmMs]；
/// - **真机帧率**：metric [TelemetryMetricName.frameRasterMs] /
///   [TelemetryMetricName.frameDropped]（壳层 FrameTelemetry 装配，
///   仅真机 profile/release 有效，数字待真机实测）。
library;

/// 遥测记录类型（§3.9：崩溃 / 性能 / 漏斗三类）。
enum TelemetryKind {
  funnel('funnel'),
  metric('metric'),
  crash('crash');

  const TelemetryKind(this.wire);

  /// 落盘/上报用文本（JSONL kind 字段）。
  final String wire;
}

/// 一条遥测记录值对象（JSONL 落盘与未来上报通道的统一格式，§3.9）。
///
/// [props] 只允许标量（bool/int/double/String）且必须经
/// [TelemetryPrivacy.sanitizeProps] 脱敏——内容字段在源头即被剔除。
class TelemetryEvent {
  const TelemetryEvent({
    required this.kind,
    required this.name,
    required this.atMs,
    this.props = const {},
  });

  /// 记录类型（funnel / metric / crash，§3.9 三类）。
  final TelemetryKind kind;

  /// 事件名（漏斗事件名见 [TelemetryFunnel]；metric=指标名；crash 固定
  /// 传错误类型时由实现方组织）。
  final String name;

  /// 记录时刻 UTC 毫秒。
  final int atMs;

  /// 已脱敏的标量属性集（§3.9 隐私口径：仅计数/耗时/错误类型/枚举标签）。
  final Map<String, Object?> props;

  Map<String, Object?> toJson() => <String, Object?>{
        'ts': atMs,
        'kind': kind.wire,
        'name': name,
        'props': props,
      };

  /// 反序列化（导出/回放工具用）；坏行返回 null（调用方跳过，不中断回放）。
  static TelemetryEvent? fromJson(Map<String, Object?> json) {
    final kindWire = json['kind'];
    final name = json['name'];
    final ts = json['ts'];
    if (name is! String || ts is! int) return null;
    final kind = switch (kindWire) {
      'funnel' => TelemetryKind.funnel,
      'metric' => TelemetryKind.metric,
      'crash' => TelemetryKind.crash,
      _ => null,
    };
    if (kind == null) return null;
    final props = json['props'];
    return TelemetryEvent(
      kind: kind,
      name: name,
      atMs: ts,
      props: props is Map<String, Object?> ? props : const {},
    );
  }
}

/// §12 验收口径漏斗事件名常量（§2.3 北极星与漏斗纪律：W8 内测起每周周报）。
abstract final class TelemetryFunnel {
  /// 冷启动完成（首帧栅格化=可交互基线，§2.3 步 0 ≤1.2s）。
  static const String coldStartComplete = 'cold_start_complete';

  /// 首次启动（W9-10 北极星·次日留存的 D0 锚点：首次启动日由壳层落
  /// settings 本地件；此后每次启动记 [appOpen] 并带 day_offset）。
  static const String firstOpen = 'first_open';

  /// 每次启动打开（W9-10 北极星·次日留存的分子数据源：props.day_offset =
  /// 距 first_open 的日历日偏移，0=当日、1=次日；某设备存在 day_offset=1
  /// 的 app_open 即计入次日留存——本地 JSONL 周报可算，数字待真机实测）。
  static const String appOpen = 'app_open';

  /// 录入抽屉打开（§2.3 录入漏斗首步「打开」；W9-10 补齐的漏斗起点，
  /// 同时是护栏「打开→确认 ≤8s（P50）」的计时起点）。
  static const String captureOpen = 'capture_open';

  /// 录入渠道选择（写/说/拍，§3.3 三通道）。
  static const String captureChannelSelected = 'capture_channel_selected';

  /// AI 解析请求发出（§7.1 管线入口）。
  static const String parseRequest = 'parse_request';

  /// AI 解析成功（含缓存命中复用，§3.3 input_hash）。
  static const String parseSuccess = 'parse_success';

  /// AI 解析失败降级手填（§7.4：失败 100% 降级不卡死）。
  static const String parseFallback = 'parse_fallback';

  /// 确认落库（§2.3 步 5；获取漏斗「打开→输入→解析→确认」终点）。
  static const String captureConfirm = 'capture_confirm';

  /// 同步 push 成功（网络层送达，§6.2 写路径）。
  static const String syncPushOk = 'sync_push_ok';

  /// 同步 push 失败（分区/协议错误，§6.1 原则 1 只降级提示）。
  static const String syncPushFail = 'sync_push_fail';

  /// 同步 pull 成功（§6.2 读路径）。
  static const String syncPullOk = 'sync_pull_ok';

  /// 同步 pull 失败。
  static const String syncPullFail = 'sync_pull_fail';

  // ── W13 留存钩子漏斗（原壳层常量收编：apps/mobile w13_funnel_events.dart
  //    「后续若 core_domain 收编再平移」的既定迁移点；事件 wire 名与 W13
  //    任务口径一字不差，写入方=feature_plan PlanGateway——漏斗跟随唯一
  //    写路径，壳层双实现收敛后不在 UI 层重复埋点）。

  /// 存钱目标建档（§3.6 存钱目标 P1：留存钩子首步——「设目标」）。
  static const String savingsGoalCreated = 'savings_goal_created';

  /// 投币打卡（§3.6「投币式打卡」：进度=贡献行求和 §5.5⑫——「存进去」；
  /// 仅真实新增时记，幂等命中不重复计）。
  static const String coinIn = 'coin_in';

  /// 重复待办建档（§3.6 待办完整版 P1「重复（RRULE）」+ 提醒）。
  static const String todoRecurrenceCreated = 'todo_recurrence_created';
}

/// 指标（metric）事件名常量（§3.9 性能监控、§9.4 帧预算、§2.3 护栏口径）。
///
/// metric 名与漏斗事件名分立：metric 落盘为 `kind=metric`，props 携带
/// `value`/`unit`/tags（全部标量，§3.9 隐私口径）。
abstract final class TelemetryMetricName {
  /// 录入「打开→确认」护栏耗时（§2.3：文字路径 ≤8s（P50）、拍照 ≤15s；
  /// W9-10 北极星·录入漏斗的护栏数据源）。
  static const String captureOpenToConfirmMs = 'capture_open_to_confirm_ms';

  /// 帧栅格耗时批次聚合（§9.4 raster ≤16ms；value=批内最大 raster ms，
  /// tags：frames/dropped/max_build_ms/raster_over_budget/build_over_budget）。
  /// 仅真机 profile/release 有效（debug JIT 失真不采），数字待真机实测。
  static const String frameRasterMs = 'frame_raster_ms';

  /// 丢帧计数（§9.4 满动效丢帧 <1%（G99 级）：value=批内丢帧数，tags.frames
  /// =批内总帧数；丢帧判定=totalSpan > 1/60s，与 DevTools 帧率口径一致）。
  static const String frameDropped = 'frame_dropped';

  /// 同步一轮耗时（§6.2 全链路；壳层 SyncCoordinator 落盘）。
  static const String syncCycleMs = 'sync_cycle_ms';
}

/// 遥测隐私闸门（§3.9「不含内容字段，仅计数/耗时/错误类型」的强制实现点）。
///
/// 实现方（落盘/上报）必须先经 [sanitizeProps]；属性键黑名单防「顺手把原文
/// 塞进 props」的意外泄漏，非标量值（Map/List/对象）一律剔除。
abstract final class TelemetryPrivacy {
  /// 内容字段键黑名单：以这些键名记录的属性一律丢弃（§3.9 隐私口径）。
  ///
  /// 注意 `error_type`/`error_code` 不在黑名单内（错误**类型**是允许字段，
  /// 错误**内容/message** 才是禁入内容）。
  static const Set<String> forbiddenKeys = <String>{
    'raw',
    'raw_input',
    'input',
    'text',
    'content',
    'message',
    'note',
    'title',
    'body',
    'payload',
    'prompt',
    'stack',
    'error',
  };

  /// 属性集脱敏：剔除黑名单键与非标量值；字符串截断到 [maxStringLength]
  /// （防长文本借道枚举键）。返回新 Map、不修改入参。
  static Map<String, Object?> sanitizeProps(
    Map<String, Object?>? props, {
    int maxStringLength = 64,
  }) {
    final sanitized = <String, Object?>{};
    props?.forEach((key, value) {
      if (forbiddenKeys.contains(key)) return;
      final value_ = sanitizeValue(value, maxStringLength: maxStringLength);
      if (value_ != null) {
        sanitized[key] = value_;
      }
    });
    return sanitized;
  }

  /// 单值脱敏：仅放行 bool/int/double/String（截断）；其余返回 null。
  static Object? sanitizeValue(Object? value, {int maxStringLength = 64}) {
    if (value == null) return null;
    if (value is bool || value is int || value is double) return value;
    if (value is String) {
      return value.length <= maxStringLength
          ? value
          : value.substring(0, maxStringLength);
    }
    return null;
  }
}

/// 遥测服务抽象（§3.9「监控：崩溃/性能监控+北极星与录入漏斗埋点」）。
///
/// 实现约束：
/// - 隐私（§3.9）：写入/上报前一律经 [TelemetryPrivacy] 脱敏；
/// - 永不阻塞（§6.1 原则 1 同款纪律）：遥测失败不得影响主流程，方法内部
///   自行兜底，不向上抛异常；
/// - crash 只记错误类型与堆栈帧数（错误内容禁入，§3.9）。
abstract interface class TelemetryService {
  /// 漏斗事件（§2.3/§12 验收口径：W8 起每周周报的数据源）。
  Future<void> funnel(String name, {Map<String, Object?>? props});

  /// 性能指标（耗时/计数，§3.9 崩溃/性能监控；帧预算 §9.4 的实测口径）。
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  });

  /// 崩溃上报（§3.9）：只记错误类型（runtimeType）与堆栈帧数，[error] 的
  /// message/toString 一律不落盘。
  Future<void> crash(Object error, StackTrace? stackTrace, {String? source});

  /// 刷盘（进程退出前的兜底；逐条落盘的实现可为空操作）。
  Future<void> flush();
}
