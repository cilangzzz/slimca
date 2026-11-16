/// W5-6 冲突测试集（§11.1 W5-6 验收「冲突测试集四用例」+ §6.5 矩阵 +
/// §6.7 双设备一致脚本 + §6.2 读写路径回归）。
///
/// 用例清单：
/// 1. 双端并发写同 facet 行 → LWW 后写者胜且 hlc 正确（§6.5 第 3 行）；
/// 2. 不同 facet 行免冲突互保（§5.3/§6.5 第 4 行）；
/// 3. 删除后远端旧副本 pull 不复活、墓碑恒胜（§6.5 第 7 行）；
/// 4. 离线补写时钟推进 + 定宽序正确（§6.3）；
/// 5. 双端各写 50 条收敛一致（总 100 条，§6.7）；
/// 6. 回归：rowMissing 依赖序、baseRevision 乐观校验、schema_ver 兼容、
///    pull 分批续拉、分区降级、LocalLoopback 缺省装配、resolve 矩阵单测。
///
/// 全程 Fake 远端（InMemorySyncBackend/LocalLoopbackBackend），
/// 禁真实网络/真实平台通道（§6.7 验收自动化）；宿主缺 sqlite3 运行库时
/// 温和跳过（与 core_db 测试同一策略）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

import 'package:feature_sync/feature_sync.dart';

import 'test_support.dart';

/// 确定性设备标识（12 位 hex，§6.3 节点段；B > A 便于同刻决胜断言）。
const String kDeviceA = 'A1B2C3D4E5F6';
const String kDeviceB = 'F6E5D4C3B2A1';

/// 构造合法定宽 HLC（§6.3）。
String hlcOf(int physicalMs, int counter, String device) =>
    domain.Hlc(physicalMs: physicalMs, counter: counter, deviceId: device)
        .format();

/// 打开双设备夹具；宿主缺 sqlite3 运行库时返回 null（调用方 SKIP）。
Future<SyncHarness?> openTwoDevices() =>
    SyncHarness.open(deviceIds: [kDeviceA, kDeviceB]);

