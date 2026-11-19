/// 计划域网关：健身手动记录落库编排 + 待办/存钱/计划读写（§3.5、§3.6、
/// §5.5、§11.1 W5-6、§11.2 W13、§10.4 分层）。
///
/// 分层边界（§10.4「接口在 core_domain、实现在 core_db」）：持久化语义全部
/// 复用 core_db 既有件——
/// - 事件/产出行落库走 `DriftEntryRepository` / `DriftEntryLineRepository`
///   （软删墓碑、投影联动等仓库契约不在此重写）；
/// - 待办复用 `TodoDao`（done_at 只前进合并、收集箱语义、投影联动；W13 增
///   重复/提醒三字段透传，§5.5⑩）；重复实例的**查询时展开**在本网关完成
///   （不预生成行，§3.6/§11.2 W13，取舍见 rrule.dart 文档注释）；
/// - 存钱复用 `SavingsGoalsDao` / `SavingsContributionsDao`（W13，§5.5⑪⑫）：
///   append-only 贡献、(goal_id, date, source) 幂等打卡、目标写/贡献写路径
///   同事务联动 day_summary.savings_progress 重算（§5.6⑬ W13 实装）；
///   **账本联动取舍（§12.2 开放问题 #9）**：贡献行是纯 append-only 记录，
///   V1 不生成 entries/entry_lines（不双重记账）——与账本流水联动待观察
///   需求后再拍板，本网关存钱写路径均不触账本表（待拍板项注释）；
/// - 本网关只做 feature 层编排：§5.5⑦ 会话三行同事务（entries(kind=fitness)
///   + entry_lines(type=burn,out) + fitness_sessions），burn 行 payload 记
///   session_id 与 MET 参数（§2.2/§5.5/§5.7 facet 行同步模型）。
///
/// 宿主装配（§10.4 壳负责装配）：override [planGatewayProvider]，其中
/// [dom.HlcClock] 必须是应用级单例（HLC 单调性是全设备唯一全序来源）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_met_table.dart';
import 'fitness_plan_models.dart';
import 'plan_models.dart';
import 'rrule.dart' show TodoRepeatSpec, parseRrule, rruleOccursOn;

/// settings 键：身体档案体重 kg（§3.5 身体档案 P0；MET 估算输入）。
/// value 为 JSON 文本（§5.6⑲ settings.value TEXT(JSON)）。
const String kSettingBodyWeightKg = 'body_weight_kg';

/// MET 估算默认体重（§3.5：体重取自身体档案；档案缺省值 70 kg）。
const double kDefaultBodyWeightKg = 70.0;

/// 依赖注入点（§10.4：壳负责装配）。宿主必须 override：
/// `planGatewayProvider.overrideWithValue(createPlanGateway(db, clock))`。
/// 未 override 直接读即抛错——装配遗漏在开发期立刻暴露，而非静默错库。
final Provider<PlanGateway> planGatewayProvider = Provider<PlanGateway>(
  (ref) => throw UnimplementedError(
    '宿主必须 override planGatewayProvider（§10.4 壳负责装配）：'
    'planGatewayProvider.overrideWithValue('
    'createPlanGateway(db: AppDatabase, clock: HlcClock))',
  ),
);

/// 构造计划域网关（宿主装配入口）。
///
/// [projection] 缺省时自动建 [cdb.DaySummaryProjection]——W5-6 起所有写路径
/// （会话三行、待办勾选、W13 存钱目标/贡献）都必须联动重算投影（§5.6 重建
/// 规则），故网关内投影恒非空，并注入各 DAO（存钱进度驱动
/// day_summary.savings_progress「写后重算当日」在 DAO 写事务内完成，
/// §5.6⑬ W13 实装）。
///
/// [telemetry] 缺省 null（测试/未装配环境零副作用）：W13 留存钩子漏斗
/// （savings_goal_created / coin_in / todo_recurrence_created）跟随唯一写
/// 路径在网关侧记——壳层双实现收敛后不在 UI 层重复埋点（事件名常量见
/// core_domain TelemetryFunnel W13 段）。
PlanGateway createPlanGateway({
  required cdb.AppDatabase db,
  required dom.HlcClock clock,
  cdb.DaySummaryProjection? projection,
  dom.TelemetryService? telemetry,
}) {
  final effectiveProjection = projection ?? cdb.DaySummaryProjection(db);
  return PlanGateway._(
    database: db,
    clock: clock,
    projection: effectiveProjection,
    entries: cdb.DriftEntryRepository(db, projection: effectiveProjection),
    entryLines:
        cdb.DriftEntryLineRepository(db, projection: effectiveProjection),
    todos: cdb.TodoDao(db, projection: effectiveProjection),
    savingsGoals:
        cdb.SavingsGoalsDao(db, projection: effectiveProjection),
    savingsContributions:
        cdb.SavingsContributionsDao(db, projection: effectiveProjection),
    telemetry: telemetry,
  );
}

/// 计划域网关：健身会话写编排 + 待办/存钱/健身计划读写（§11.1 W5-6、§11.2 W13）。
class PlanGateway {
  PlanGateway._({
    required cdb.AppDatabase database,
    required this.clock,
    required this.projection,
    required this.entries,
    required this.entryLines,
    required this.todos,
    required this.savingsGoals,
    required this.savingsContributions,
    this.telemetry,
  })  : db = database,
        outbox = cdb.SyncOutboxWriter(database);

  final cdb.AppDatabase db;

  /// 出网入队器（§5.6⑯/§6.2）：W14 起计划域新增写路径（fitness_plans/
  /// fitness_sessions/exercise_sets 及其 entry/burn 行）统一经本器在业务写
  /// **同事务**内读回行快照入队（§6.2「业务行 + sync_outbox 同事务写入」；
  /// W5-6 的手动记录路径先于本器落地、未入队，见 submitFitnessSession 注记）。
  final cdb.SyncOutboxWriter outbox;

  /// 应用级单例时钟（§6.3）：本网关签发的所有行 HLC 皆源于此。
  final dom.HlcClock clock;

  /// day_summary 投影（§5.6⑬）：恒非空，写后联动重算。
  final cdb.DaySummaryProjection projection;

  /// 遥测注入点（W13 留存钩子漏斗；null=测试/未装配零副作用，§3.9）。
  final dom.TelemetryService? telemetry;

  /// 事件主干仓库（core_db 实现，§10.4）。
  final cdb.DriftEntryRepository entries;

  /// 产出行仓库（core_db 实现）。
  final cdb.DriftEntryLineRepository entryLines;

