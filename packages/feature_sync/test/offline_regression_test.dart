/// W7-8 飞行模式回归测试（§11.1 W7-8「新增飞行模式回归测试：InMemory 后端
/// 分区模拟断网→本地继续写→恢复→补传→双端收敛一致」+ §6.7 离线场景）。
///
/// 场景清单：
/// 1. **飞行模式全链路**：基线同步 → 设备分区（飞行模式）→ 分区期间本地
///    继续写（业务行 + outbox 同事务、day_summary 本地照常重算，§6.1 原则 1
///    「离线全功能可用」）→ syncOnce 只降级报错不抛出、outbox 保全 →
///    对端在线写并上送 → 复网补传（幂等键 = outbox.id，§5.6⑯）→ 双端
///    逐行收敛一致（§6.7）；
/// 2. **低 hlc 迟到行补投**：B 时钟滞后（飞行模式下真实会发生——设备时钟
///    慢于他端），其写入的 hlc 低于 A 已推进的游标 → 纯游标 pull 永远
///    看不见（投递洞）→ 靠投递簿补漏投递一次 → 双端收敛（§6.7 双设备
///    一致脚本的关键半边；服务端水位补漏的线级镜像见
///    supabase_engine_chain_test ⑤）。
///
/// 全程 Fake 远端（禁真实网络，§6.7）；宿主缺 sqlite3 运行库时温和跳过。
library;

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

import 'package:feature_sync/feature_sync.dart';

import 'test_support.dart';

const String kDeviceA = 'A1B2C3D4E5F6';
const String kDeviceB = 'F6E5D4C3B2A1';

Future<SyncHarness?> openTwoDevices() =>
    SyncHarness.open(deviceIds: [kDeviceA, kDeviceB]);

