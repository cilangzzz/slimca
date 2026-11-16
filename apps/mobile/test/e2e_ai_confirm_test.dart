// E2E 专项验收（§11.1 W3-4 验收线：「打开 → 确认」AI 双解析闭环（文本路径））。
//
// 与 widget_test.dart（默认 FakeParser 冒烟）、e2e_record_to_dashboard_test.dart
// （W2 手动记一笔→仪表盘即时更新）互补，本用例按 W3-4 验收口径逐环断言：
// - FakeParser 注入（override aiParserProvider，确定性脚本桩，零真实网络）；
// - 文本「早餐两个包子 ¥6」→ 解析 → 确认卡出现，热量/金额 count-up 播完
//   后数值稳定（§9.3#4）；
// - 确认 → entries + calorie（500 kcal 类）+ money（600 分）行落库；
// - corrections 审计随确认落库（§5.6⑮：确认卡上改标题 → 字段级审计行）；
// - 仪表盘即时更新（唯一驱动=drift watch 流重发，§2.3 步 5/6）。
//
// 测试装配与既有 e2e 同一口径：内存 Drift 真库 + 固定 device_id 的 HlcClock
// 直接 override（不跑 bootstrap()）；内置账本种子 ensureDefaultLedgers 补齐
// （AI 网关落库依赖 money/kcal 内置账本 id，§5.4）。Windows 宿主缺 sqlite3
// 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/ai_parser.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 core_db test_support 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存真库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
Future<db.AppDatabase?> _tryOpenMemoryDatabase() async {
  final database = db.AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    if (_isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 注入式确定性 FakeParser（任务验收口径：FakeParser 注入，测试零真实网络）。
///
/// 「早餐两个包子 ¥6」→ 500 kcal（两个包子量级，§11.1 W3-4 验收「500kcal 类」）
/// + 600 分（¥6，§5.1 分存储）；行级置信度取 §7.2 示例同款 0.62/0.93
/// （黄/绿三色点各现一次，§7.3 口径）。同输入恒同结果，无随机/时钟/网络。
class _ScriptedFakeParser implements AiParser {
  const _ScriptedFakeParser();

  @override
  Future<AiParseResult> parse(AiParseRequest request) async => AiParseResult(
        title: request.input, // 标题=原句（与默认 FakeParser 同纪律，§2.3 步 3）
        kindHint: 'mixed',
        lines: <AiParsedLine>[
          const AiParsedLine(
            type: AiLineType.calorie,
            amount: 500,
            confidence: 0.62,
            categoryHint: '餐饮-早餐',
            items: [],
          ),
          const AiParsedLine(
            type: AiLineType.money,
            amount: 600,
            currency: 'CNY',
            confidence: 0.93,
            ledgerHint: 'default',
          ),
        ],
        parseNotes: '份量按两个包子估计；金额来自文本「¥6」',
        confidence: 0.62,
        provider: 'fake-scripted',
        model: 'e2e-deterministic-v1',
        promptVersion: 'e2e-v1',
        latencyMs: 0,
        costMicro: 0,
      );
}

void main() {
  testWidgets(
      'E2E：FakeParser 注入 → 「早餐两个包子 ¥6」→ 确认卡（count-up 后稳定）→ '
      '确认 → entry + calorie/money 行 + corrections 审计 + 仪表盘即时更新',
      (WidgetTester tester) async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，E2E 照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AI 确认闭环 E2E 未执行');
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3）+ 内置账本种子（§5.4：默认 money 账本 + kcal 账本）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          // FakeParser 注入（§11.1 W3-4 验收：默认 mock 路径的显式注入形态）。
          aiParserProvider.overrideWithValue(const _ScriptedFakeParser()),
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget);

    // ── 打开录入抽屉 → 一句话输入 → 解析（§3.3 步 2-3）──────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aiTextField')), findsOneWidget);
    expect(find.byKey(const Key('aiParseButton')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('aiTextField')),
      '早餐两个包子 ¥6',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('aiParseButton')));
    // 确认卡出现（§2.3 步 3「抽屉原地转确认卡」；解析为注入桩即时返回）。
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aiConfirmButton')), findsOneWidget);

    // ── count-up 稳定（§9.3#4：数值滚到终值后不再变化）──────────────
    // pumpAndSettle 已收敛全部单次动画；再推固定时长两次，断言终值不变。
    expect(find.text('500 kcal'), findsOneWidget, reason: '热量 count-up 终值');
    expect(find.text('¥6'), findsOneWidget, reason: '金额 count-up 终值（600 分）');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('500 kcal'), findsOneWidget, reason: 'count-up 已稳定');
    expect(find.text('¥6'), findsOneWidget, reason: 'count-up 已稳定');

    // ── 确认卡上修正标题（§2.3 步 4「先拍后改」→ corrections 审计行）──
    await tester.enterText(
      find.byKey(const Key('aiConfirmTitleField')),
      '早餐两个包子',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('aiConfirmButton')));
    await tester.pumpAndSettle(); // 确认落库 + 抽屉弹簧收起 + 明细流重发

    // 抽屉已收起：确认按钮不在树上（§2.3 步 5「卡片飞入仪表盘槽位」）。
    expect(find.byKey(const Key('aiConfirmButton')), findsNothing);

    // ── 仪表盘即时更新（唯一驱动=drift watch 流重发，§2.3 步 5/6）────
    // 今日记录卡新条目（确认标题）+ 摘要「摄入 500 kcal · ¥6」。
    expect(find.text('早餐两个包子'), findsOneWidget);
    expect(find.text('摄入 500 kcal · ¥6'), findsOneWidget);
    // 支出卡：¥0 → ¥6（600 分，§5.1 展示换算）。
    expect(find.text('¥0'), findsNothing, reason: '旧零值已被流重发改写');
    expect(find.text('¥6'), findsWidgets, reason: '支出卡即时更新（与摘要同源）');
    // 热量环卡：环心净 kcal 0 → 500；摄入指标行同步；消耗仍为 0。
    expect(find.text('摄入 0 kcal'), findsNothing, reason: '摄入指标已更新');
    expect(find.text('500 kcal'), findsOneWidget, reason: '摄入指标=500');
    expect(find.text('0 kcal'), findsNWidgets(2), reason: '消耗两处仍为 0');
    expect(find.text('500'), findsOneWidget, reason: '环心净 kcal=摄入 500');
    expect(find.text('0'), findsNothing, reason: '环心旧零值已更新');

    // ── 落库保真：entries 主干 + facet 拆行（§5.2/§5.3）──────────────
    final entries = await database.select(database.entries).get();
    expect(entries, hasLength(1), reason: '一笔事件一条 entries 主干');
    final entry = entries.single;
    expect(entry.title, '早餐两个包子', reason: '确认标题落库（§5.2①）');
    expect(entry.kind, 'mixed', reason: '热量+金额 → mixed（§5.2①）');
    expect(entry.source, 'text', reason: 'AI 文本通道（§5.2① source）');
    expect(entry.status, 'confirmed', reason: '确认落库（§5.2① status）');
    expect(entry.aiParseId, isNotNull, reason: 'ai_parses.id 溯源（§5.6⑭）');
    expect(entry.note, '份量按两个包子估计；金额来自文本「¥6」',
        reason: 'parse_notes → entries.note 追加（§7.3）');
    expect(entry.date, formatCalendarDay(DateTime.now()),
        reason: '归属日=抽屉唤起日（§3.2）');

    final lines = await (database.select(database.entryLines)
          ..where((t) => t.entryId.equals(entry.id)))
        .get();
    final kcalLines = lines.where((l) => l.type == 'calorie').toList();
    final moneyLines = lines.where((l) => l.type == 'money').toList();
    expect(kcalLines, hasLength(1), reason: 'calorie 行（§5.3 拆行）');
    expect(kcalLines.single.amount, 500, reason: 'W3-4 验收：500kcal 类');
    expect(kcalLines.single.direction, 'in', reason: 'calorie=in（§5.2②）');
    expect(kcalLines.single.confidence, 0.62,
        reason: 'AI 产出行必带置信度（§5.2②）');
    expect(moneyLines, hasLength(1), reason: 'money 行（§5.3 拆行）');
    expect(moneyLines.single.amount, 600, reason: 'W3-4 验收：600 分（¥6）');
    expect(moneyLines.single.direction, 'out', reason: '文本路径恒出账（§5.2②）');
    expect(moneyLines.single.currency, 'CNY');
    expect(moneyLines.single.confidence, 0.93);

    // ── ai_parses 留痕（§5.6⑭）─────────────────────────────────────
    final parses = await database.select(database.aiParses).get();
    expect(parses, hasLength(1));
    expect(parses.single.id, entry.aiParseId);
    expect(parses.single.inputKind, 'text');
    expect(parses.single.provider, 'fake-scripted');
    expect(parses.single.inputHash, isNotEmpty);

    // ── corrections 审计（§5.6⑮：改标题 → 字段级 append-only 一行）──
    // 热量/金额未改 → 不落审计（确认 ≠ 修正）；仅标题一处修正。
    final corrections = await database.select(database.corrections).get();
    expect(corrections, hasLength(1), reason: '仅标题一处修正（§5.6⑮）');
    final audit = corrections.single;
    expect(audit.entryId, entry.id);
    expect(audit.lineId, isNull, reason: '主干字段修正 line_id=NULL（§5.6⑮）');
    expect(audit.field, 'title');
    expect(audit.oldValue, '早餐两个包子 ¥6', reason: 'old_value=解析原值');
    expect(audit.newValue, '早餐两个包子', reason: 'new_value=用户确认值');
    expect(audit.source, 'user');
  });
}