  /// 待办 DAO（core_db 实现，done_at 只前进合并，§6.5；W13 重复/提醒三字段，
  /// §5.5⑩）。
  final cdb.TodoDao todos;

  /// 存钱目标 DAO（core_db 实现，§5.5⑪；W13）。
  final cdb.SavingsGoalsDao savingsGoals;

  /// 存钱贡献 DAO（core_db 实现，append-only + 幂等打卡，§5.5⑫；W13）。
  final cdb.SavingsContributionsDao savingsContributions;

  // ── 内部签发辅助（§5.1 公共列 / §6.3 HLC）─────────────────────────

  int get _nowMs => clock.wallClock();

  String _newId() => cdb.generateUuidV7();

  /// 新行的公共列（§5.1）：hlc 由 HlcClock 签发、revision 本地自增起步=1。
  dom.SyncMeta _newMeta() => dom.SyncMeta(
        createdAt: _nowMs,
        updatedAt: _nowMs,
        hlc: clock.now().format(),
        revision: 1,
        deviceId: clock.deviceId,
      );

  /// 内置 kcal 账本（§5.2②「kcal 行归集到内置 kcal 账本」、§5.4④「不可删除
  /// 不可多开」）：seed 保证恰一个，此处兜底惰性创建（幂等；与 feature_capture
  /// 的 ensureKcalLedger 同口径）。
  Future<cdb.Ledger> _ensureKcalLedger() async {
    final rows = await (db.select(db.ledgers)
          ..where((t) => t.kind.equals('kcal') & t.deletedAt.isNull()))
        .get();
    if (rows.isNotEmpty) return rows.first;
    final row = cdb.Ledger(
      id: _newId(),
      name: '热量账本',
      icon: 'local_fire_department',
      currency: 'kcal',
      kind: 'kcal',
      sort: 0,
      openingBalanceMinor: 0,
      isArchived: false,
      createdAt: _nowMs,
      updatedAt: _nowMs,
      deletedAt: null,
      hlc: clock.now().format(),
      revision: 1,
      schemaVer: dom.kCurrentSchemaVer,
      deviceId: clock.deviceId,
    );
    await db.into(db.ledgers).insert(row);
    return row;
  }

  // ── 健身手动记录写路径（§3.5、§5.5⑦、§11.1 W5-6）─────────────────

  /// 提交一次手动健身：同事务落三行（§5.5⑦ entry_id 联动、§2.2 事务一致）：
  /// - entries：kind=fitness、source=manual、status=confirmed（§5.2①）；
  /// - entry_lines：type=burn、direction=out、amount=MET 估算 kcal、归集
  ///   内置 kcal 账本、confidence=null（人工行无置信度，§5.2②），payload 记
  ///   session_id + MET 参数（§5.2② payload「MET 参数」）；
  /// - fitness_sessions：§5.5⑦ 列语义，entry_id 回填事件 id。
  ///
  /// 投影联动（§5.6）：burn 行经仓库 upsert 在同事务重算当日 kcal_out/
  /// net_kcal。返回会话 id。
  ///
  /// start_at 语义（§5.5⑦ 可空）：仅当日记录回填 `now - duration`（手动补记
  /// 无真实开始时刻）；非当日留 null——UI 只按日期归档展示。
  ///
  /// outbox 纪律（§6.2「业务行 + sync_outbox 同事务写入」）：会话/事件/burn
  /// 三行在**同事务**内读回行快照入队（[outbox.enqueueRow] 读回行终态构
  /// payload）——原 W5-6 口径「壳层 FitnessService 自带入队」已随壳层双实现
  /// 收敛删除，手动记录写路径唯一在本网关，漏入队=静默丢同步（坑点 #4）。
  Future<String> submitFitnessSession(FitnessSessionDraft draft) async {
    // MET 估算（§3.5 kcal = MET × 体重kg × 时长h）；非法入参在此抛错。
    final kcal = estimateKcalBurn(
      activity: draft.activity,
      intensity: draft.intensity,
      durationS: draft.durationS,
      weightKg: draft.weightKg,
    );
    final ledger = await _ensureKcalLedger();
    final entryId = _newId();
    final sessionId = _newId();
    final lineId = _newId();
    // 与壳侧 FitnessService._deriveTitle 同口径：「类型 + N 分钟」
    // （§5.2① title 一句话描述；apps/mobile/lib/data/fitness_service.dart）。
    final title =
        draft.title ?? '${draft.activity.name} ${draft.durationS ~/ 60} 分钟';
    final now = DateTime.fromMillisecondsSinceEpoch(_nowMs);
    final isToday = dom.formatCalendarDay(now) == draft.date;
    final startAt = isToday ? _nowMs - draft.durationS * 1000 : null;
    final payload = jsonEncode(<String, Object?>{
      'session_id': sessionId,
      'activity_id': draft.activity.id,
      'activity_name': draft.activity.name,
      'met': draft.activity.metFor(draft.intensity),
      'intensity': draft.intensity.wire,
      'weight_kg': draft.weightKg,
    }..removeWhere((k, v) => v == null));

    // Drift 嵌套事务：内层（仓库自身的 transaction）join 外层事务（§6.2
    // 「业务行 + 投影同事务」）。三行各自独立 HLC（行级同步，§5.7）。
    await db.transaction(() async {
      await entries.upsert(dom.Entry(
        id: entryId,
        date: draft.date,
        tzOffsetMin: draft.tzOffsetMin,
        occurredAt: _nowMs,
        kind: dom.EntryKind.fitness,
        source: dom.EntrySource.manual,
        title: title,
        note: draft.note,
        status: dom.EntryStatus.confirmed,
        aiParseId: null,
        meta: _newMeta(),
      ));
      await entryLines.upsert(dom.EntryLine(
        id: lineId,
        entryId: entryId,
        type: dom.LineType.burn,
        amount: kcal,
        direction: dom.LineDirection.outcome, // burn=out（§5.2②）
        ledgerId: ledger.id,
        categoryId: null,
        currency: null,
        confidence: null, // 人工行无置信度（§5.2② AI 产出行必填）
        payload: payload,
        correctionOf: null,
        status: dom.LineStatus.active,
        meta: _newMeta(),
      ));
      await db.into(db.fitnessSessions).insert(cdb.FitnessSession(
            id: sessionId,
            date: draft.date,
            tzOffsetMin: draft.tzOffsetMin,
            startAt: startAt,
            durationS: draft.durationS,
            type: draft.activity.type.wire, // §5.5⑦ type 枚举
            kcalBurn: kcal,
            entryId: entryId,
            source: 'manual', // §5.5⑦ source 枚举
            planDayId: null, // P1 健身计划排期（§11.1 W14）
            note: draft.note,
            createdAt: _nowMs,
            updatedAt: _nowMs,
            deletedAt: null,
            hlc: clock.now().format(),
            revision: 1,
            schemaVer: dom.kCurrentSchemaVer,
            deviceId: clock.deviceId,
          ));
      // ④ §6.2 出网：三行业务行快照同事务入队（enqueueRow 在业务写之后
      // 调用，读回行终态构 payload——坑点 #4 纪律）。
      await outbox.enqueueRow('fitness_sessions', sessionId);
      await outbox.enqueueRow('entries', entryId);
      await outbox.enqueueRow('entry_lines', lineId);
    });
    return sessionId;
  }

