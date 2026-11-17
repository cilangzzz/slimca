/// 报表聚合 oracle 对账测试（§3.4 统计报表、§11.2 W15「统计报表」主线）。
///
/// 策略（任务口径「随机数据 + 手写 SQL 比对」）：固定种子随机生成 2026 全年
/// 的 entry+entry_lines（多日/多分类/多账本，含 draft 事件、软删墓碑、
/// void 作废、superseded 修正链），经 recomputeAll 落投影后，将
/// DriftReportRepository 的桶序列/分类堆叠与「手写 SQL 直查聚合」逐桶
/// 逐字段比对——测试内 oracle 与仓库实现（UNION 合并）刻意不同构，互为印证。
///
/// 另覆盖数据层双口径（类文档「day_summary 直读 + entry_lines 聚合兜底」）：
/// - 直读分支：投影行在（recomputeAll 后）→ 序列取投影行；
/// - 兜底分支：DELETE 全部投影行 → 序列经 entry_lines 聚合仍与 oracle 一致；
/// - per-账本过滤（§11.2 W15）：oracle 加 ledger_id 谓词后逐桶一致。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过。
library;

import 'dart:math';

import 'package:core_db/core_db.dart' as cdb;
// as drift：oracle SQL 的 Variable 与墓碑覆写的 Value 用前缀形态。
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feature_ledger/feature_ledger.dart';

