/// 计划域网关：健身手动记录落库编排 + 待办/存钱/计划读侧（§3.5、§3.6、
/// §5.5、§11.1 W5-6、§10.4 分层）。
///
/// 分层边界（§10.4「接口在 core_domain、实现在 core_db」）：持久化语义全部
/// 复用 core_db 既有件——
/// - 事件/产出行落库走 `DriftEntryRepository` / `DriftEntryLineRepository`
///   （软删墓碑、投影联动等仓库契约不在此重写）；
/// - 待办复用 `TodoDao`（含 done_at 只前进合并、收集箱语义、投影联动）；
///   注：TodoDao 内部自持 `LocalWriteClock` 发戳（core_db 既有接缝），与本
///   网关注入的 `dom.HlcClock` 是两个实例——同毫秒 counter 不共享，属
///   core_db 现状，W5-6 按现状复用不做改造；
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
import 'plan_models.dart';

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
/// [projection] 缺省时自动建 [cdb.DaySummaryProjection]——W5-6 所有写路径
/// （会话三行、待办勾选）都必须联动重算投影（§5.6 重建规则），故网关内
/// 投影恒非空。
PlanGateway createPlanGateway({
  required cdb.AppDatabase db,
  required dom.HlcClock clock,
  cdb.DaySummaryProjection? projection,
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
  );
}

/// 计划域网关：健身会话写编排 + 待办/存钱/健身计划读写（§11.1 W5-6）。
class PlanGateway {
  PlanGateway._({
    required cdb.AppDatabase database,
    required this.clock,
    required this.projection,
    required this.entries,
    required this.entryLines,
    required this.todos,
  }) : db = database;

  final cdb.AppDatabase db;

  /// 应用级单例时钟（§6.3）：本网关签发的所有行 HLC 皆源于此。
  final dom.HlcClock clock;

  /// day_summary 投影（§5.6⑬）：恒非空，写后联动重算。
  final cdb.DaySummaryProjection projection;

  /// 事件主干仓库（core_db 实现，§10.4）。
  final cdb.DriftEntryRepository entries;

  /// 产出行仓库（core_db 实现）。
  final cdb.DriftEntryLineRepository entryLines;

  /// 待办 DAO（core_db 实现，done_at 只前进合并，§6.5）。
  final cdb.TodoDao todos;

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
        id: _newId(),
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

  // ── 待办（§3.6 待办基础 P0、§5.5⑩；复用 TodoDao，§10.4）──────────

  /// 新建待办：[date] null=收集箱（§5.5⑩ date NULL=收集箱）。
  Future<cdb.Todo> createTodo({
    required String title,
    String? date,
    String? note,
    int? dueAt,
  }) =>
      todos.create(title: title, date: date, note: note, dueAt: dueAt);

  /// 勾选/取消完成（done_at 只前进合并，§6.5；投影联动 todo_done）。
  Future<void> setTodoDone(String id, {required bool done}) =>
      todos.setDone(id, done: done);

  /// 删除待办（软删墓碑，§5.1）。
  Future<void> deleteTodo(String id) => todos.softDelete(id);

  /// 收集箱 → 今日：回填计划日（§3.6「一键安排到今天」）。
  Future<void> moveTodoToToday(String id, {required String date}) =>
      todos.updateDetails(id: id, date: date);

  /// 某日待办流（未完成在前）。
  Stream<List<cdb.Todo>> watchTodosByDate(String date) =>
      todos.watchByDate(date);

  /// 收集箱流（date IS NULL，排除墓碑）。
  Stream<List<cdb.Todo>> watchInboxTodos() => todos.watchInbox();

  // ── 存钱目标（§3.6 占位、§5.5⑪⑫；W13 全量功能）───────────────────

  /// 目标 + 本地聚合进度（进度=Σ contributions，append-only，§5.5⑫）。
  /// 空库发空列表——占位页据此渲染空态（§3.6「P1 表已建、W13 上线」）。
  Stream<List<SavingsGoalView>> watchSavingsGoalViews() {
    return (db.select(db.savingsGoals)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .asyncMap((goals) async {
      final views = <SavingsGoalView>[];
      for (final goal in goals) {
        final row = await db
            .customSelect(
              'SELECT COALESCE(SUM(amount_minor), 0) AS total '
              'FROM savings_contributions '
              'WHERE goal_id = ? AND deleted_at IS NULL',
              variables: [Variable.withString(goal.id)],
            )
            .getSingle();
        views.add(SavingsGoalView(
          goal: goal,
          contributedMinor: row.read<int>('total'),
        ));
      }
      return views;
    });
  }

  // ── 健身计划（§3.5 占位、§5.5⑧；W14 全量功能）────────────────────

  /// 计划列表（未删；起始日倒序）。W5-6 无写路径（W14 接入排期/模板），
  /// 占位页据此渲染空态。
  Stream<List<cdb.FitnessPlan>> watchFitnessPlans() {
    return (db.select(db.fitnessPlans)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .watch();
  }
}