  /// 删除健身会话（§5.1 删除行软删墓碑、§6.5 墓碑拒绝复活）：
  /// 会话行打墓碑 + 关联事件经仓库 softDelete（其内联动重算投影，kcal_out
  /// 即时回落）。行不存在或已删为幂等 no-op。
  Future<void> deleteFitnessSession(String sessionId) async {
    await db.transaction(() async {
      final row = await (db.select(db.fitnessSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (row == null) return;
      final hlc = clock.now();
      if (row.deletedAt == null) {
        await (db.update(db.fitnessSessions)
              ..where((t) => t.id.equals(sessionId)))
            .write(cdb.FitnessSessionsCompanion(
          deletedAt: Value(hlc.physicalMs),
          updatedAt: Value(hlc.physicalMs),
          hlc: Value(hlc.format()),
          revision: Value(row.revision + 1),
        ));
      }
      final entryId = row.entryId;
      if (entryId != null && row.deletedAt == null) {
        // 事件软删：仓库内同事务刷新公共列并重算归属日投影（§5.6）。
        await entries.softDelete(entryId, hlc: hlc.format());
      }
    });
  }

  /// 某日会话列表（未删；最近录入在前）——按日查看（§3.5 列表可按日查看）。
  Stream<List<cdb.FitnessSession>> watchSessionsByDate(String date) {
    return (db.select(db.fitnessSessions)
          ..where((t) => t.date.equals(date) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.hlc),
          ]))
        .watch();
  }

  // ── 身体档案：体重（§3.5 身体档案 P0，MET 估算输入）────────────────

  /// 读体重 kg（settings 缺失/坏值回退 [kDefaultBodyWeightKg]，§7.4 健壮性）。
  Future<double> loadBodyWeightKg() async {
    final row = await (db.select(db.settings)
          ..where((t) => t.key.equals(kSettingBodyWeightKg)))
        .getSingleOrNull();
    if (row == null) return kDefaultBodyWeightKg;
    final parsed = double.tryParse('${jsonDecode(row.value)}');
    if (parsed == null || parsed <= 0) return kDefaultBodyWeightKg;
    return parsed;
  }

  /// 写体重 kg（settings UPSERT；§5.6⑲ settings.value TEXT(JSON)）。
  Future<void> saveBodyWeightKg(double weightKg) {
    return db.into(db.settings).insertOnConflictUpdate(
          cdb.SettingsCompanion.insert(
            key: kSettingBodyWeightKg,
            value: jsonEncode(weightKg),
          ),
        );
  }

  // ── 待办（§3.6 待办基础 P0 + 完整版 W13、§5.5⑩；复用 TodoDao，§10.4）──

  /// 新建待办：[date] null=收集箱（§5.5⑩ date NULL=收集箱）。
  ///
  /// W13 重复/提醒（§3.6 完整版、§11.2 W13 主线）：
  /// - [repeatRule] 为 RRULE 文本（编辑器经 TodoRepeatSpec.toRrule 构造）；
  /// - [rruleAnchorDate] 缺省 null → TodoDao 落库时取 [date] 作 DTSTART
  ///   （重复待办自计划日起展开）；收集箱（date=NULL）不支持重复（无展开
  ///   起点，编辑器入口已隐藏）；
  /// - [remindAt] 为提醒时刻 UTC ms（本层只落字段；真实通知由壳层调度，
  ///   §3.6 P1——apps/mobile 接本地通知插件后按 remind_at 本地时:分 +
  ///   RRULE 逐实例重排）。
  Future<cdb.Todo> createTodo({
    required String title,
    String? date,
    String? note,
    int? dueAt,
    String? repeatRule,
    String? rruleAnchorDate,
    int? remindAt,
  }) async {
    final todo = await todos.create(
      title: title,
      date: date,
      note: note,
      dueAt: dueAt,
      repeatRule: repeatRule,
      rruleAnchorDate: rruleAnchorDate,
      remindAt: remindAt,
    );
    // W13 漏斗（§11.2 W13 任务 4）：重复待办建档即记——props 只带频率枚举
    // （§3.9 内容禁入遥测）。原壳层快速添加路径的埋点随写路径收敛迁移至此。
    final rule = repeatRule;
    if (telemetry != null && rule != null && rule.trim().isNotEmpty) {
      await telemetry!.funnel(
        dom.TelemetryFunnel.todoRecurrenceCreated,
        props: <String, Object?>{'freq': _repeatFreqOf(rule)},
      );
    }
    return todo;
  }

  /// RRULE → 频率枚举（`FREQ=DAILY;…` → `daily`；无 FREQ 防御回 `?`）。
  static String _repeatFreqOf(String rule) => rule
      .split(';')
      .firstWhere((p) => p.startsWith('FREQ='), orElse: () => 'FREQ=?')
      .substring(5)
      .toLowerCase();