bool _isSqliteLibraryMissing(Object error) {
  final String msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

const String _device = '3F8A12C0B7D4';
int _clockMs = 1763251200000;
int _rowSeq = 0;

/// 下一个行 id（TEXT 主键；时间有序只是锦上添花，测试不依赖）。
String _nextId() {
  _rowSeq++;
  return '0196a7e0-0000-7000-8000-${_rowSeq.toRadixString(16).padLeft(12, '0')}';
}

Future<void> _insertEntry(
  cdb.AppDatabase db, {
  required String id,
  required String date,
  required String kind,
  required String status,
  bool deleted = false,
}) async {
  final int ms = _clockMs;
  _clockMs += 7;
  await db.into(db.entries).insert(
        cdb.Entry(
          id: id,
          date: date,
          tzOffsetMin: 480,
          occurredAt: ms,
          kind: kind,
          source: 'manual',
          title: '随机事件 $id',
          note: null,
          status: status,
          aiParseId: null,
          createdAt: ms,
          updatedAt: ms,
          deletedAt: deleted ? ms + 3 : null,
          hlc: '$ms:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
}

Future<void> _insertLine(
  cdb.AppDatabase db, {
  required String id,
  required String entryId,
  required String type,
  required int amount,
  required String direction,
  required String ledgerId,
  String? categoryId,
  String status = 'active',
  bool deleted = false,
  String? correctionOf,
}) async {
  final int ms = _clockMs;
  _clockMs += 7;
  await db.into(db.entryLines).insert(
        cdb.EntryLine(
          id: id,
          entryId: entryId,
          type: type,
          amount: amount,
          direction: direction,
          ledgerId: ledgerId,
          categoryId: categoryId,
          currency: type == 'money' ? 'CNY' : null,
          confidence: null,
          payload: null,
          correctionOf: correctionOf,
          status: status,
          createdAt: ms,
          updatedAt: ms,
          deletedAt: deleted ? ms + 3 : null,
          hlc: '$ms:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
}

/// 桶序列 oracle（手写 SQL，与仓库 UNION 实现不同构）：过滤口径与
/// core_db 投影 `_kDayAggregateSql` 一致（active 行、行/事件未删；draft
/// 计入——§5.6⑬ 聚合口径），按桶分组。
Future<Map<String, (int, int, int, int)>> _oracleBuckets(
  cdb.AppDatabase db, {
  required String start,
  required String endExclusive,
  required bool byMonth,
  String? ledgerId,
}) async {
  final String bucketExpr = byMonth ? 'substr(e.date, 1, 7)' : 'e.date';
  final String ledgerFilter =
      ledgerId == null ? '' : ' AND l.ledger_id = ?';
  final rows = await db
      .customSelect(
        'SELECT $bucketExpr AS bucket, '
        "COALESCE(SUM(CASE WHEN l.type = 'calorie' AND l.direction = 'in' THEN l.amount ELSE 0 END), 0) AS kcal_in, "
        "COALESCE(SUM(CASE WHEN l.type = 'burn' AND l.direction = 'out' THEN l.amount ELSE 0 END), 0) AS kcal_out, "
        "COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'out' THEN l.amount ELSE 0 END), 0) AS spend_minor, "
        "COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'in' THEN l.amount ELSE 0 END), 0) AS income_minor "
        'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
        'WHERE e.date >= ? AND e.date < ? '
        "AND l.status = 'active' AND l.deleted_at IS NULL "
        'AND e.deleted_at IS NULL$ledgerFilter '
        'GROUP BY bucket',
        variables: <drift.Variable<String>>[
          drift.Variable.withString(start),
          drift.Variable.withString(endExclusive),
          if (ledgerId != null) drift.Variable.withString(ledgerId),
        ],
      )
      .get();
  return <String, (int, int, int, int)>{
    for (final row in rows)
      row.read<String>('bucket'): (
        row.read<int>('kcal_in'),
        row.read<int>('kcal_out'),
        row.read<int>('spend_minor'),
        row.read<int>('income_minor'),
      ),
  };
}

/// 分类堆叠 oracle：桶×分类 money-out 求和。
Future<Map<String, Map<String?, int>>> _oracleStacks(
  cdb.AppDatabase db, {
  required String start,
  required String endExclusive,
  required bool byMonth,
  String? ledgerId,
}) async {
  final String bucketExpr = byMonth ? 'substr(e.date, 1, 7)' : 'e.date';
  final String ledgerFilter =
      ledgerId == null ? '' : ' AND l.ledger_id = ?';
  final rows = await db
      .customSelect(
        'SELECT $bucketExpr AS bucket, l.category_id AS category_id, '
        'COALESCE(SUM(l.amount), 0) AS spend_minor '
        'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
        "WHERE l.type = 'money' AND l.direction = 'out' "
        "AND l.status = 'active' AND l.deleted_at IS NULL "
        'AND e.deleted_at IS NULL '
        'AND e.date >= ? AND e.date < ?$ledgerFilter '
        'GROUP BY bucket, l.category_id',
        variables: <drift.Variable<String>>[
          drift.Variable.withString(start),
          drift.Variable.withString(endExclusive),
          if (ledgerId != null) drift.Variable.withString(ledgerId),
        ],
      )
      .get();
  final Map<String, Map<String?, int>> result = <String, Map<String?, int>>{};
  for (final row in rows) {
    (result[row.read<String>('bucket')] ??= <String?, int>{})[
        row.readNullable<String>('category_id')] = row.read<int>('spend_minor');
  }
  return result;
}

void main() {
  test('报表聚合 oracle 对账：随机全年数据 → 桶序列/分类堆叠逐桶一致；'
      '直读与兜底双分支；per-账本过滤', () async {
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();

      // ── 1) 随机夹具（固定种子可复现）：2026 全年 × 每月 1-4 日 ──
      final Random rng = Random(20261122);
      final cdb.Ledger money =
          (await cdb.LedgerDao(db).defaultMoneyLedger())!;
      final cdb.Ledger kcal = (await cdb.LedgerDao(db).kcalLedger())!;
      final List<cdb.Category> categories = await cdb.CategoryDao(db).getAll();
      final List<String> expenseCategoryIds = <String>[
        for (final cdb.Category c in categories)
          if (c.kind == 'expense') c.id,
      ];

      for (int month = 1; month <= 12; month++) {
        final int dayCount = 1 + rng.nextInt(4);
        for (int d = 0; d < dayCount; d++) {
          final String date =
              '2026-${month.toString().padLeft(2, '0')}-'
              '${(1 + rng.nextInt(28)).toString().padLeft(2, '0')}';
          // 约 1/6 软删墓碑（投影/序列必须排除，§5.1）。
          final bool entryDeleted = rng.nextInt(6) == 0;
          // 约 1/5 draft（AI 未确认；投影口径仍计入，§5.6⑬）。
          final String entryStatus =
              rng.nextInt(5) == 0 ? 'draft' : 'confirmed';
          final String entryId = _nextId();
          await _insertEntry(
            db,
            id: entryId,
            date: date,
            kind: rng.nextBool() ? 'expense' : 'mixed',
            status: entryStatus,
            deleted: entryDeleted,
          );
          final int lineCount = 1 + rng.nextInt(3);
          for (int j = 0; j < lineCount; j++) {
            final int roll = rng.nextInt(10);
            if (roll < 3) {
              // money-out（挂随机支出分类；约 1/4 未分类）。
              await _insertLine(
                db,
                id: _nextId(),
                entryId: entryId,
                type: 'money',
                amount: 100 + rng.nextInt(30000),
                direction: 'out',
                ledgerId: money.id,
                categoryId: rng.nextInt(4) == 0
                    ? null
                    : expenseCategoryIds[rng.nextInt(expenseCategoryIds.length)],
                // 约 1/8 void 作废（聚合排除，§5.2②）。
                status: rng.nextInt(8) == 0 ? 'void' : 'active',
              );
            } else if (roll < 5) {
              // money-in。
              await _insertLine(
                db,
                id: _nextId(),
                entryId: entryId,
                type: 'money',
                amount: 100 + rng.nextInt(10000),
                direction: 'in',
                ledgerId: money.id,
                status: 'active',
              );
            } else if (roll < 8) {
              // calorie-in（kcal 账本）。
              await _insertLine(
                db,
                id: _nextId(),
                entryId: entryId,
                type: 'calorie',
                amount: 100 + rng.nextInt(1800),
                direction: 'in',
                ledgerId: kcal.id,
                status: 'active',
              );
            } else {
              // burn-out（运动再入账）。
              await _insertLine(
                db,
                id: _nextId(),
                entryId: entryId,
                type: 'burn',
                amount: 50 + rng.nextInt(800),
                direction: 'out',
                ledgerId: kcal.id,
                status: 'active',
              );
            }
          }
        }
      }
      // superseded 修正链：挑若干 active money 行置 superseded 并补一条
      // active 修正行（修正=新增行，聚合取修正行口径，§5.2②）。
      final List<cdb.EntryLine> moneyLines = await (db.select(db.entryLines)
            ..where((t) => t.type.equals('money') &
                t.status.equals('active') &
                t.deletedAt.isNull()))
          .get();
      final int supersedeCount = 3 + rng.nextInt(4);
      for (int i = 0; i < supersedeCount && i < moneyLines.length; i++) {
        final cdb.EntryLine victim = moneyLines[i];
        await (db.update(db.entryLines)
              ..where((t) => t.id.equals(victim.id)))
            .write(const cdb.EntryLinesCompanion(status: drift.Value('superseded')));
        await _insertLine(
          db,
          id: _nextId(),
          entryId: victim.entryId,
          type: 'money',
          amount: victim.amount + 111,
          direction: victim.direction,
          ledgerId: victim.ledgerId!,
          categoryId: victim.categoryId,
          correctionOf: victim.id,
        );
      }

      // ── 2) 全量重算（投影行就绪 → 直读分支）──
      await cdb.DaySummaryProjection(db).recomputeAll();

      final DriftReportRepository repo = DriftReportRepository(db);
      const String yearStart = '2026-01-01';
      const String yearEnd = '2027-01-01';
      final ReportRange yearRange = ReportRange(
        period: ReportPeriod.year,
        start: yearStart,
        endExclusive: yearEnd,
        byMonth: true,
      );
      final ReportRange novRange = ReportRange(
        period: ReportPeriod.month,
        start: '2026-11-01',
        endExclusive: '2026-12-01',
        byMonth: false,
      );

      // ── 3) 年档（月桶）对账：直读分支 ──
      List<ReportBucketPoint> series = await repo
          .watchBucketSeries(range: yearRange)
          .first;
      Map<String, (int, int, int, int)> oracle =
          await _oracleBuckets(db, start: yearStart, endExclusive: yearEnd, byMonth: true);
      expect(series.length, 12, reason: '年档 12 个月桶');
      for (final ReportBucketPoint point in series) {
        final (int kin, int kout, int spend, int income) =
            oracle[point.bucketKey] ?? (0, 0, 0, 0);
        expect(point.kcalIn, kin, reason: '${point.bucketKey} kcal_in');
        expect(point.kcalOut, kout, reason: '${point.bucketKey} kcal_out');
        expect(point.spendMinor, spend, reason: '${point.bucketKey} spend');
        expect(point.incomeMinor, income, reason: '${point.bucketKey} income');
        expect(point.netKcal, kin - kout, reason: '${point.bucketKey} net');
      }

      // ── 4) 月档（日桶）对账：直读分支 ──
      series = await repo.watchBucketSeries(range: novRange).first;
      oracle = await _oracleBuckets(
        db,
        start: '2026-11-01',
        endExclusive: '2026-12-01',
        byMonth: false,
      );
      expect(series.length, 30, reason: '11 月 30 个日桶');
      for (final ReportBucketPoint point in series) {
        final (int kin, int kout, int spend, int income) =
            oracle[point.bucketKey] ?? (0, 0, 0, 0);
        expect(point.kcalIn, kin, reason: '${point.bucketKey} kcal_in');
        expect(point.kcalOut, kout, reason: '${point.bucketKey} kcal_out');
        expect(point.spendMinor, spend, reason: '${point.bucketKey} spend');
        expect(point.incomeMinor, income, reason: '${point.bucketKey} income');
      }

      // ── 5) 分类堆叠对账（月档）──
      final List<ReportCategoryStack> stacks =
          await repo.watchCategoryStacks(range: novRange).first;
      final Map<String, Map<String?, int>> stackOracle = await _oracleStacks(
        db,
        start: '2026-11-01',
        endExclusive: '2026-12-01',
        byMonth: false,
      );
      final Map<String, Map<String?, int>> stackActual = <String,
          Map<String?, int>>{};
      for (final ReportCategoryStack slice in stacks) {
        (stackActual[slice.bucketKey] ??= <String?, int>{})[slice.categoryId] =
            slice.spendMinor;
      }
      expect(stackActual.length, stackOracle.length, reason: '有数据的桶集合一致');
      stackOracle.forEach((String bucket, Map<String?, int> byCategory) {
        expect(stackActual[bucket], byCategory,
            reason: '$bucket 分类堆叠与 oracle 一致');
      });

      // ── 6) per-账本过滤对账（§11.2 W15 多账本）：money 账本序列 ──
      series = await repo
          .watchBucketSeries(range: yearRange, ledgerId: money.id)
          .first;
      oracle = await _oracleBuckets(
        db,
        start: yearStart,
        endExclusive: yearEnd,
        byMonth: true,
        ledgerId: money.id,
      );
      for (final ReportBucketPoint point in series) {
        final (int kin, int kout, int spend, int income) =
            oracle[point.bucketKey] ?? (0, 0, 0, 0);
        expect(point.spendMinor, spend,
            reason: '${point.bucketKey} money 账本支出（filtered oracle）');
        expect(point.kcalIn, kin,
            reason: '${point.bucketKey} money 账本无 calorie 行 → 0');
        expect(point.incomeMinor, income);
      }

      // ── 7) 兜底分支：DELETE 全部投影行 → entry_lines 聚合仍与 oracle 一致
      // （类文档「day_summary 直读 + entry_lines 聚合兜底」的后半句）──
      await db.delete(db.daySummaries).go();
      series = await repo.watchBucketSeries(range: yearRange).first;
      oracle = await _oracleBuckets(
        db,
        start: yearStart,
        endExclusive: yearEnd,
        byMonth: true,
      );
      for (final ReportBucketPoint point in series) {
        final (int kin, int kout, int spend, int income) =
            oracle[point.bucketKey] ?? (0, 0, 0, 0);
        expect(point.kcalIn, kin, reason: '${point.bucketKey} 兜底 kcal_in');
        expect(point.spendMinor, spend, reason: '${point.bucketKey} 兜底 spend');
        expect(point.incomeMinor, income, reason: '${point.bucketKey} 兜底 income');
      }
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，报表 oracle 对账测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
