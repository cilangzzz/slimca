/// 纯函数单元测试（无平台通道/无真实网络，§10.5）：金额/热量格式化与
/// 解析（§5.1 金额=分、kcal=整数）与月/日口径助手（§5.1 日期口径）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:feature_ledger/feature_ledger.dart';

void main() {
  group('LedgerFormat（§5.1 金额口径：分 → ¥两位小数，无 double）', () {
    test('moneyMinor 两位小数与千分位分组', () {
      expect(LedgerFormat.moneyMinor(1850), '¥18.50');
      expect(LedgerFormat.moneyMinor(400), '¥4.00');
      expect(LedgerFormat.moneyMinor(500000), '¥5,000.00');
      expect(LedgerFormat.moneyMinor(0), '¥0.00');
      expect(LedgerFormat.moneyMinor(-850), '-¥8.50');
    });

    test('signedMoneyMinor 收入加号、负数原样', () {
      expect(LedgerFormat.signedMoneyMinor(500000), '+¥5,000.00');
      expect(LedgerFormat.signedMoneyMinor(0), '¥0.00');
      expect(LedgerFormat.signedMoneyMinor(-850), '-¥8.50');
    });

    test('parseYuanToMinor 接受 10/10.5/10.50，拒绝非法与负数', () {
      expect(LedgerFormat.parseYuanToMinor('10'), 1000);
      expect(LedgerFormat.parseYuanToMinor('10.5'), 1050);
      expect(LedgerFormat.parseYuanToMinor('10.55'), 1055);
      expect(LedgerFormat.parseYuanToMinor(' 50 '), 5000);
      expect(LedgerFormat.parseYuanToMinor('¥10'), isNull);
      expect(LedgerFormat.parseYuanToMinor('10.555'), isNull);
      expect(LedgerFormat.parseYuanToMinor('-1'), isNull);
      expect(LedgerFormat.parseYuanToMinor(''), isNull);
      expect(LedgerFormat.parseYuanToMinor('abc'), isNull);
    });

    test('yuanInputText 与 parseYuanToMinor 互逆（对话框回填口径）', () {
      expect(LedgerFormat.yuanInputText(1000), '10');
      expect(LedgerFormat.yuanInputText(1050), '10.5');
      expect(LedgerFormat.yuanInputText(1055), '10.55');
      expect(
        LedgerFormat.parseYuanToMinor(LedgerFormat.yuanInputText(1234)),
        1234,
      );
    });

    test('parseKcal 仅接受 1-99999 整数', () {
      expect(LedgerFormat.parseKcal('2000'), 2000);
      expect(LedgerFormat.parseKcal(' 650 '), 650);
      expect(LedgerFormat.parseKcal('0'), isNull);
      expect(LedgerFormat.parseKcal('-1'), isNull);
      expect(LedgerFormat.parseKcal('100000'), isNull);
      expect(LedgerFormat.parseKcal('12.5'), isNull);
      expect(LedgerFormat.parseKcal(''), isNull);
    });

    test('kcal 文本口径', () {
      expect(LedgerFormat.kcal(650), '650 kcal');
      expect(LedgerFormat.kcal(0), '0 kcal');
    });
  });

  group('LedgerCalendar（§5.1 日期口径：yyyy-MM-dd / yyyy-MM 固定宽度）', () {
    test('monthPrefix 两位补零', () {
      expect(LedgerCalendar.monthPrefix(DateTime(2026, 11, 16)), '2026-11');
      expect(LedgerCalendar.monthPrefix(DateTime(2026, 3, 1)), '2026-03');
    });

    test('monthRange 半开区间 [月初, 次月初)，跨年安全', () {
      final ({String start, String end}) november =
          LedgerCalendar.monthRange('2026-11');
      expect(november.start, '2026-11-01');
      expect(november.end, '2026-12-01');
      final ({String start, String end}) december =
          LedgerCalendar.monthRange('2026-12');
      expect(december.start, '2026-12-01');
      expect(december.end, '2027-01-01');
      expect(
        () => LedgerCalendar.monthRange('2026-1'),
        throwsArgumentError,
        reason: '非 yyyy-MM 前缀破坏固定宽度字典序，必须硬失败（§5.1）',
      );
    });

    test('shiftMonth 平移并归位 1 号，跨年安全', () {
      expect(
        LedgerCalendar.monthPrefix(
          LedgerCalendar.shiftMonth(DateTime(2026, 11, 1), 1),
        ),
        '2026-12',
      );
      expect(
        LedgerCalendar.monthPrefix(
          LedgerCalendar.shiftMonth(DateTime(2026, 11, 1), -1),
        ),
        '2026-10',
      );
      expect(
        LedgerCalendar.monthPrefix(
          LedgerCalendar.shiftMonth(DateTime(2026, 12, 1), 1),
        ),
        '2027-01',
      );
      expect(
        LedgerCalendar.monthPrefix(
          LedgerCalendar.shiftMonth(DateTime(2026, 1, 1), -1),
        ),
        '2025-12',
      );
    });

    test('monthTitle 中文月标题', () {
      expect(LedgerCalendar.monthTitle(DateTime(2026, 11, 1)), '2026年11月');
    });

    test('dayGroupTitle 自然日 + 周几（2026-11-16 为周一）', () {
      expect(LedgerCalendar.dayGroupTitle('2026-11-16'), '11月16日 周一');
      expect(LedgerCalendar.dayGroupTitle('2026-11-18'), '11月18日 周三');
      expect(LedgerCalendar.dayGroupTitle('2026-11-20'), '11月20日 周五');
      expect(LedgerCalendar.dayGroupTitle('2026-11-22'), '11月22日 周日');
    });

    test('dayGroupTitle/dayLabel 对脏数据原样返回（不抛异常影响整页）', () {
      expect(LedgerCalendar.dayGroupTitle('bad-date'), 'bad-date');
      expect(LedgerCalendar.dayLabel('bad-date'), 'bad-date');
      expect(LedgerCalendar.dayLabel('2026-11-16'), '11月16日');
    });

    test('normalize 归位自然日 0 点', () {
      final DateTime normalized = LedgerCalendar.normalize(
        DateTime(2026, 11, 16, 13, 30),
      );
      expect(normalized, DateTime(2026, 11, 16));
    });
  });

  group('parseBudgetSnapshot（§5.6⑬ budget_snapshot 双形态兼容）', () {
    test('daily 数组形态：逐项解析并按 kcalLedgerIds 判定口径', () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"daily":['
        '{"ledger_id":"lm","category_id":null,"amount":1000,"used":1850,"remaining":-850},'
        '{"ledger_id":"lk","category_id":null,"amount":2000,"used":650,"remaining":1350},'
        '{"ledger_id":"lm","category_id":"c1","amount":500,"used":300,"remaining":200}'
        ']}',
        daySpendMinor: 1850,
        dayNetKcal: 650,
        kcalLedgerIds: const <String>{'lk'},
      );
      expect(items.length, 3);
      expect(items[0].isKcal, false);
      expect(items[0].isOver, true);
      expect(items[1].isKcal, true);
      expect(items[1].isOver, false);
      expect(items[2].categoryId, 'c1');
      expect(items[2].isCategoryGoal, true);
    });

    test('平铺形态（feature_dashboard v1）：按当日投影值合成 used/remaining', () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"kcal_budget":2000,"spend_budget_minor":1000}',
        daySpendMinor: 1850,
        dayNetKcal: 650,
      );
      expect(items.length, 2);
      expect(items[0].isKcal, true);
      expect(items[0].amount, 2000);
      expect(items[0].used, 650);
      expect(items[0].remaining, 1350);
      expect(items[1].isKcal, false);
      expect(items[1].amount, 1000);
      expect(items[1].used, 1850);
      expect(items[1].remaining, -850);
    });

    test('空/坏 JSON/形态不符 → 空列表（简报退化为目标未设置提示）', () {
      expect(parseBudgetSnapshot(null, daySpendMinor: 0, dayNetKcal: 0), isEmpty);
      expect(parseBudgetSnapshot('', daySpendMinor: 0, dayNetKcal: 0), isEmpty);
      expect(
        parseBudgetSnapshot('not-json', daySpendMinor: 0, dayNetKcal: 0),
        isEmpty,
      );
      expect(
        parseBudgetSnapshot('[]', daySpendMinor: 0, dayNetKcal: 0),
        isEmpty,
        reason: '顶层非对象视为形态不符',
      );
    });

    test('used/remaining 缺失时按 amount-used 兜底、异常项跳过', () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"daily":['
        '{"ledger_id":"lm","category_id":null,"amount":1000,"used":600},'
        '{"ledger_id":"lm","category_id":null,"amount":"bad","used":1}'
        ']}',
        daySpendMinor: 600,
        dayNetKcal: 0,
      );
      expect(items.length, 1);
      expect(items[0].remaining, 400);
    });
  });

  group('分类色 token（§8.2 语义 token 白名单）', () {
    test('normalizeLedgerColorToken 白名单内原样、缺省 primary', () {
      expect(normalizeLedgerColorToken('warn'), 'warn');
      expect(normalizeLedgerColorToken(null), 'primary');
      expect(normalizeLedgerColorToken(''), 'primary');
      expect(
        normalizeLedgerColorToken('#FF0000'),
        'primary',
        reason: '裸色值不允许进库（§8.2）',
      );
    });

    test('白名单与 seed 色集一致（9 个语义 token）', () {
      expect(kLedgerColorTokens, hasLength(9));
      expect(kLedgerColorTokens, contains('primary'));
      expect(kLedgerColorTokens, contains('danger'));
    });
  });
}