  /// 更新待办（标题/备注/重复规则/提醒）。
  ///
  /// [repeatRule]/[remindAt] 显式覆盖（null=清空，§5.5⑩）。锚点策略
  /// （§5.5⑩ rrule_anchor_date，上层决策口径）：[clearAnchor]=true → 锚点
  /// 置空（清空规则时 series 终结）；[anchorDate] 非空 → 锚点设为该日；
  /// 两者都缺省 → 锚点不改动（TodoDao.updateDetails 哨兵透传）。
  Future<void> updateTodoDetails({
    required String id,
    String? title,
    String? note,
    String? repeatRule,
    int? remindAt,
    bool clearAnchor = false,
    String? anchorDate,
  }) async {
    // W13 漏斗：重复规则「无 → 有」的建档转换与 createTodo 同口径记一次
    // （档位编辑/清空不重复计，§3.9 props 只带频率枚举）。
    final priorRule = repeatRule == null
        ? null
        : (await (db.select(db.todos)..where((t) => t.id.equals(id)))
              .getSingleOrNull())
            ?.repeatRule;
    await todos.updateDetails(
      id: id,
      title: title,
      note: note,
      repeatRule: repeatRule,
      remindAt: remindAt,
      rruleAnchorDate:
          clearAnchor ? null : (anchorDate ?? _unchanged),
    );
    final rule = repeatRule;
    final priorHasRule =
        priorRule != null && priorRule.trim().isNotEmpty;
    if (telemetry != null &&
        rule != null &&
        rule.trim().isNotEmpty &&
        !priorHasRule) {
      await telemetry!.funnel(
        dom.TelemetryFunnel.todoRecurrenceCreated,
        props: <String, Object?>{'freq': _repeatFreqOf(rule)},
      );
    }
  }

  /// 勾选/取消完成（done_at 只前进合并，§6.5；投影联动 todo_done）。
  ///
  /// 重复待办实例的勾选同样作用于基行（不物化实例行，W13）：勾选当日实例
  /// → 基行 done_at=now（落在实例日 → 当日实例呈完成态）；跨设备并发合并
  /// 语义不变（set 胜，§6.5）。
  Future<void> setTodoDone(String id, {required bool done}) =>
      todos.setDone(id, done: done);

  /// 删除待办（软删墓碑，§5.1）。重复待办删除作用于整条 series 基行
  /// （v1 口径：无「仅删除当日实例」——实例不落行，删除当日实例无从落列，
  /// 升级路径见 rrule.dart 文档注释）。
  Future<void> deleteTodo(String id) => todos.softDelete(id);

  /// 收集箱 → 今日：回填计划日（§3.6「一键安排到今天」）。
  Future<void> moveTodoToToday(String id, {required String date}) =>
      todos.updateDetails(id: id, date: date);

  /// 某日待办流（未完成在前）。
  Stream<List<cdb.Todo>> watchTodosByDate(String date) =>
      todos.watchByDate(date);

  /// 收集箱流（date IS NULL，排除墓碑）。
  Stream<List<cdb.Todo>> watchInboxTodos() => todos.watchInbox();

  /// 某日待办**实例**流（§3.6 待办完整版 W13）。
  ///
  /// 展开策略（W13，取舍详见 rrule.dart 文档注释）：查询时按 anchor 展开当日
  /// 实例、不预生成行——
  /// - 非重复行：date=[date] 直出（done=done_at 非空，W5-6 行为不变）；
  /// - 重复行（repeat_rule 可解析且锚点非空）：rruleOccursOn(anchor, rule,
  ///   [date]) 命中 → 虚拟实例（done=done_at 落在实例日；anchor 日基行与
  ///   实例合一，不重复渲染）；
  /// - [date]=null → 收集箱：date IS NULL 基行直出、不展开（无展开起点，
  ///   §5.5⑩），done=done_at 非空（行级语义）。
  ///
  /// 排序沿用 TodoDao 口径：未完成在前、创建序、hlc 兜底全序（重复基行的
  /// done_at 反映最近勾选实例，跨日排序偶有偏差，v1 接受——见类注释取舍）。
  Stream<List<TodoDayInstance>> watchTodoDayInstances(String? date) {
    return _watchVisibleTodos().map((rows) {
      final day = date;
      final instances = <TodoDayInstance>[];
      for (final row in rows) {
        final rule = parseRrule(row.repeatRule);
        if (day == null) {
          // 收集箱：date IS NULL 基行直出（§5.5⑩）。
          if (row.date != null) continue;
          instances.add(TodoDayInstance(
            todo: row,
            date: null,
            done: row.doneAt != null,
            recurring: rule != null,
            repeatLabel: rule == null
                ? null
                : (TodoRepeatSpec.fromRrule(row.repeatRule)?.label),
          ));
          continue;
        }
        if (rule != null) {
          // 重复待办：按锚点展开命中当日（锚点缺省回退基行 date；
          // 两者皆空 → 无展开起点，不出现）。
          final anchor = row.rruleAnchorDate ?? row.date;
          if (anchor == null ||
              !rruleOccursOn(anchorDay: anchor, rule: rule, day: day)) {
            continue;
          }
          instances.add(TodoDayInstance(
            todo: row,
            date: day,
            done: row.doneAt != null &&
                dom.formatCalendarDay(
                      DateTime.fromMillisecondsSinceEpoch(row.doneAt!),
                    ) ==
                    day,
            recurring: true,
            repeatLabel: TodoRepeatSpec.fromRrule(row.repeatRule)?.label,
          ));
          continue;
        }
        // 非重复：date=当日直出。
        if (row.date != day) continue;
        instances.add(TodoDayInstance(
          todo: row,
          date: day,
          done: row.doneAt != null,
          recurring: false,
        ));
      }
      return instances;
    });
  }

