/// 多账本过滤互斥对账测试（§5.4④、§3.4 多账本 P1、§11.2 W15）。
///
/// 任务口径「多账本过滤互斥」：同一月内给两个 money 账本 + 内置 kcal 账本
/// 各挂流水，断言——
/// - 账单流（watchMonthBillGroups）：ledgerId 过滤集合两两**互斥**（一条账
///   只出现在其行挂的账本筛选下，§5.2② 行必挂账本），并集=全量；
/// - 分类汇总（watchMonthCategorySums）：per-账本金额拆分自洽（A+B=全量）；
/// - 报表序列（watchBucketSeries）：per-账本桶序列互斥且支出可加（A+B=全量，
///   全量无未挂账本流水的前提在夹具内保证）。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过（与 W5-6 widget 测试同一守卫）。
library;

import 'package:core_db/core_db.dart' as cdb;
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
int _ms = 1763251200000;

/// 插入一条 entry + 单行 facet（§5.2①②；金额/热量维度并存）。
/// [ledgerId] 允许 null（模拟「无归属」防御组，§5.2② ledger_id 可空行）。
Future<void> _insertEntry(
  cdb.AppDatabase db, {
  required String entryId,
  required String date,
  required String title,
  required String lineId,
  required String type,
  required int amount,
  required String direction,
  String? ledgerId,
  String? categoryId,
}) async {
  final int entryMs = _ms;
  _ms += 1000;
  await db.into(db.entries).insert(
        cdb.Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: entryMs,
          kind: type == 'money' ? 'expense' : 'food',
          source: 'manual',
          title: title,
          note: null,
          status: 'confirmed',
          aiParseId: null,
          createdAt: entryMs,
          updatedAt: entryMs,
          deletedAt: null,
          hlc: '$entryMs:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
  final int lineMs = entryMs + 2;
  await db.into(db.entryLines).insert(
        cdb.EntryLine(
          id: lineId,
          entryId: entryId,
          type: type,
          amount: amount,
          direction: direction,
          ledgerId: ledgerId,
          categoryId: categoryId,
          currency: type == 'money' ? 'CNY' : null,
          confidence: null,
          payload: null,
          correctionOf: null,
          status: 'active',
          createdAt: lineMs,
          updatedAt: lineMs,
          deletedAt: null,
          hlc: '$lineMs:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
}

void main() {
  test('多账本过滤互斥：账单流/分类汇总/报表序列 per-账本拆分自洽', () async {
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性

      // ── 夹具：默认账本 A + 新建账本 B + 内置 kcal 账本 ──
      final cdb.Ledger ledgerA = (await cdb.LedgerDao(db).defaultMoneyLedger())!;
      final cdb.LedgerDao ledgerDao = cdb.LedgerDao(db);
      final cdb.Ledger ledgerB = await ledgerDao.createLedger(
        name: '旅行账本',
        currency: 'CNY',
      );
      final cdb.Ledger kcal = (await ledgerDao.kcalLedger())!;
      final List<cdb.Category> categories = await cdb.CategoryDao(db).getAll();
      final String catMeal =
          categories.firstWhere((c) => c.name == '餐饮-正餐').id;
      final String catTraffic = categories.firstWhere((c) => c.name == '交通').id;
      final String catShopping = categories.firstWhere((c) => c.name == '购物').id;

      // A：11-05 餐饮 5000、11-10 交通 400。
      // B：11-05 购物 12000、11-10 餐饮 8000。
      // kcal：11-06 摄入 650。
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000a001',
          date: '2026-11-05', title: 'A-面馆', lineId: 'l-a001',
          type: 'money', amount: 5000, direction: 'out',
          ledgerId: ledgerA.id, categoryId: catMeal);
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000a002',
          date: '2026-11-10', title: 'A-通勤', lineId: 'l-a002',
          type: 'money', amount: 400, direction: 'out',
          ledgerId: ledgerA.id, categoryId: catTraffic);
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000b001',
          date: '2026-11-05', title: 'B-手办', lineId: 'l-b001',
          type: 'money', amount: 12000, direction: 'out',
          ledgerId: ledgerB.id, categoryId: catShopping);
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000b002',
          date: '2026-11-10', title: 'B-当地饭', lineId: 'l-b002',
          type: 'money', amount: 8000, direction: 'out',
          ledgerId: ledgerB.id, categoryId: catMeal);
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000k001',
          date: '2026-11-06', title: 'k-早餐', lineId: 'l-k001',
          type: 'calorie', amount: 650, direction: 'in',
          ledgerId: kcal.id, categoryId: catMeal);

      final DriftLedgerRepository repo = DriftLedgerRepository(db);
      final DriftReportRepository report = DriftReportRepository(db);

      // ── 1) 账单流互斥（§3.4 账单页 ledgerId 过滤）──
      final List<LedgerDayGroup> all =
          await repo.watchMonthBillGroups('2026-11').first;
      final List<LedgerDayGroup> onlyA =
          await repo.watchMonthBillGroups('2026-11', ledgerId: ledgerA.id).first;
      final List<LedgerDayGroup> onlyB =
          await repo.watchMonthBillGroups('2026-11', ledgerId: ledgerB.id).first;
      final List<LedgerDayGroup> onlyKcal =
          await repo.watchMonthBillGroups('2026-11', ledgerId: kcal.id).first;

      Set<String> entryIdsOf(List<LedgerDayGroup> groups) => <String>{
            for (final LedgerDayGroup group in groups)
              for (final LedgerBillEntry entry in group.entries) entry.entryId,
          };

      final Set<String> allIds = entryIdsOf(all);
      final Set<String> aIds = entryIdsOf(onlyA);
      final Set<String> bIds = entryIdsOf(onlyB);
      final Set<String> kcalIds = entryIdsOf(onlyKcal);
      expect(aIds.intersection(bIds), isEmpty, reason: 'A/B 筛选集合互斥（§5.2②）');
      expect(aIds.intersection(kcalIds), isEmpty, reason: 'money/kcal 账本互斥');
      expect(bIds.intersection(kcalIds), isEmpty);
      expect(<String>{...aIds, ...bIds, ...kcalIds}, allIds,
          reason: 'per-账本并集=全量（行必挂账本，§5.2②）');
      expect(aIds, <String>{'0196a7e0-0000-7000-8000-00000000a001',
          '0196a7e0-0000-7000-8000-00000000a002'});
      expect(bIds, <String>{'0196a7e0-0000-7000-8000-00000000b001',
          '0196a7e0-0000-7000-8000-00000000b002'});
      // 混合账（同 entry 多行跨账本）在 W15 不出现——行级账本即筛选粒度。

      // 金额自洽：onlyA 日合计只含 A 行。
      final int aSpend = onlyA.fold(
        0,
        (int sum, LedgerDayGroup g) => sum + g.spendMinor,
      );
      expect(aSpend, 5400, reason: 'A=餐饮 5000 + 交通 400');
      final int bSpend = onlyB.fold(
        0,
        (int sum, LedgerDayGroup g) => sum + g.spendMinor,
      );
      expect(bSpend, 20000, reason: 'B=购物 12000 + 餐饮 8000');
      final int allSpend = all.fold(
        0,
        (int sum, LedgerDayGroup g) => sum + g.spendMinor,
      );
      expect(allSpend, aSpend + bSpend, reason: 'A+B=全量');

      // ── 2) 分类汇总互斥（§3.4 月度分类汇总）──
      final List<LedgerCategorySum> sumsA =
          await repo.watchMonthCategorySums('2026-11', ledgerId: ledgerA.id).first;
      final List<LedgerCategorySum> sumsB =
          await repo.watchMonthCategorySums('2026-11', ledgerId: ledgerB.id).first;
      int sumOf(List<LedgerCategorySum> sums) =>
          sums.fold(0, (int s, LedgerCategorySum x) => s + x.spendMinor);
      expect(sumOf(sumsA), 5400);
      expect(sumOf(sumsB), 20000);
      final List<LedgerCategorySum> sumsAll =
          await repo.watchMonthCategorySums('2026-11').first;
      expect(sumOf(sumsAll), sumOf(sumsA) + sumOf(sumsB));

      // ── 3) 报表序列互斥（§3.4 报表 ledgerId 过滤 + 双轴联动）──
      final ReportRange november = reportRangeFor(
        ReportPeriod.month,
        DateTime(2026, 11, 15),
      );
      final List<ReportBucketPoint> seriesAll = await report
          .watchBucketSeries(range: november)
          .first;
      final List<ReportBucketPoint> seriesA = await report
          .watchBucketSeries(range: november, ledgerId: ledgerA.id)
          .first;
      final List<ReportBucketPoint> seriesB = await report
          .watchBucketSeries(range: november, ledgerId: ledgerB.id)
          .first;

      expect(seriesAll.length, 30, reason: '11 月 30 个日桶（零填充）');
      int spendOf(List<ReportBucketPoint> series) =>
          series.fold(0, (int s, ReportBucketPoint p) => s + p.spendMinor);
      expect(spendOf(seriesA), 5400);
      expect(spendOf(seriesB), 20000);
      expect(spendOf(seriesAll), spendOf(seriesA) + spendOf(seriesB),
          reason: '桶序列 per-账本可加（夹具无未挂账本流水）');
      // 桶级互斥抽查：11-05 桶 A=5000、B=12000、all=17000。
      ReportBucketPoint bucketOf(List<ReportBucketPoint> series, String key) =>
          series.firstWhere((ReportBucketPoint p) => p.bucketKey == key);
      expect(bucketOf(seriesA, '2026-11-05').spendMinor, 5000);
      expect(bucketOf(seriesB, '2026-11-05').spendMinor, 12000);
      expect(bucketOf(seriesAll, '2026-11-05').spendMinor, 17000);
      // kcal 维度按账本过滤：kcal 摄入只出现在 kcal 账本序列。
      expect(bucketOf(seriesA, '2026-11-06').kcalIn, 0);
      final List<ReportBucketPoint> seriesKcal = await report
          .watchBucketSeries(range: november, ledgerId: kcal.id)
          .first;
      expect(bucketOf(seriesKcal, '2026-11-06').kcalIn, 650);
      expect(bucketOf(seriesKcal, '2026-11-06').spendMinor, 0,
          reason: 'kcal 账本筛选下无 money 流水');
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，多账本过滤互斥测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  test('报表序列：未挂账本行在全量口径出现、per-账本口径不出现（兜底聚合）',
      () async {
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final cdb.Ledger ledgerA =
          (await cdb.LedgerDao(db).defaultMoneyLedger())!;

      // 无 day_summary 行（投影未建）→ 序列走 entry_lines 聚合兜底。
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000c001',
          date: '2026-11-12', title: '孤儿行', lineId: 'l-c001',
          type: 'money', amount: 900, direction: 'out',
          ledgerId: null, categoryId: null);
      await _insertEntry(db,
          entryId: '0196a7e0-0000-7000-8000-00000000c002',
          date: '2026-11-12', title: 'A 行', lineId: 'l-c002',
          type: 'money', amount: 300, direction: 'out',
          ledgerId: ledgerA.id, categoryId: null);

      final DriftReportRepository report = DriftReportRepository(db);
      final ReportRange november =
          reportRangeFor(ReportPeriod.month, DateTime(2026, 11, 15));
      final List<ReportBucketPoint> seriesAll =
          await report.watchBucketSeries(range: november).first;
      final List<ReportBucketPoint> seriesA =
          await report.watchBucketSeries(range: november, ledgerId: ledgerA.id).first;

      ReportBucketPoint bucketOf(List<ReportBucketPoint> series, String key) =>
          series.firstWhere((ReportBucketPoint p) => p.bucketKey == key);
      expect(bucketOf(seriesAll, '2026-11-12').spendMinor, 1200,
          reason: '未挂账本行只进全量口径（§5.2② 防御组）');
      expect(bucketOf(seriesA, '2026-11-12').spendMinor, 300,
          reason: 'per-账本口径不含未挂账本行（互斥）');
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，多账本过滤互斥测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