void main() {
  group('冲突测试集四用例 + 收敛（§11.1 W5-6 验收）', () {
    test('①双端并发写同 facet 行：LWW 后写者胜且 hlc 正确（§6.5 第 3 行）',
        () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. A 建事件 + 热量行（同 facet 行的唯一初始版本），上送。
      final entryId = a.nextUuid();
      final lineId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: entryId, title: '午餐'),
        [
          a.makeLine(
            id: lineId,
            entryId: entryId,
            type: domain.LineType.calorie,
            amount: 600,
            direction: domain.LineDirection.income,
          ),
        ],
      );
      await a.engine.syncOnce();
      expect(h.backend.rowCount('entries'), 1);
      expect(h.backend.rowCount('entry_lines'), 1);

      // 2. B 拉取基线（双端同持 L1:600）。
      await b.engine.syncOnce();
      expect((await b.rawRow('entry_lines', lineId))!['amount'], 600);

      // 3. 双端离线并发编辑同一 facet 行：A 早 5ms、B 晚 10ms（B=后写者）。
      h.backend.partition(a.deviceId);
      h.backend.partition(b.deviceId);
      a.wall.advance(5);
      final metaA = await a.editLineAmount(lineId, 700);
      b.wall.advance(10);
      final metaB = await b.editLineAmount(lineId, 800);
      // 后写者的 hlc 严格更大（定宽字典序=时间序，§6.3）。
      expect(metaB.hlc.compareTo(metaA.hlc) > 0, isTrue);

      // 4. 复网：B 先上送（接受）；A 后上送（hlc 落后 → hlcNonMonotonic 拒绝）。
      h.backend.restore(b.deviceId);
      final reportB = await b.engine.syncOnce();
      expect(reportB.acked, 1);
      expect(h.backend.rowState('entry_lines', lineId)!.hlc, metaB.hlc);

      h.backend.restore(a.deviceId);
      final reportA = await a.engine.syncOnce();
      expect(
        reportA.rejections[domain.SyncRejectionReason.hlcNonMonotonic],
        1,
      );
      expect(reportA.droppedOutbox, 1);
      expect(await a.pendingCount(), 0);

      // 5. 双端收敛到后写者（800），行 hlc = 后写者戳（LWW 裁决正确）。
      final lineA = await a.rawRow('entry_lines', lineId);
      final lineB = await b.rawRow('entry_lines', lineId);
      expect(lineA!['amount'], 800);
      expect(lineA['hlc'], metaB.hlc);
      expect(lineB!['amount'], 800);
      expect(lineB['hlc'], metaB.hlc);

      // 6. hlc 正确：A 经 recv 合并后写者时间戳，下一枚本地戳严格大于它
      //    （§6.3「收到比本地新的时间戳 → 跳变跟上」），且仍满足定宽编码。
      final next = a.clock.now().format();
      expect(next.compareTo(metaB.hlc) > 0, isTrue);
      expect(
        RegExp(r'^\d{13}:\d{6}:[0-9A-F]{12}$').hasMatch(next),
        isTrue,
      );
    });

    test('②不同 facet 行免冲突互保：修正金额与改热量并行、双端全存活（§5.3）',
        () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. A 建混合事件：金额行 M（1850 分）+ 热量行 C（720 kcal），上送；B 拉取。
      final ledgerA = await a.defaultLedgerId();
      final entryId = a.nextUuid();
      final moneyId = a.nextUuid();
      final kcalId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: entryId, title: '晚餐'),
        [
          a.makeLine(
            id: moneyId,
            entryId: entryId,
            type: domain.LineType.money,
            amount: 1850,
            direction: domain.LineDirection.outcome,
            ledgerId: ledgerA,
            currency: 'CNY',
          ),
          a.makeLine(
            id: kcalId,
            entryId: entryId,
            type: domain.LineType.calorie,
            amount: 720,
            direction: domain.LineDirection.income,
          ),
        ],
      );
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // 2. 双端离线改**不同 facet 行**（结构性免冲突，§5.3）：
      //    A 修正金额（新增 correction 行 M2=2200，M→superseded，§5.2②）；
      //    B 改热量 720→900。
      h.backend.partition(a.deviceId);
      h.backend.partition(b.deviceId);
      a.wall.advance(5);
      final correctionId = a.nextUuid();
      await a.supersedeMoneyLine(
        moneyId,
        a.makeLine(
          id: correctionId,
          entryId: entryId,
          type: domain.LineType.money,
          amount: 2200,
          direction: domain.LineDirection.outcome,
          ledgerId: ledgerA,
          currency: 'CNY',
          correctionOf: moneyId,
          meta: a.stamp(),
        ),
      );
      b.wall.advance(10);
      final kcalMeta = await b.editLineAmount(kcalId, 900);

      // 3. 复网互相同步（A 推拉 → B 推拉 → A 再拉）。
      h.backend.restore(a.deviceId);
      h.backend.restore(b.deviceId);
      await a.engine.syncOnce();
      await b.engine.syncOnce();
      await a.engine.syncOnce();

      // 4. 双端收敛：三行互保——M(superseded) + M2(correction) + C(900)。
      expect(h.backend.rowCount('entry_lines'), 3);
      for (final d in [a, b]) {
        final m = await d.rawRow('entry_lines', moneyId);
        final m2 = await d.rawRow('entry_lines', correctionId);
        final c = await d.rawRow('entry_lines', kcalId);
        expect(m!['status'], 'superseded');
        expect(m2!['amount'], 2200);
        expect(m2['correction_of'], moneyId);
        expect(c!['amount'], 900);
        expect(c['hlc'], kcalMeta.hlc);
      }

      // 5. day_summary 由 dirty 自愈重算（投影不同步，§6.5 末行）：
      //    双端同日聚合一致 = 修正后金额 2200 + 热量 900（superseded 不计入，
      //    §5.6⑬ 明细聚合 SQL 只数 active 行）。
      final summaryA = await a.daySummaryOf(kHarnessDate);
      final summaryB = await b.daySummaryOf(kHarnessDate);
      expect(summaryA, equals(summaryB));
      expect(summaryA['spend_minor'], 2200);
      expect(summaryA['kcal_in'], 900);
    });

    test('③删除后远端旧副本：pull 不复活、墓碑恒胜（§6.5 第 7 行）', () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // ── push 半边：陈旧存活副本上送撞墓碑 → 拒绝 → 采纳墓碑 ──────────
      // 1. A 建事件（+金额行），上送；B 拉取存活副本。
      final ledgerA = await a.defaultLedgerId();
      final entryId = a.nextUuid();
      final moneyId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: entryId, title: '将删事件'),
        [
          a.makeLine(
            id: moneyId,
            entryId: entryId,
            type: domain.LineType.money,
            amount: 990,
            direction: domain.LineDirection.outcome,
            ledgerId: ledgerA,
            currency: 'CNY',
          ),
        ],
      );
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // 2. A 软删并上送 → 服务端行=墓碑。
      await a.deleteEntry(entryId);
      await a.engine.syncOnce();
      expect(h.backend.rowState('entries', entryId)!.isTombstone, isTrue);

      // 3. B 离线编辑不知已删的存活副本（hlc 比墓碑更新）。
      h.backend.partition(b.deviceId);
      b.wall.advance(30);
      await b.editEntryTitle(entryId, '平板改标题');
      h.backend.restore(b.deviceId);

      // 4. B 上送存活 upsert：hlc 校验通过但 baseRevision 已过期 → 拒绝；
      //    引擎作废出网项并采纳服务端墓碑 → 本地保持删除（不复活）。
      final report4 = await b.engine.syncOnce();
      expect(
        report4.rejections[domain.SyncRejectionReason.baseRevisionConflict],
        1,
      );
      expect(await b.pendingCount(), 0);
      final afterAdopt = await b.rawRow('entries', entryId);
      expect(afterAdopt!['deleted_at'], isNotNull);
      expect(h.backend.rowState('entries', entryId)!.isTombstone, isTrue);

      // 5. 更强的复活尝试：未来戳 + 无 baseRevision 的存活快照 →
      //    服务端 tombstoneConflict（墓碑拒绝复活在服务端强制）→
      //    引擎采纳墓碑 → 仍保持删除。
      final staleRow = (await b.rawRow('entries', entryId))!;
      final reviveHlc = b.clock.now().format();
      await b.enqueueRaw(
        tableName: 'entries',
        rowId: entryId,
        payload: <String, Object?>{
          ...staleRow,
          'deleted_at': null,
          'title': '复活尝试',
          'hlc': reviveHlc,
          'updated_at': domain.Hlc.parse(reviveHlc).physicalMs,
        },
        hlc: reviveHlc,
      );
      final report5 = await b.engine.syncOnce();
      expect(
        report5.rejections[domain.SyncRejectionReason.tombstoneConflict],
        1,
      );
      expect((await b.rawRow('entries', entryId))!['deleted_at'], isNotNull);

      // ── pull 半边：更晚 hlc 的存活副本只 pull 不 push → 墓碑经仲裁胜出 ──
      // 6. 新事件 E2：A 建 → 上送 → B 拉取；A 软删 → 上送。
      final entry2 = a.nextUuid();
      await a.writeEntryWithLines(a.makeEntry(id: entry2, title: '事件二'));
      await a.engine.syncOnce();
      await b.engine.syncOnce();
      await a.deleteEntry(entry2);
      await a.engine.syncOnce();
      expect(h.backend.rowState('entries', entry2)!.isTombstone, isTrue);

      // 7. B 离线编辑存活副本（hlc 远晚于墓碑），**不上送**、只 pull：
      //    墓碑胜出与 hlc 新旧无关（「删后编辑保持删除胜出」§6.5 第 7 行）。
      b.wall.advance(40);
      await b.editEntryTitle(entry2, '陈旧副本编辑');
      expect((await b.rawRow('entries', entry2))!['deleted_at'], isNull);

      await b.engine.pull(await b.store.readCursors());
      final pulled = await b.rawRow('entries', entry2);
      expect(pulled!['deleted_at'], isNotNull);
      expect(pulled['hlc'], h.backend.rowState('entries', entry2)!.hlc);

      // 8. 该陈旧出网项随后上送：仍被拒（baseRevision 过期）→ 采纳墓碑
      //    → 清账、保持删除——push/pull 两条采纳路径结论一致。
      expect(await b.pendingCount(), 1);
      final report8 = await b.engine.syncOnce();
      expect(
        report8.rejections[domain.SyncRejectionReason.baseRevisionConflict],
        1,
      );
      expect((await b.rawRow('entries', entry2))!['deleted_at'], isNotNull);
      expect(await b.pendingCount(), 0);
    });

    test('④离线补写：counter 递增、墙钟推进复位、recv 跳变、定宽序=时间序（§6.3）',
        () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. A 全程离线连写 4 条（同一虚拟毫秒 → counter 0..3）。
      h.backend.partition(a.deviceId);
      final offlineHlcs = <String>[];
      for (var i = 0; i < 4; i++) {
        final metas =
            await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));
        offlineHlcs.add(metas.single.hlc);
      }
      // 同毫秒连发：物理段全等、counter 严格递增（§6.3「同 ms 并发自增」）。
      final parsed = offlineHlcs.map(domain.Hlc.parse).toList();
      for (var i = 1; i < parsed.length; i++) {
        expect(parsed[i].physicalMs, parsed[0].physicalMs);
        expect(parsed[i].counter, parsed[i - 1].counter + 1);
      }
      // 定宽字典序 = 签发序 = 时间序（§6.3 核心性质）。
      expect(offlineHlcs, equals([...offlineHlcs]..sort()));

      // 2. 墙钟推进 1ms：物理 +1、counter 归零（§6.3 时钟推进行）。
      a.wall.advance(1);
      final meta5 =
          (await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()))).single;
      final p5 = domain.Hlc.parse(meta5.hlc);
      expect(p5.physicalMs, parsed[0].physicalMs + 1);
      expect(p5.counter, 0);
      expect(meta5.hlc.compareTo(offlineHlcs.last) > 0, isTrue);

      // 3. 服务端持有远端未来时间戳（B 时钟快 1 小时）；B 上送后 A 复网拉取。
      b.wall.advance(3600000);
      final remoteMeta = (await b.writeEntryWithLines(
        b.makeEntry(id: b.nextUuid(), title: '未来设备'),
      ))
          .single;
      expect(remoteMeta.hlc.compareTo(offlineHlcs.last) > 0, isTrue);
      await b.engine.syncOnce();

      h.backend.restore(a.deviceId);
      final report = await a.engine.syncOnce(); // push 5 条 + pull（含远端行）
      expect(report.acked, 5);
      expect(h.backend.rowCount('entries'), 6);

      // 4. recv 跳变跟上：A 下一枚本地戳严格大于远端未来戳（§6.3），
      //    且与全部历史戳构成单调全序、满足定宽编码。
      final next = a.clock.now().format();
      expect(next.compareTo(remoteMeta.hlc) > 0, isTrue);
      final allOrder = [
        ...offlineHlcs,
        meta5.hlc,
        remoteMeta.hlc,
        next,
      ]..sort();
      expect(allOrder.last, next);
      expect(
        RegExp(r'^\d{13}:\d{6}:[0-9A-F]{12}$').hasMatch(next),
        isTrue,
      );
    });

    test('⑤双端各离线写 50 条 → 三轮同步收敛一致，总计 100 条（§6.7）', () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. 双端各自离线写 50 条（事件 + 金额行），两天分摊、金额可验算。
      h.backend.partition(a.deviceId);
      h.backend.partition(b.deviceId);
      final ledgerA = await a.defaultLedgerId();
      final ledgerB = await b.defaultLedgerId();
      final expectedSpend = <String, int>{};
      Future<void> writeBatch(
        SyncDeviceFixture d,
        String ledgerId,
        String tag,
        int baseAmount,
      ) async {
        for (var i = 0; i < 50; i++) {
          final date = i.isEven ? kHarnessDate : '2026-11-15';
          final id = d.nextUuid();
          final amount = baseAmount + i;
          await d.writeEntryWithLines(
            d.makeEntry(id: id, date: date, title: '$tag-$i'),
            [
              d.makeLine(
                id: d.nextUuid(),
                entryId: id,
                type: domain.LineType.money,
                amount: amount,
                direction: domain.LineDirection.outcome,
                ledgerId: ledgerId,
                currency: 'CNY',
              ),
            ],
          );
          expectedSpend[date] = (expectedSpend[date] ?? 0) + amount;
        }
      }

      await writeBatch(a, ledgerA, '手机', 100);
      await writeBatch(b, ledgerB, '平板', 900);

      // 2. 复网：A 推拉 → B 推拉 → A 再拉，三轮收敛。
      h.backend.restore(a.deviceId);
      h.backend.restore(b.deviceId);
      final r1 = await a.engine.syncOnce();
      expect(r1.error, isNull);
      expect(r1.acked, 100);
      final r2 = await b.engine.syncOnce();
      expect(r2.acked, 100);
      expect(r2.applied, 100); // A 的 100 行落库
      expect(r2.skipped, 100); // 自身 100 行回显跳过
      final r3 = await a.engine.syncOnce();
      expect(r3.applied, 100); // B 的 100 行补投落库（含 hlc ≤ 游标的行）
      expect(r3.skipped, 0); // A 自身回显在 r1 已投递（投递簿去重不重发）

      // 3. 行级一致：事件 100/100、金额行 100/100，双端逐行全字段相等。
      expect(h.backend.rowCount('entries'), 100);
      expect(h.backend.rowCount('entry_lines'), 100);
      for (final table in const ['entries', 'entry_lines']) {
        final rowsA = await a.database
            .customSelect('SELECT * FROM "$table" ORDER BY id')
            .get();
        final rowsB = await b.database
            .customSelect('SELECT * FROM "$table" ORDER BY id')
            .get();
        expect(rowsA.length, 100);
        for (var i = 0; i < rowsA.length; i++) {
          expect(
            rowsA[i].data,
            equals(rowsB[i].data),
            reason: '$table 第 $i 行双端不一致',
          );
        }
      }

      // 4. day_summary 自愈一致且可验算（§5.6⑬/§6.5 末行）。
      for (final date in const [kHarnessDate, '2026-11-15']) {
        final summaryA = await a.daySummaryOf(date);
        final summaryB = await b.daySummaryOf(date);
        expect(summaryA, equals(summaryB));
        expect(summaryA['spend_minor'], expectedSpend[date]);
      }
    });
  });

  group('§6.2 读写路径回归', () {
    test('子行先于父行上送：rowMissing 暂缓保留，父行补送后自动重试清账', () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      final entryId = a.nextUuid();
      final lineId = a.nextUuid();
      // 行戳顺序：line 先签发 → outbox 出队序（created_at 升序）line 在前，
      // 构造「子行先于父行」的乱序上送（§6.2 per-table 依赖序的对侧场景）。
      final lineMeta = a.stamp();
      final entryMeta = a.stamp();
      final entry = a.makeEntry(id: entryId, meta: entryMeta);
      final line = a.makeLine(
        id: lineId,
        entryId: entryId,
        type: domain.LineType.calorie,
        amount: 500,
        direction: domain.LineDirection.income,
        meta: lineMeta,
      );
      await a.enqueueRaw(
        tableName: 'entry_lines',
        rowId: lineId,
        payload: line.toJson(),
        hlc: lineMeta.hlc,
      );
      await a.enqueueRaw(
        tableName: 'entries',
        rowId: entryId,
        payload: entry.toJson(),
        hlc: entryMeta.hlc,
      );

      final report = await a.engine.syncOnce();
      expect(
        report.rejections[domain.SyncRejectionReason.rowMissing],
        1,
      );
      // 父行补送 ack 后，同轮自动重试成功清账（§6.2 暂缓语义）。
      expect(await a.pendingCount(), 0);
      expect(h.backend.rowCount('entries'), 1);
      expect(h.backend.rowCount('entry_lines'), 1);
    });

    test('baseRevision 乐观校验：基于旧版本的写入被拒并采纳服务端现值（§5.6⑯）',
        () async {
      final h = await openTwoDevices();
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      final entryId = a.nextUuid();
      await a.writeEntryWithLines(a.makeEntry(id: entryId, title: 'v1'));
      await a.engine.syncOnce();
      await b.engine.syncOnce();

      // 双端离线编辑；B 复网先上送（接受）；A 的编辑 hlc 更新但 baseRevision
      // 仍是旧版本 → baseRevisionConflict（hlc 校验必过 → 隔离出乐观校验分支）。
      h.backend.partition(a.deviceId);
      h.backend.partition(b.deviceId);
      b.wall.advance(10);
      await b.editEntryTitle(entryId, 'B改');
      a.wall.advance(20);
      await a.editEntryTitle(entryId, 'A改');

      h.backend.restore(b.deviceId);
      await b.engine.syncOnce();
      h.backend.restore(a.deviceId);
      final report = await a.engine.syncOnce();
      expect(
        report.rejections[domain.SyncRejectionReason.baseRevisionConflict],
        1,
      );
      expect(report.droppedOutbox, 1);
      // 采纳服务端现值：双端收敛到 B 的版本（尽管 A 的 hlc 更新）——
      // 乐观校验语义：基于旧版本的写入不可直接落，出网作废。
      expect((await a.rawRow('entries', entryId))!['title'], 'B改');
      expect((await b.rawRow('entries', entryId))!['title'], 'B改');
      expect(await a.pendingCount(), 0);
    });

    test('schema_ver 兼容：超档上送作废、超档远端行跳过但游标推进、未知列忽略（§6.4）',
        () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      // ① push 侧：超档载荷 → schemaVerRejected → 出网作废（永不重试）。
      final badId = a.nextUuid();
      final badMeta = a.stamp();
      final badPayload = a.makeEntry(id: badId, meta: badMeta).toJson()
        ..['schema_ver'] = 2;
      await a.enqueueRaw(
        tableName: 'entries',
        rowId: badId,
        payload: badPayload,
        hlc: badMeta.hlc,
      );
      final report = await a.engine.syncOnce();
      expect(
        report.rejections[domain.SyncRejectionReason.schemaVerRejected],
        1,
      );
      expect(report.droppedOutbox, 1);
      expect(h.backend.rowCount('entries'), 0);
      expect(await a.pendingCount(), 0);

      // ② pull 侧：服务端种入超档行 → 跳过不落库，但游标照常推进、不阻断。
      final futureHlc = hlcOf(kHarnessBaseWallMs + 50, 0, 'FFFFFFFFFFFF');
      h.backend.seedServerRow(
        'food_items',
        ServerRowState(
          payload: <String, Object?>{
            'id': 'future-food-01',
            'schema_ver': 2,
            'hlc': futureHlc,
          },
          hlc: futureHlc,
          revision: 1,
          schemaVer: 2,
        ),
      );

      // ③ 前瞻行：同档 schema_ver + 未知列 → 正常落库（老客户端忽略新列）。
      final okHlc = hlcOf(kHarnessBaseWallMs + 60, 0, 'FFFFFFFFFFFF');
      const ledgerId = 'ledger-future-01';
      h.backend.seedServerRow(
        'ledgers',
        ServerRowState(
          payload: <String, Object?>{
            'id': ledgerId,
            'name': '未来账本',
            'icon': 'wallet',
            'currency': 'CNY',
            'kind': 'money',
            'sort': 99,
            'opening_balance_minor': 0,
            'is_archived': 0,
            'created_at': kHarnessBaseWallMs,
            'updated_at': kHarnessBaseWallMs + 60,
            'deleted_at': null,
            'hlc': okHlc,
            'revision': 1,
            'schema_ver': 1,
            'device_id': 'FFFFFFFFFFFF',
            'future_column': '前瞻值',
          },
          hlc: okHlc,
          revision: 1,
          schemaVer: 1,
        ),
      );

      final report2 = await a.engine.syncOnce();
      expect(report2.skipped, 1); // 超档行确定性跳过
      expect(report2.applied, 1); // 前瞻行落库
      expect(await a.rawRow('food_items', 'future-food-01'), isNull);
      expect(report2.cursors['food_items'], futureHlc); // 游标仍推进
      final ledger = await a.rawRow('ledgers', ledgerId);
      expect(ledger, isNotNull);
      expect(ledger!['name'], '未来账本');
      expect(ledger.containsKey('future_column'), isFalse);

      // ④ 二次同步无增量（游标已越过；跳过属确定性处理、不重复投递）。
      final report3 = await a.engine.syncOnce();
      expect(report3.pulled, 0);
    });

    test('pull 分批续拉：hasMore 逐批清空、游标推进至最大 hlc（§6.2/§5.6⑰）',
        () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA], maxPullRows: 10);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      final hlcs = <String>[];
      for (var i = 0; i < 25; i++) {
        final metas =
            await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));
        hlcs.add(metas.single.hlc);
      }
      final report = await a.engine.syncOnce();
      expect(report.acked, 25);
      // 回显行与本地行同 hlc → LWW 判本地胜 → 跳过计数；游标照常推进
      // （确定性处理含仲裁跳过，§6.2）。
      expect(report.skipped, 25);
      expect(report.applied, 0);
      expect(report.cursors['entries'], hlcs.last); // 推进到最大 hlc

      // 二次同步无增量（游标语义）。
      final again = await a.engine.syncOnce();
      expect(again.pulled, 0);
      expect(again.applied, 0);
    });

    test('分区/断网：只降级报错不抛出，outbox 保持待发，恢复后清账（§6.1 原则 1）',
        () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));
      await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));

      h.backend.partition(a.deviceId);
      final report = await a.engine.syncOnce();
      expect(report.error, isA<SyncBackendException>());
      expect(report.acked, 0);
      expect(await a.pendingCount(), 2);
      expect(a.statuses.last.phase, SyncPhase.error);
      expect(a.statuses.last.error, isNotNull);

      // 恢复联网 → 同一轮清账、状态回 done。
      h.backend.restore(a.deviceId);
      final ok = await a.engine.syncOnce();
      expect(ok.error, isNull);
      expect(ok.acked, 2);
      expect(await a.pendingCount(), 0);
      expect(a.statuses.last.phase, SyncPhase.done);
    });

    test('LocalLoopbackBackend：无服务端缺省装配——push 全量 ack、pull 恒空（§6.1）',
        () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      final loopback = LocalLoopbackBackend();
      final engine = LocalSyncEngine(
        backend: loopback,
        outbox: a.outbox,
        store: a.store,
        deviceId: a.deviceId,
        clock: a.clock,
      );
      final e1 = a.nextUuid();
      final e2 = a.nextUuid();
      await a.writeEntryWithLines(a.makeEntry(id: e1));
      await a.writeEntryWithLines(a.makeEntry(id: e2));

      final report = await engine.syncOnce();
      expect(report.error, isNull);
      expect(report.acked, 2);
      expect(report.pulled, 0);
      expect(await a.pendingCount(), 0);
      // 权威 revision 回写业务行（loopback 本地 seq 递增，§6.2 写路径末步）。
      expect((await a.rawRow('entries', e1))!['revision'], 1);
      expect((await a.rawRow('entries', e2))!['revision'], 2);
    });
  });

  group('§6.5 矩阵 resolve 单测（纯仲裁逻辑）', () {
    test('LWW：hlc 大者胜；同刻不同节点 → 节点段大者胜（定宽全序）', () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final engine = h.device(0).engine;

      Future<domain.ConflictWinner> winnerOf(
        String localHlc,
        String remoteHlc,
      ) async =>
          (await engine.resolve(
            domain.SyncConflict(
              tableName: 'entries',
              rowId: 'r',
              conflictClass: domain.ConflictClass.entryLww,
              localHlc: localHlc,
              remoteHlc: remoteHlc,
              localPayload: '{}',
              remotePayload: '{}',
            ),
          ))
              .winner;

      expect(
        await winnerOf(hlcOf(1000, 0, kDeviceA), hlcOf(2000, 0, kDeviceB)),
        domain.ConflictWinner.remote,
      );
      expect(
        await winnerOf(hlcOf(3000, 5, kDeviceA), hlcOf(2000, 9, kDeviceB)),
        domain.ConflictWinner.local,
      );
      // 同物理同 counter：节点段大者胜（B > A，全序无平局）。
      expect(
        await winnerOf(hlcOf(1000, 7, kDeviceA), hlcOf(1000, 7, kDeviceB)),
        domain.ConflictWinner.remote,
      );
    });

    test('todo.done 只前进：并发 set/unset → set 胜；双 set 取大（§6.5 第 6 行）',
        () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final engine = h.device(0).engine;

      Future<Object?> mergedDoneAt(
        Map<String, Object?> local,
        Map<String, Object?> remote,
      ) async {
        final resolution = await engine.resolve(
          domain.SyncConflict(
            tableName: 'todos',
            rowId: 't1',
            conflictClass: domain.ConflictClass.todoDoneForward,
            localHlc: hlcOf(1000, 0, kDeviceA),
            remoteHlc: hlcOf(2000, 0, kDeviceB),
            localPayload: jsonEncode(local),
            remotePayload: jsonEncode(remote),
          ),
        );
        expect(resolution.winner, domain.ConflictWinner.merged);
        return (jsonDecode(resolution.mergedPayload!)
            as Map<String, Object?>)['done_at'];
      }

      // 并发 set/unset（远端 hlc 更新但未 set）：set 胜——勾选永不丢失。
      expect(
        await mergedDoneAt(
          <String, Object?>{'done_at': 1000},
          <String, Object?>{'done_at': null},
        ),
        1000,
      );
      // 并发 unset/set（远端 hlc 更旧但已 set）：set 胜——只前进。
      expect(
        await mergedDoneAt(
          <String, Object?>{'done_at': null},
          <String, Object?>{'done_at': 500},
        ),
        500,
      );
      // 双 set：取大者（完成时刻单调不减）。
      expect(
        await mergedDoneAt(
          <String, Object?>{'done_at': 1000},
          <String, Object?>{'done_at': 700},
        ),
        1000,
      );
    });

    test('墓碑：任一方为墓碑 → 删除胜出，与 hlc 新旧无关（§6.5 第 7 行）', () async {
      final h = await SyncHarness.open(deviceIds: [kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final engine = h.device(0).engine;

      Future<domain.ConflictWinner> tombWinner(
        Map<String, Object?> local,
        String localHlc,
        Map<String, Object?> remote,
        String remoteHlc,
      ) async =>
          (await engine.resolve(
            domain.SyncConflict(
              tableName: 'entries',
              rowId: 'r',
              conflictClass: domain.ConflictClass.tombstone,
              localHlc: localHlc,
              remoteHlc: remoteHlc,
              localPayload: jsonEncode(local),
              remotePayload: jsonEncode(remote),
            ),
          ))
              .winner;

      // 本地存活更新（hlc 更新）vs 远端墓碑（hlc 更旧）→ 删除胜出。
      expect(
        await tombWinner(
          <String, Object?>{'deleted_at': null},
          hlcOf(9000, 0, kDeviceA),
          <String, Object?>{'deleted_at': 123},
          hlcOf(1000, 0, kDeviceB),
        ),
        domain.ConflictWinner.remote,
      );
      // 本地墓碑（hlc 更旧）vs 远端存活更新（hlc 更新）→ 删除仍胜出。
      expect(
        await tombWinner(
          <String, Object?>{'deleted_at': 123},
          hlcOf(1000, 0, kDeviceA),
          <String, Object?>{'deleted_at': null},
          hlcOf(9000, 0, kDeviceB),
        ),
        domain.ConflictWinner.local,
      );
      // 双墓碑 → LWW 兜底。
      expect(
        await tombWinner(
          <String, Object?>{'deleted_at': 123},
          hlcOf(1000, 0, kDeviceA),
          <String, Object?>{'deleted_at': 456},
          hlcOf(2000, 0, kDeviceB),
        ),
        domain.ConflictWinner.remote,
      );
    });
  });
}