  /// 全部未删待办（重复展开的读源；排序与 TodoDao.watchByDate 同口径）。
  Stream<List<cdb.Todo>> _watchVisibleTodos() {
    return (db.select(db.todos)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm
                .desc(const CustomExpression<bool>('done_at IS NULL')),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.hlc),
          ]))
        .watch();
  }

  // ── 存钱目标（§3.6 留存钩子、§5.5⑪⑫、§11.2 W13 主线）──────────────
  //
  // 账本联动取舍（§12.2 开放问题 #9，W13 拍板维持 V1 倾向）：存钱贡献是
  // 纯 append-only 记录（§5.5⑫），**不**生成 entries/entry_lines 转账流水
  // （不双重记账）；与账本联动待观察需求后另行拍板——本节所有写路径均不触
  // 账本/事件表（待拍板项，此处注释为唯一声明点）。

  /// 新建存钱目标（§5.5⑪；§3.6 新建目标：365 天挑战/52 周挑战/自定义）。
  ///
  /// [draft] 携带结构化形态：挑战目标金额与 rhythm 由格子数推导（见
  /// SavingsGoalDraft 文档），自定义取显式金额；起始日缺省=设备本地今日
  /// （365/52 周存钱法「第 1 格」锚点）。写路径经 SavingsGoalsDao：outbox
  /// 同事务入队 + day_summary.savings_progress 同事务重算（§5.6⑬/§6.2）。
  Future<cdb.SavingsGoal> createSavingsGoal(SavingsGoalDraft draft) async {
    final goal = await savingsGoals.create(
      name: draft.name,
      targetMinor: draft.effectiveTargetMinor,
      method: draft.method,
      rhythm: draft.rhythmJson(),
      deadline: draft.deadline,
      startedOn: draft.startedOn,
    );
    // W13 漏斗（§11.2 W13 任务 4）：建档即记——props 只有枚举标签（§3.9
    // 金额与名称禁入遥测）。原壳层 SavingsService 的埋点随写路径收敛迁移。
    if (telemetry != null) {
      await telemetry!.funnel(
        dom.TelemetryFunnel.savingsGoalCreated,
        props: <String, Object?>{'method': draft.method},
      );
    }
    return goal;
  }

  /// 投币打卡（§3.6「投币式打卡」、§5.5⑫ append-only）。
  ///
  /// 幂等（防重复）：同 (goal_id, date, source='manual') 已有存活行 →
  /// no-op 返回既有行（SavingsContributionsDao.append 幂等键，§5.5⑫ v1 补
  /// 列 source）；UI 状态置灰只是提示，真正防重复在 DAO 幂等键。
  ///
  /// [amountMinor] 缺省时按存钱法推当日格子（[savingsLadderStep]）：365 天
  /// 挑战第 N 天投 N×基数、52 周挑战第 N 周投 N×基数、自定义投每日固定额；
  /// [slot] 缺省同推。目标未开跑（day < started_on）抛 StateError。
  Future<cdb.SavingsContribution> contributeToGoal({
    required String goalId,
    required String date,
    int? amountMinor,
    int? slot,
    String? note,
  }) async {
    final goal = await savingsGoals.findById(goalId);
    if (goal == null) {
      throw StateError('contributeToGoal: savings_goals 无此行 $goalId');
    }
    // W13 漏斗（§11.2 W13 任务 4）：coin_in 只记真实新增——幂等命中
    // （同日同来源已有存活行）不重复计「存进去」，漏斗不失真（§5.5⑫）。
    final existing = await savingsContributions.findEffective(
      goalId: goalId,
      date: date,
    );
    final int amount;
    final int? effectiveSlot;
    if (amountMinor != null) {
      amount = amountMinor;
      effectiveSlot = slot;
    } else {
      final step = savingsLadderStep(goal: goal, day: date);
      if (step == null) {
        throw StateError(
          'contributeToGoal: 目标 $goalId 当日（$date）无格子可投'
          '（未开跑或 rhythm 不可推算，§3.6）',
        );
      }
      amount = step.amountMinor;
      effectiveSlot = step.slot;
    }
    final contribution = await savingsContributions.append(
      goalId: goalId,
      amountMinor: amount,
      date: date,
      slot: effectiveSlot,
      note: note,
    );
    if (telemetry != null && existing == null) {
      await telemetry!.funnel(
        dom.TelemetryFunnel.coinIn,
        props: <String, Object?>{
          'method': goal.method,
          if (effectiveSlot != null) 'slot': effectiveSlot,
        },
      );
    }
    return contribution;
  }

  /// 目标 + 本地聚合进度流（§5.5⑫「进度=Σ贡献行」）。
  ///
  /// W13 改为单条响应式联查（LEFT JOIN + GROUP BY，readsFrom 双表）：贡献
  /// 追加/目标变更任一发生即重发——W5-6 占位实现（asyncMap 逐目标求和、
  /// 无 readsFrom）在打卡写路径上线后不会刷新，此处一并修正。墓碑行与
  /// 墓碑目标均排除（§6.5）。
  Stream<List<SavingsGoalView>> watchSavingsGoalViews() {
    return db
        .customSelect(
          'SELECT g.id AS g_id, g.name AS g_name, '
          'g.target_minor AS g_target_minor, g.deadline AS g_deadline, '
          'g.method AS g_method, g.rhythm AS g_rhythm, '
          'g.status AS g_status, g.started_on AS g_started_on, '
          'g.created_at AS g_created_at, g.updated_at AS g_updated_at, '
          'g.hlc AS g_hlc, g.revision AS g_revision, '
          'g.schema_ver AS g_schema_ver, g.device_id AS g_device_id, '
          'COALESCE(SUM(c.amount_minor), 0) AS contributed_minor '
          'FROM savings_goals g '
          'LEFT JOIN savings_contributions c '
          'ON c.goal_id = g.id AND c.deleted_at IS NULL '
          'WHERE g.deleted_at IS NULL '
          'GROUP BY g.id '
          'ORDER BY g.created_at ASC, g.id ASC',
          readsFrom: {db.savingsGoals, db.savingsContributions},
        )
        .watch()
        .map((rows) => [
              for (final row in rows)
                SavingsGoalView(
                  goal: cdb.SavingsGoal(
                    id: row.read<String>('g_id'),
                    name: row.read<String>('g_name'),
                    targetMinor: row.read<int>('g_target_minor'),
                    deadline: row.readNullable<String>('g_deadline'),
                    method: row.read<String>('g_method'),
                    rhythm: row.read<String>('g_rhythm'),
                    status: row.read<String>('g_status'),
                    startedOn: row.read<String>('g_started_on'),
                    createdAt: row.read<int>('g_created_at'),
                    updatedAt: row.read<int>('g_updated_at'),
                    deletedAt: null,
                    hlc: row.read<String>('g_hlc'),
                    revision: row.read<int>('g_revision'),
                    schemaVer: row.read<int>('g_schema_ver'),
                    deviceId: row.read<String>('g_device_id'),
                  ),
                  contributedMinor: row.read<int>('contributed_minor'),
                ),
            ]);
  }

  /// 单目标流（详情页，§3.6 目标详情）。
  Stream<cdb.SavingsGoal?> watchGoalById(String id) {
    return (db.select(db.savingsGoals)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// 单目标进度求和流（§5.5⑫，core_db DAO 响应式直驱）。
  Stream<int> watchGoalProgress(String goalId) =>
      savingsContributions.watchSumByGoal(goalId);

  /// 目标当日人工投币行流（打卡按钮状态直驱：非空=今日已投币，§3.6 状态
  /// 防重复；source='manual' 与 DAO 幂等键三元组同口径）。
  Stream<cdb.SavingsContribution?> watchTodayManualContribution({
    required String goalId,
    required String date,
  }) {
    return (db.select(db.savingsContributions)
          ..where((t) =>
              t.goalId.equals(goalId) &
              t.date.equals(date) &
              t.source.equals(cdb.kSavingsSourceManual) &
              t.deletedAt.isNull())
          ..limit(1))
        .watchSingleOrNull();
  }

  /// 目标贡献历史流（append-only 时间线，§3.6 目标详情；含远端墓碑行供
  /// 「撤销」痕迹渲染，上层自行过滤）。
  Stream<List<cdb.SavingsContribution>> watchContributionsByGoal(
          String goalId) =>
      savingsContributions.watchByGoal(goalId);

  /// 目标当日格子推算（打卡按钮文案直驱；未开跑/不可推算返回 null）。
  ({int amountMinor, int? slot, String? label})? savingsStepForDay({
    required cdb.SavingsGoal goal,
    required String day,
  }) =>
      savingsLadderStep(goal: goal, day: day);

  /// 归档目标（软删墓碑，§5.1；投影 savings_progress 同事务联动，§5.6⑬）。
  Future<void> deleteSavingsGoal(String id) => savingsGoals.softDelete(id);

  /// 标记达成（§5.5⑪ status active→completed；达成判定=Σ贡献≥目标，由
  /// 上层（详情页按 watchGoalProgress）决策后写回，DAO 读路径零副作用）。
  Future<void> markGoalCompleted(String id) => savingsGoals.updateDetails(
        id: id,
        status: cdb.kSavingsGoalStatusCompleted,
      );

  // ── 健身计划（§3.5 健身计划 P1 留存钩子、§5.5⑧⑨、§11.2 W14 全量）────
  //
  // 写路径纪律（§6.2）：fitness_plans / fitness_sessions / exercise_sets 均为
  // §5.1 同步真值表，业务行与行快照**同事务**入队 sync_outbox（[outbox]）；
  // 汇总路径的 entries/entry_lines 复用仓库写（软删墓碑/投影联动契约，
  // §10.4），仓库写后在同事务内补行快照入队（仓库层不做 outbox，装配纪律）。
  //
  // 会话时序口径（§11.2 W14 任务 3）：**开练即建会话行**（start_at 真值、
  // duration/kcal 暂 0），每完成一组落 exercise_sets（父行先于子行，pull
  // 依赖序 §6.2；中途退出已完成组不丢）；「完成训练」在单事务内汇总——
  // duration=start_at 起算的真实墙钟时长、kcal 走既有 MET 逻辑（§3.5）、
  // entries(kind=fitness)+entry_lines(type=burn) 联动（复用 W5-6 链路）。

  /// 计划列表（未删；起始日倒序）。
  Stream<List<cdb.FitnessPlan>> watchFitnessPlans() {
    return (db.select(db.fitnessPlans)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .watch();
  }

  /// 单计划流（编辑预填/详情）。
  Stream<cdb.FitnessPlan?> watchPlanById(String id) {
    return (db.select(db.fitnessPlans)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// 单计划读取（一次性）。
  Future<cdb.FitnessPlan?> findPlanById(String id) {
    return (db.select(db.fitnessPlans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// 新建健身计划（§5.5⑧）：模板=名称+动作列表+按周排期掩码。
  ///
  /// - [exercises] 走 [FitnessPlanTemplate.encode] 落 exercises 列（§5.5⑧
  ///   「排期模板：动作/组数/重量配比/休息秒」，形状见 fitness_plan_models）；
  /// - [weekdayMask] bit0=周一…bit6=周日（§5.5⑧）；空掩码=纯模板（可开练、
  ///   不出现在任何排期日）；
  /// - [startDate] 缺省=设备本地今日（§5.5⑧ start_date）。
  Future<cdb.FitnessPlan> createFitnessPlan({
    required String name,
    required int weekdayMask,
    required List<PlanExercise> exercises,
    String? startDate,
    bool active = true,
  }) async {
    final stamp = _nextStamp();
    final rowId = _newId();
    final effectiveStartDate = startDate ??
        dom.formatCalendarDay(DateTime.fromMillisecondsSinceEpoch(_nowMs));
    await db.transaction(() async {
      await db.into(db.fitnessPlans).insert(cdb.FitnessPlan(
            id: rowId,
            name: name,
            weekdayMask: weekdayMask,
            exercises: FitnessPlanTemplate(exercises: exercises).encode(),
            startDate: effectiveStartDate,
            active: active,
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            deletedAt: null,
            hlc: stamp.hlc,
            revision: 1,
            schemaVer: dom.kCurrentSchemaVer,
            deviceId: clock.deviceId,
          ));
      // §6.2 写路径纪律：行快照同事务入队（§5.6⑯）。
      await outbox.enqueueRow('fitness_plans', rowId);
    });
    return (await findPlanById(rowId))!;
  }

  /// 更新计划字段（名称/排期掩码/模板/启用/起始日）。
  ///
  /// 各可变参数缺省传「不改动」哨兵（本类沿用 TodoDao.updateDetails 的
  /// Object 哨兵口径）；[exercises] 传 `List<PlanExercise>`（内部编码落列）。
  Future<void> updateFitnessPlanDetails({
    required String id,
    Object? name = _unchanged,
    Object? weekdayMask = _unchanged,
    Object? exercises = _unchanged,
    Object? active = _unchanged,
    Object? startDate = _unchanged,
  }) async {
    final List<PlanExercise>? exerciseList =
        exercises == _unchanged ? null : exercises as List<PlanExercise>?;
    await db.transaction(() async {
      final row = await (db.select(db.fitnessPlans)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('updateFitnessPlanDetails: 无此计划 $id（§5.5⑧）');
      }
      final stamp = _nextStamp();
      await (db.update(db.fitnessPlans)..where((t) => t.id.equals(id))).write(
        cdb.FitnessPlansCompanion(
          name: name == _unchanged
              ? const Value.absent()
              : Value(name as String),
          weekdayMask: weekdayMask == _unchanged
              ? const Value.absent()
              : Value(weekdayMask as int),
          exercises: exerciseList == null
              ? const Value.absent()
              : Value(FitnessPlanTemplate(exercises: exerciseList).encode()),
          active:
              active == _unchanged ? const Value.absent() : Value(active as bool),
          startDate: startDate == _unchanged
              ? const Value.absent()
              : Value(startDate as String),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2：主干变更同事务入队（§5.6⑯）。
      await outbox.enqueueRow('fitness_plans', id);
    });
  }

  /// 删除计划（软删墓碑，§5.1/§6.5 墓碑拒绝复活）。既有会话行不受影响
  /// （fitness_sessions.plan_day_id 为逻辑前向引用，§5.5⑦）。
  Future<void> deleteFitnessPlan(String id) async {
    await db.transaction(() async {
      final row = await (db.select(db.fitnessPlans)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return; // 幂等 no-op
      final hlc = clock.now();
      if (row.deletedAt == null) {
        await (db.update(db.fitnessPlans)..where((t) => t.id.equals(id)))
            .write(cdb.FitnessPlansCompanion(
          deletedAt: Value(hlc.physicalMs),
          updatedAt: Value(hlc.physicalMs),
          hlc: Value(hlc.format()),
          revision: Value(row.revision + 1),
        ));
        // §6.2：墓碑快照入队（读侧自动以 delete 语义出网，§5.6⑯）。
        await outbox.enqueueRow('fitness_plans', id);
      }
    });
  }

  /// 开练（§11.2 W14 任务 2「从排期或模板发起当日训练」）：**建会话行**
  /// （§5.5⑦ type=template_instance、source=plan、start_at=开练时刻）。
  ///
  /// - [date] 归属日（本地日历日，§5.1）；[tzOffsetMin] 缺省取当前时区偏移；
  /// - plan_day_id 落 plan id：v1 无独立排期日表（§5.5⑦ planDayId 注记），
  ///   排期日语义 =（plan_day_id, date）二元组，掩码宿主即计划行；
  /// - duration_s/kcal_burn 落 0，训练结束由 [finishWorkoutSession] 汇总
  ///   （§11.2 W14 任务 3）；会话行先于组明细存在，pull 依赖序父→子（§6.2）。
  Future<cdb.FitnessSession> startWorkoutSession({
    required String planId,
    required String date,
    int? tzOffsetMin,
  }) async {
    final now = DateTime.fromMillisecondsSinceEpoch(_nowMs);
    final effectiveTz = tzOffsetMin ?? now.timeZoneOffset.inMinutes;
    return db.transaction(() async {
      final plan = await (db.select(db.fitnessPlans)
            ..where((t) => t.id.equals(planId)))
          .getSingleOrNull();
      if (plan == null || plan.deletedAt != null) {
        throw StateError('startWorkoutSession: 无此计划 $planId（§5.5⑧）');
      }
      final stamp = _nextStamp();
      final rowId = _newId();
      await db.into(db.fitnessSessions).insert(cdb.FitnessSession(
            id: rowId,
            date: date,
            tzOffsetMin: effectiveTz,
            startAt: stamp.updatedAtMs, // 开练时刻（§5.5⑦ start_at 真值）
            durationS: 0, // 完成训练时汇总（§11.2 W14 任务 3）
            type: kFitnessSessionTypeTemplateInstance,
            kcalBurn: 0,
            entryId: null, // 完成训练时联动 entry+burn 行（§5.5⑦）
            source: kFitnessSessionSourcePlan,
            planDayId: planId,
            note: null,
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            deletedAt: null,
            hlc: stamp.hlc,
            revision: 1,
            schemaVer: dom.kCurrentSchemaVer,
            deviceId: clock.deviceId,
          ));
      // §6.2：会话行快照同事务入队（§5.6⑯）。
      await outbox.enqueueRow('fitness_sessions', rowId);
      return (db.select(db.fitnessSessions)..where((t) => t.id.equals(rowId)))
          .getSingle();
    });
  }

  /// 完成一组（§11.2 W14 任务 3「每完成一组落 exercise_sets 行」）：落
  /// session_id/动作/组序/次数/重量/休息秒 + done_at 完成时刻——**完成标记=
  /// done_at 非空**（§5.5⑨ 冻结列口径：W14 只在完成时落行，append-only，
  /// §6.1 原则 2），行快照同事务入队。
  ///
  /// [sort] 缺省=该会话已有存活组数+1（会话内全局组序，§5.5⑨ sort）。
  Future<cdb.ExerciseSet> logExerciseSet({
    required String sessionId,
    required String exerciseRef,
    required int reps,
    required int weightKgX10,
    int? restS,
    double? rpe,
    int? sort,
  }) {
    assert(reps >= 1, '次数必须 ≥1（§5.5⑨ reps）');
    assert(weightKgX10 >= 0, '重量必须非负（§5.5⑨ 定点 ×10）');
    return db.transaction(() async {
      final session = await (db.select(db.fitnessSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null || session.deletedAt != null) {
        throw StateError('logExerciseSet: 无此会话 $sessionId（§5.5⑦）');
      }
      final existing = await (db.select(db.exerciseSets)
            ..where((t) =>
                t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
          .get();
      final stamp = _nextStamp();
      final rowId = _newId();
      await db.into(db.exerciseSets).insert(cdb.ExerciseSet(
            id: rowId,
            sessionId: sessionId,
            exerciseRef: exerciseRef,
            weightKgX10: weightKgX10,
            reps: reps,
            rpe: rpe,
            restS: restS,
            doneAt: stamp.updatedAtMs, // 完成标记（§5.5⑨ done_at）
            sort: sort ?? existing.length + 1,
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            deletedAt: null,
            hlc: stamp.hlc,
            revision: 1,
            schemaVer: dom.kCurrentSchemaVer,
            deviceId: clock.deviceId,
          ));
      // §6.2：组明细快照同事务入队（§5.6⑯）。
      await outbox.enqueueRow('exercise_sets', rowId);
      return (db.select(db.exerciseSets)..where((t) => t.id.equals(rowId)))
          .getSingle();
    });
  }

  /// 完成训练（§11.2 W14 任务 3「训练结束汇总」）：单事务内——
  /// 1. duration_s = start_at 起算的真实墙钟时长（秒）；
  /// 2. kcal_burn 走既有 MET 逻辑（§3.5 公式、[kFitnessPlanMetActivityId]
  ///    中档 MET；时长 0 → 0 kcal，不走估算）；
  /// 3. entries(kind=fitness)+entry_lines(type=burn,out) 同事务联动（复用
  ///    W5-6 链路 [entries]/[entryLines]，投影当日 kcal_out 即时重算 §5.6），
  ///    burn 行 payload 记 session_id/plan_id/MET 参数（§5.2②）；
  /// 4. 会话行回填 duration/kcal/entry_id，行快照入队。
  ///
  /// 幂等：entry_id 已非空（已汇总）→ 直接返回既有行（双击/重复 finish 不
  /// 重复产出行）；无组明细抛 StateError（空会话由退出清理路径软删，§11.2
  /// W14 UI 口径）。
  Future<cdb.FitnessSession> finishWorkoutSession({
    required String sessionId,
    required double weightKg,
    String? note,
  }) async {
    if (weightKg <= 0) {
      throw ArgumentError.value(weightKg, 'weightKg',
          '体重必须为正（MET 估算输入，§3.5 身体档案）');
    }
    final kcalLedger = await _ensureKcalLedger();
    final metActivity =
        findFitnessActivity(kFitnessPlanMetActivityId) ??
            kFitnessActivities.first;
    return db.transaction(() async {
      final session = await (db.select(db.fitnessSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null || session.deletedAt != null) {
        throw StateError('finishWorkoutSession: 无此会话 $sessionId（§5.5⑦）');
      }
      if (session.entryId != null) {
        return session; // 幂等：已汇总（§6.1 不重复产出事实行）
      }
      final sets = await (db.select(db.exerciseSets)
            ..where(
                (t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
          .get();
      if (sets.isEmpty) {
        throw StateError(
          'finishWorkoutSession: 会话 $sessionId 无组明细（§11.2 W14：'
          '空会话不入账，退出路径清理）',
        );
      }
      final plan = session.planDayId == null
          ? null
          : await (db.select(db.fitnessPlans)
                ..where((t) => t.id.equals(session.planDayId!)))
              .getSingleOrNull();
      // 时长（§5.5⑦ duration_s）：start_at 起算真实墙钟秒（开练即建行的代价
      // 与收益一致——含组间休息的真实训练时长）。
      final durationS = session.startAt == null
          ? 0
          : (_nowMs - session.startAt!) ~/ 1000;
      // MET 估算（§3.5 既有逻辑复用；时长 0 跳过估算——estimateKcalBurn
      // 对非正时长抛 ArgumentError，防御口径）。
      final kcal = durationS <= 0
          ? 0
          : estimateKcalBurn(
              activity: metActivity,
              intensity: FitnessIntensity.mid,
              durationS: durationS,
              weightKg: weightKg,
            );
      final minutes = durationS ~/ 60;
      final entryId = _newId();
      final entryMeta = _newMeta();
      final title = '${plan?.name ?? metActivity.name} $minutes 分钟';
      final payload = jsonEncode(<String, Object?>{
        'session_id': sessionId,
        'plan_id': session.planDayId,
        'plan_name': plan?.name,
        'activity_id': metActivity.id,
        'met': metActivity.metFor(FitnessIntensity.mid),
        'weight_kg': weightKg,
        'duration_s': durationS,
        'sets': sets.length,
      }..removeWhere((k, v) => v == null));

      // ① 事件主干（§5.2① kind=fitness；source=manual——entries.source 枚举
      //    §5.2① 无 plan 档，计划语义由 fitness_sessions.source 承担）。
      await entries.upsert(dom.Entry(
        id: entryId,
        date: session.date,
        tzOffsetMin: session.tzOffsetMin,
        occurredAt: _nowMs,
        kind: dom.EntryKind.fitness,
        source: dom.EntrySource.manual,
        title: title,
        note: note ?? session.note,
        status: dom.EntryStatus.confirmed,
        aiParseId: null,
        meta: entryMeta,
      ));
      // ② burn 产出行（§5.2② type=burn/out；人工行无置信度；投影重算在
      //    仓库事务内完成，外层事务 join，§5.6）。
      final lineId = _newId();
      await entryLines.upsert(dom.EntryLine(
        id: lineId,
        entryId: entryId,
        type: dom.LineType.burn,
        amount: kcal,
        direction: dom.LineDirection.outcome,
        ledgerId: kcalLedger.id,
        categoryId: null,
        currency: null,
        confidence: null,
        payload: payload,
        correctionOf: null,
        status: dom.LineStatus.active,
        meta: _newMeta(),
      ));
      // ③ 会话行回填汇总值（§5.5⑦）。
      final stamp = _nextStamp();
      await (db.update(db.fitnessSessions)
            ..where((t) => t.id.equals(sessionId)))
          .write(cdb.FitnessSessionsCompanion(
        durationS: Value(durationS),
        kcalBurn: Value(kcal),
        entryId: Value(entryId),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(stamp.updatedAtMs),
        hlc: Value(stamp.hlc),
        revision: Value(session.revision + 1),
      ));
      // ④ §6.2 出网：会话/事件/burn 行快照同事务入队（仓库层不做 outbox，
      //    装配纪律——见本节头注记）。
      await outbox.enqueueRow('fitness_sessions', sessionId);
      await outbox.enqueueRow('entries', entryId);
      await outbox.enqueueRow('entry_lines', lineId);
      return (db.select(db.fitnessSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingle();
    });
  }

  /// 会话行读取（一次性；开练页控制器装载）。
  Future<cdb.FitnessSession?> findSessionById(String sessionId) {
    return (db.select(db.fitnessSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
  }

  /// 会话组明细（一次性，组序升序；开练控制器断点续练恢复游标）。
  Future<List<cdb.ExerciseSet>> setsForSession(String sessionId) {
    return (db.select(db.exerciseSets)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
  }

  /// 会话组明细流（§10.1 reactive：开练页「已落组明细」直驱）。
  Stream<List<cdb.ExerciseSet>> watchSetsBySession(String sessionId) {
    return (db.select(db.exerciseSets)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .watch();
  }

  /// 全部会话流（未删；W14 训练历史页数据源，按日/按计划分组由页面承担）。
  /// 手动记录（W5-6）与计划实例（W14）共用 fitness_sessions 行模型（§5.5⑦）。
  Stream<List<cdb.FitnessSession>> watchAllSessions() {
    return (db.select(db.fitnessSessions)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.startAt),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  /// 会话 → 存活组数映射流（§5.5⑨ GROUP BY 单查询；历史页组数徽标，
  /// 避免逐会话订阅）。
  Stream<Map<String, int>> watchSetCountsBySession() {
    return db
        .customSelect(
          'SELECT session_id, COUNT(*) AS cnt FROM exercise_sets '
          'WHERE deleted_at IS NULL GROUP BY session_id',
          readsFrom: {db.exerciseSets},
        )
        .watch()
        .map((rows) => {
              for (final row in rows)
                row.read<String>('session_id'): row.read<int>('cnt'),
            });
  }

  /// 本地写入戳（§5.1 公共列 + §6.3 HLC；网关侧统一入口——W14 起
  /// fitness_plans/exercise_sets 等直写路径经此发戳，与会话行同口径）。
  ({String hlc, int updatedAtMs}) _nextStamp() {
    final hlc = clock.now();
    return (hlc: hlc.format(), updatedAtMs: hlc.physicalMs);
  }

  /// 「不改动」哨兵（透传 TodoDao.updateDetails 口径）。
  static const Object _unchanged = Object();
}