void main() {
  group('飞行模式回归（§11.1 W7-8、§6.7）', () {
    test('①断网→本地继续写→恢复→补传→双端收敛一致', () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);
      final ledgerA = await a.defaultLedgerId();
      final ledgerB = await b.defaultLedgerId();

      // ── 1. 基线：A 建事件 E0 + 金额行 500 → 上送；B 拉取基线。
      final e0 = a.nextUuid();
      final e0Line = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: e0, title: '基线事件'),
        [
          a.makeLine(
            id: e0Line,
            entryId: e0,
            type: domain.LineType.money,
            amount: 500,
            direction: domain.LineDirection.outcome,
            ledgerId: ledgerA,
            currency: 'CNY',
          ),
        ],
      );
      final baseline = await a.engine.syncOnce();
      expect(baseline.error, isNull);
      expect(baseline.acked, 2);
      await b.engine.syncOnce();
      expect(h.backend.rowCount('entries'), 1);
      expect((await b.daySummaryOf(kHarnessDate))['spend_minor'], 500);

      // ── 2. 飞行模式（§6.1 原则 1）：A 分区——空转也只降级（pull 探测失败
      //    → report.error），永不抛出、永不阻塞。
      h.backend.partition(a.deviceId);
      final offline1 = await a.engine.syncOnce();
      expect(offline1.error, isA<SyncBackendException>());
      expect(await a.pendingCount(), 0); // 无待发项
      expect(a.statuses.last.phase, SyncPhase.error); // 传输不可达即降级态
      expect(a.statuses.last.error, isNotNull);

      // ── 3. 分区期间本地继续写（离线全功能）：
      //    E1 + 金额行 1200、E2（无行）、编辑 E0 标题——业务行与 outbox
      //    同事务入队（§6.2 写路径第一步），day_summary 本地照常重算。
      a.wall.advance(5000);
      final e1 = a.nextUuid();
      final e1Line = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: e1, title: '飞行模式写一'),
        [
          a.makeLine(
            id: e1Line,
            entryId: e1,
            type: domain.LineType.money,
            amount: 1200,
            direction: domain.LineDirection.outcome,
            ledgerId: ledgerA,
            currency: 'CNY',
          ),
        ],
      );
      await a.writeEntryWithLines(
        a.makeEntry(id: a.nextUuid(), title: '飞行模式写二'),
      );
      await a.editEntryTitle(e0, '飞行模式改标题');

      // 本地投影自愈：离线写即时入账（500 + 1200，§5.6⑬）。
      expect((await a.daySummaryOf(kHarnessDate))['spend_minor'], 1700);

      // 飞行模式下 syncOnce：传输层分区错误 → report.error，outbox 全保全。
      final offline2 = await a.engine.syncOnce();
      expect(offline2.error, isA<SyncBackendException>());
      expect(offline2.acked, 0);
      expect(await a.pendingCount(), 4); // E1×2 + E2×1 + E0 编辑×1
      expect(a.statuses.last.phase, SyncPhase.error);
      expect(a.statuses.last.error, isNotNull);

      // ── 4. B 在线写 E3 + 金额行 800 → 上送（A 不可见）。
      final e3 = b.nextUuid();
      await b.writeEntryWithLines(
        b.makeEntry(id: e3, title: '对端在线写'),
        [
          b.makeLine(
            id: b.nextUuid(),
            entryId: e3,
            type: domain.LineType.money,
            amount: 800,
            direction: domain.LineDirection.outcome,
            ledgerId: ledgerB,
            currency: 'CNY',
          ),
        ],
      );
      final onlineB = await b.engine.syncOnce();
      expect(onlineB.error, isNull);
      expect(onlineB.acked, 2);
      expect(h.backend.rowCount('entries'), 2); // E0（基线）+ E3；E1/E2 仍在途

      // ── 5. 复网（§6.7 补传）：A 恢复 → syncOnce = 补传 4 项 + 拉到 B 的
      //    E3 行；幂等键 = outbox.id 保证补传不重复入账（§5.6⑯）。
      h.backend.restore(a.deviceId);
      final catchUp = await a.engine.syncOnce();
      expect(catchUp.error, isNull);
      expect(catchUp.acked, 4);
      expect(await a.pendingCount(), 0);
      expect(catchUp.applied, 2); // B 的 E3 事件 + 金额行
      expect((await a.rawRow('entries', e3)), isNotNull);
      expect(a.statuses.last.phase, SyncPhase.done);

      // ── 6. B 补拉 A 的飞行模式写入 → 双端逐行收敛一致（§6.7）。
      final catchUpB = await b.engine.syncOnce();
      expect(catchUpB.error, isNull);
      expect(catchUpB.applied, 4); // E1×2 + E2×1 + E0 编辑×1
      expect(await b.pendingCount(), 0);

      for (final table in const ['entries', 'entry_lines']) {
        final rowsA = await a.database
            .customSelect('SELECT * FROM "$table" ORDER BY id')
            .get();
        final rowsB = await b.database
            .customSelect('SELECT * FROM "$table" ORDER BY id')
            .get();
        // W7-8 集成修复：行数按表分计——entries = E0/E1/E2/E3 共 4 条，
        // entry_lines = E0/E1/E3 的金额行共 3 条（E2 无产出行）。
        expect(
          rowsA.length,
          table == 'entries' ? 4 : 3,
          reason: '$table 行数（飞行模式全链路）',
        );
        for (var i = 0; i < rowsA.length; i++) {
          expect(
            rowsA[i].data,
            equals(rowsB[i].data),
            reason: '$table 第 $i 行双端不一致（§6.7 飞行模式回归失败）',
          );
        }
      }

      // ── 7. 收敛断言：E0 标题为 A 的编辑版（无并发 → baseRevision 命中，
      //    乐观校验通过）；投影双端一致且可验算（500+1200+800）。
      expect((await a.rawRow('entries', e0))!['title'], '飞行模式改标题');
      expect((await b.rawRow('entries', e0))!['title'], '飞行模式改标题');
      final summaryA = await a.daySummaryOf(kHarnessDate);
      final summaryB = await b.daySummaryOf(kHarnessDate);
      expect(summaryA, equals(summaryB));
      expect(summaryA['spend_minor'], 500 + 1200 + 800);

      // ── 8. 二次同步无增量（游标/投递簿双轨去重，§6.2）。
      final quietA = await a.engine.syncOnce();
      expect(quietA.pulled, 0);
      expect(quietA.acked, 0);
      final quietB = await b.engine.syncOnce();
      expect(quietB.pulled, 0);
      expect(quietB.acked, 0);
    });

    test('②低 hlc 迟到行：时钟滞后设备的写入经投递簿补漏收敛（§6.7）', () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. A 先写（墙钟推进 10s，hlc 远大于 B 的基准戳）→ 上送 → 游标推进。
      a.wall.advance(10000);
      final freshId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: freshId, title: '新钟行'),
      );
      final r1 = await a.engine.syncOnce();
      expect(r1.error, isNull);
      final freshHlc = (await a.rawRow('entries', freshId))!['hlc'] as String;

      // 2. B 时钟滞后（不推进墙钟）：离线写——其 hlc 物理段早于 A 的游标，
      //    构造「游标已越过」的投递洞（§6.7 双端一致的关键边界）。
      final lateId = b.nextUuid();
      final lateLineId = b.nextUuid();
      await b.writeEntryWithLines(
        b.makeEntry(id: lateId, title: '滞后钟行'),
        [
          b.makeLine(
            id: lateLineId,
            entryId: lateId,
            type: domain.LineType.calorie,
            amount: 250,
            direction: domain.LineDirection.income,
          ),
        ],
      );
      final lateHlc = (await b.rawRow('entries', lateId))!['hlc'] as String;
      expect(lateHlc.compareTo(freshHlc) < 0, isTrue); // 前提：hlc 低于游标

      // 3. B 上送（服务端接受：新行无 hlc 单调约束）。
      final r2 = await b.engine.syncOnce();
      expect(r2.error, isNull);
      expect(r2.acked, 2);
      expect(h.backend.rowCount('entries'), 2);

      // 4. A 补拉：迟到行 hlc ≤ 游标但从未投递 → 投递簿补投一次 → 落库。
      final r3 = await a.engine.syncOnce();
      expect(r3.error, isNull);
      expect(r3.applied, 2); // 迟到行 + 迟到热量行
      expect((await a.rawRow('entries', lateId))!['title'], '滞后钟行');
      expect((await a.rawRow('entry_lines', lateLineId))!['amount'], 250);

      // 5. 双端已收敛：A 的新钟行早在 B 的 r2 pull 相位落库（syncOnce 恒含
      //    pull，§6.2），B 的迟到行/热量行也在 r2 经回显落库——本轮无增量
      //    （投递簿/游标双轨去重，§6.2）。
      final r4 = await b.engine.syncOnce();
      expect(r4.applied, 0);
      final r5 = await a.engine.syncOnce();
      expect(r5.pulled, 0);
      for (final d in [a, b]) {
        expect((await d.rawRow('entries', lateId))!['hlc'], lateHlc);
        expect((await d.rawRow('entries', freshId))!['hlc'], freshHlc);
      }
    });
  });
}
