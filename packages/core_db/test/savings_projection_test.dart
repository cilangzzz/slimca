/// day_summary.savings_progress 投影对账测试（§5.6⑬ W13 实装、§11.2 W13）。
///
/// 策略（与 day_summary_projection_test 同口径）：直写真值行（绕过 DAO——
/// 投影必须对任意落库形态成立，含 W7 起同步 pull 直写），经
/// recomputeDaySummary / recomputeAll / recomputeDirtyDays 落投影后，与
/// 手写 oracle 逐项比对。另覆盖 parseSavingsProgress 解包（坏形状防御）。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// 测试日期集（§5.1 date=本地日历日 TEXT yyyy-MM-dd）。
const String kSnapshotDay = '2026-12-05';

void main() {
  /// 直写一条目标行（§5.5⑪；绕过 DAO，覆盖同步 pull 直写形态）。
  Future<void> insertGoal(
    AppDatabase db, {
    required String id,
    required int targetMinor,
    required String startedOn,
    String? deadline,
    String status = kSavingsGoalStatusActive,
    int? deletedAt,
  }) async {
    await db.into(db.savingsGoals).insert(
          SavingsGoalsCompanion.insert(
            id: id,
            name: '目标-$id',
            targetMinor: targetMinor,
            deadline: Value(deadline),
            method: kSavingsMethodCustom,
            rhythm: '{}',
            status: status,
            startedOn: startedOn,
            createdAt: 1763251200000,
            updatedAt: 1763251200000,
            hlc: '0001763251200000:000001:3F8A12C0B7D4',
            revision: 1,
            deviceId: '3F8A12C0B7D4',
            deletedAt: Value(deletedAt),
          ),
        );
  }

  /// 直写一条贡献行（§5.5⑫；append-only，墓碑仅经 pull 形态注入）。
  Future<void> insertContribution(
    AppDatabase db, {
    required String id,
    required String goalId,
    required String date,
    required int amountMinor,
    int? deletedAt,
  }) async {
    await db.into(db.savingsContributions).insert(
          SavingsContributionsCompanion.insert(
            id: id,
            goalId: goalId,
            date: date,
            amountMinor: amountMinor,
            slot: const Value(null),
            note: const Value(null),
            source: const Value(kSavingsSourceManual),
            createdAt: 1763251200000,
            updatedAt: 1763251200000,
            hlc: '0001763251200000:000002:3F8A12C0B7D4',
            revision: 1,
            deviceId: '3F8A12C0B7D4',
            deletedAt: Value(deletedAt),
          ),
        );
  }

  /// oracle：手写 SQL 直查（与投影实现不同构，互为印证）。
  Future<Map<String, ({int contributedMinor, int targetMinor})>>
      savingsOracle(AppDatabase db, String date) async {
    final goalRows = await db
        .customSelect(
          "SELECT id, target_minor FROM savings_goals "
          "WHERE status = 'active' AND deleted_at IS NULL "
          'AND started_on <= ? AND (deadline IS NULL OR deadline >= ?)',
          variables: [Variable.withString(date), Variable.withString(date)],
        )
        .get();
    final result = <String, ({int contributedMinor, int targetMinor})>{};
    for (final goal in goalRows) {
      final goalId = goal.read<String>('id');
      final sumRow = await db
          .customSelect(
            'SELECT COALESCE(SUM(amount_minor), 0) AS total '
            'FROM savings_contributions '
            'WHERE goal_id = ? AND deleted_at IS NULL AND date <= ?',
            variables: [
              Variable.withString(goalId),
              Variable.withString(date),
            ],
          )
          .getSingle();
      result[goalId] = (
        contributedMinor: sumRow.read<int>('total'),
        targetMinor: goal.read<int>('target_minor'),
      );
    }
    return result;
  }

  test('有效性矩阵 + 累计口径：多目标快照逐项对账（oracle 互证）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，存钱投影对账测试未执行');
      return;
    }
    try {
      final projection = DaySummaryProjection(db);

      // 有效目标集合（快照日 2026-12-05）各维度矩阵：
      await insertGoal(db,
          id: 'gA',
          targetMinor: 5000,
          startedOn: '2026-12-01',
          deadline: '2026-12-31'); // A：打卡中（窗口内）→ 进快照
      await insertGoal(db,
          id: 'gB', targetMinor: 4000, startedOn: '2026-12-10'); // B：未开始
      await insertGoal(db,
          id: 'gC',
          targetMinor: 3000,
          startedOn: '2026-11-01',
          deadline: '2026-11-30'); // C：已过截止
      await insertGoal(db,
          id: 'gD',
          targetMinor: 2000,
          startedOn: '2026-11-01',
          status: kSavingsGoalStatusCompleted); // D：已完成
      await insertGoal(db,
          id: 'gE',
          targetMinor: 1000,
          startedOn: '2026-11-01',
          deletedAt: 1764000000000); // E：墓碑（已归档）
      await insertGoal(db,
          id: 'gF', targetMinor: 8000, startedOn: '2026-11-01'); // F：无截止

      await insertContribution(db,
          id: 'cA1', goalId: 'gA', date: '2026-12-01', amountMinor: 1000);
      await insertContribution(db,
          id: 'cA2', goalId: 'gA', date: '2026-12-05', amountMinor: 500);
      await insertContribution(db,
          id: 'cA3', goalId: 'gA', date: '2026-12-06', amountMinor: 999);
      await insertContribution(db,
          id: 'cF1', goalId: 'gF', date: '2026-12-03', amountMinor: 700);
      await insertContribution(db,
          id: 'cF2', goalId: 'gF', date: '2026-12-04', amountMinor: 800,
          deletedAt: 1764000000000);

      final summary =
          await projection.recomputeDaySummary(kSnapshotDay);
      final expected = await savingsOracle(db, kSnapshotDay);
      final parsed = parseSavingsProgress(summary.savingsProgress!);

      expect(parsed.keys.toSet(), {'gA', 'gF'},
          reason: '有效性矩阵：仅打卡中且窗口内的目标进快照');
      expect(parsed, expected, reason: '快照与手写 oracle 逐项一致');
      expect(parsed['gA']!.contributedMinor, 1500,
          reason: '累计口径 date<=快照日：12-06 的 999 不计入');
      expect(parsed['gF']!.contributedMinor, 700,
          reason: '墓碑贡献 800 不计入（§5.1 删除行）');

      // 边界日：started_on=快照日、deadline=快照日均有效（闭区间）。
      await insertGoal(db,
          id: 'gH',
          targetMinor: 6000,
          startedOn: kSnapshotDay,
          deadline: kSnapshotDay);
      final boundary = parseSavingsProgress(
          (await projection.recomputeDaySummary(kSnapshotDay))
              .savingsProgress!);
      expect(boundary.containsKey('gH'), isTrue,
          reason: 'started_on/deadline 边界为闭区间');
      expect(boundary['gH']!.contributedMinor, 0);

      // 更早日（2026-11-20）：C/F 已生效但贡献全部晚于快照日 → contributed 0；
      // A 未开始、B 未开始、D 非打卡中、E 墓碑。
      final early = parseSavingsProgress(
          (await projection.recomputeDaySummary('2026-11-20'))
              .savingsProgress!);
      expect(early.keys.toSet(), {'gC', 'gF'},
          reason: '11-20：仅 C（截止未到）与 F（无截止）有效');
      expect(early['gC']!.contributedMinor, 0);
      expect(early['gF']!.contributedMinor, 0);

      // recomputeAll（§5.6 全量自愈）与单日重算结果一致。
      await projection.recomputeAll();
      final afterAll = parseSavingsProgress(
          (await (db.select(db.daySummaries)
                    ..where((t) => t.date.equals(kSnapshotDay)))
                .getSingle())
              .savingsProgress!);
      expect(afterAll['gA'], (contributedMinor: 1500, targetMinor: 5000));
      expect(afterAll.containsKey('gH'), isTrue);
    } finally {
      await db.close();
    }
  });

  test('清零与自愈：外部直改贡献/归档目标 → markSavingsProgressDirty → '
      'recomputeDirtyDays 吸收；无有效目标清 NULL', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，存钱投影自愈测试未执行');
      return;
    }
    try {
      final projection = DaySummaryProjection(db);
      await insertGoal(db,
          id: 'gZ', targetMinor: 10000, startedOn: '2026-12-01');
      await insertContribution(db,
          id: 'cZ1', goalId: 'gZ', date: '2026-12-02', amountMinor: 3000);

      var summary =
          await projection.recomputeDaySummary(kSnapshotDay);
      expect(
        parseSavingsProgress(summary.savingsProgress!)['gZ']!.contributedMinor,
        3000,
      );

      // 外部直改贡献金额（模拟 W7 起同步 pull 直写）→ 标 dirty → 后台重算。
      await (db.update(db.savingsContributions)
            ..where((t) => t.id.equals('cZ1')))
          .write(const SavingsContributionsCompanion(amountMinor: Value(4500)));
      await projection.markSavingsProgressDirty(fromDate: '2026-12-02');
      final dirtyRow = await (db.select(db.daySummaries)
            ..where((t) => t.date.equals(kSnapshotDay)))
          .getSingle();
      expect(dirtyRow.dirty, isTrue, reason: '§5.6 重建规则：进度行标 dirty');
      expect(
        parseSavingsProgress(dirtyRow.savingsProgress!)['gZ']!
            .contributedMinor,
        3000,
        reason: 'dirty 行保持旧值等待重算',
      );
      await projection.recomputeDirtyDays();
      final healed = await (db.select(db.daySummaries)
            ..where((t) => t.date.equals(kSnapshotDay)))
          .getSingle();
      expect(
        parseSavingsProgress(healed.savingsProgress!)['gZ']!.contributedMinor,
        4500,
        reason: '自愈吸收外部变更',
      );
      expect(healed.dirty, isFalse, reason: '重算完成 dirty 复位');

      // markSavingsProgressDirty 不带日期：全部进度行标 dirty。
      await projection.markSavingsProgressDirty();
      final allDirty = await db
          .customSelect(
              'SELECT COUNT(*) AS c FROM day_summaries WHERE dirty = 1')
          .getSingle();
      expect(allDirty.read<int>('c'), greaterThanOrEqualTo(1));

      // 目标归档（直写墓碑，模拟 pull）→ 重算清零：无有效目标 → NULL。
      await (db.update(db.savingsGoals)..where((t) => t.id.equals('gZ')))
          .write(const SavingsGoalsCompanion(deletedAt: Value(1765000000000)));
      final zeroed =
          await projection.recomputeDaySummary(kSnapshotDay);
      expect(zeroed.savingsProgress, isNull,
          reason: '无当日有效目标 → 快照 NULL（§5.6⑬ 空态，W1-W12 行为即此）');
      expect(zeroed.dirty, isFalse);
    } finally {
      await db.close();
    }
  });

  test('parseSavingsProgress：合法快照解包、坏 JSON/坏形状防御性返回空', () async {
    expect(
      parseSavingsProgress(
          '{"g1":{"contributed_minor":1500,"target_minor":5000}}'),
      {'g1': (contributedMinor: 1500, targetMinor: 5000)},
    );
    expect(parseSavingsProgress('{}'), isEmpty);

    // 多目标。
    final multi = parseSavingsProgress(
        '{"a":{"contributed_minor":1,"target_minor":2},'
        '"b":{"contributed_minor":3,"target_minor":4}}');
    expect(multi.keys.toSet(), {'a', 'b'});
    expect(multi['b']!.contributedMinor, 3);

    // 坏形状：非对象 JSON、坏 JSON、条目缺键/类型不符逐条跳过。
    expect(parseSavingsProgress('[1,2]'), isEmpty, reason: '非对象形状');
    expect(parseSavingsProgress('not-json'), isEmpty, reason: '坏 JSON 不抛错');
    expect(
      parseSavingsProgress(
          '{"bad1":{"contributed_minor":"x","target_minor":2},'
          '"bad2":{"target_minor":2},'
          '"bad3":5,'
          '"good":{"contributed_minor":7,"target_minor":9}}'),
      {'good': (contributedMinor: 7, targetMinor: 9)},
      reason: '坏条目跳过、好条目保留（快照可整行重建自愈，§5.6）',
    );
  });
}
