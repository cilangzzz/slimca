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
    savingsGoals:
        cdb.SavingsGoalsDao(db, projection: effectiveProjection),
    savingsContributions:
        cdb.SavingsContributionsDao(db, projection: effectiveProjection),
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
  }) =>
      todos.create(
        title: title,
        date: date,
        note: note,
        dueAt: dueAt,
        repeatRule: repeatRule,
        rruleAnchorDate: rruleAnchorDate,
        remindAt: remindAt,
      );

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
  }) =>
      todos.updateDetails(
        id: id,
        title: title,
        note: note,
        repeatRule: repeatRule,
        remindAt: remindAt,
        rruleAnchorDate:
            clearAnchor ? null : (anchorDate ?? _unchanged),
      );

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
  Future<cdb.SavingsGoal> createSavingsGoal(SavingsGoalDraft draft) {
    return savingsGoals.create(
      name: draft.name,
      targetMinor: draft.effectiveTargetMinor,
      method: draft.method,
      rhythm: draft.rhythmJson(),
      deadline: draft.deadline,
      startedOn: draft.startedOn,
    );
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
    return savingsContributions.append(
      goalId: goalId,
      amountMinor: amount,
      date: date,
      slot: effectiveSlot,
      note: note,
    );
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

  // ── 健身计划（§3.5 占位、§5.5⑧；W14 全量功能）────────────────────

  /// 计划列表（未删；起始日倒序）。W5-6 无写路径（W14 接入排期/模板），
  /// 占位页据此渲染空态。
  Stream<List<cdb.FitnessPlan>> watchFitnessPlans() {
    return (db.select(db.fitnessPlans)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startDate)]))
        .watch();
  }

  /// 「不改动」哨兵（透传 TodoDao.updateDetails 口径）。
  static const Object _unchanged = Object();
}
