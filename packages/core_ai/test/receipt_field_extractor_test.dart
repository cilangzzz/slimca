/// 端侧字段抽取器测试（§11.2 W16 任务第 1 项；纯 Dart 启发式、离线确定）。
///
/// 骨架纪律断言口径：抽取不到的字段一律 null + warnings（不猜测）；
/// 金额元→分（§5.1）零浮点；日期必须是真实日历日（§5.1 杜绝错日）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'receipt_test_support.dart';

void main() {
  group('fixture 小票全字段抽取（kFixtureReceiptLines 基准）', () {
    test('商户/时间/合计/明细逐字段（W16 任务 ReceiptDraft 字段口径）', () {
      final draft = extractReceiptFields(kFixtureReceiptLines);

      expect(draft.merchant, '全家便利店');
      expect(draft.datetime!.day, '2026-03-05');
      expect(draft.datetime!.time, '12:31');
      expect(draft.totalMinor, 1250, reason: '实收 12.50 → 1250 分（§5.1）');
      expect(draft.lineItems.map((i) => i.name).toList(), ['可乐', '饭团']);
      expect(draft.lineItems[0].amountMinor, 350);
      expect(draft.lineItems[0].quantity, 1.0);
      expect(draft.lineItems[1].amountMinor, 900);
      expect(draft.lineItems[1].quantity, isNull);
      // OCR 全文按阅读序拼接（仅端侧留存）。
      expect(draft.rawText, kFixtureReceiptLines.join('\n'));
      // 唯一降档说明：会员噪声行不入明细。
      expect(draft.warnings, hasLength(1));
      expect(draft.warnings.single, contains('1 行未能解析为明细'));
      expect(draft.hasText, isTrue);
      expect(draft.hasPrefillFields, isTrue);
    });

    test('小票时间折算 UTC ms（§5.2① occurred_at 预填；UTC+8）', () {
      final draft = extractReceiptFields(kFixtureReceiptLines);
      // 本地 2026-03-05 12:31（UTC+8）→ UTC = 本地 − 480min。
      expect(
        draft.datetime!.occurredAtMsUtc(480),
        DateTime.utc(2026, 3, 5, 12, 31).millisecondsSinceEpoch - 480 * 60000,
      );
      // 只有日期没有时刻 → occurred_at null（可空列，不猜整点，§5.2①）。
      expect(ReceiptDateTime(day: '2026-03-05').occurredAtMsUtc(480), isNull);
      // 非法 day / 越界时区 → null（不猜）。
      expect(ReceiptDateTime(day: 'not-a-day').occurredAtMsUtc(480), isNull);
      expect(
        ReceiptDateTime(day: '2026-03-05', time: '12:31').occurredAtMsUtc(900),
        isNull,
        reason: '时区偏移越界（>14h）属脏输入，不猜',
      );
    });
  });

  group('合计抽取（金额口径 §5.1，实收/实付 优先）', () {
    test('实收优先于合计；候选不一致记 warnings', () {
      final draft = extractReceiptFields([
        '小卖部',
        '合计 18.00',
        '实收 17.50',
      ]);
      expect(draft.totalMinor, 1750, reason: '实收=实际支付额，优先于应付');
      expect(draft.warnings.join('；'), contains('合计候选不一致'));
      expect(draft.warnings.join('；'), contains('1750'));
    });

    test('无小数合计（实收 18 → 1800 分）与千分位（1,234.50 → 123450 分）', () {
      expect(extractReceiptFields(['小卖部', '实收 18']).totalMinor, 1800);
      expect(extractReceiptFields(['小卖部', '合计 1,234.50']).totalMinor,
          123450);
    });

    test('合计关键词行缺小数金额 → 行内数字如实被取（已知局限，确认卡可改）',
        () {
      final draft = extractReceiptFields(['小卖部', '合计票数 3']);
      expect(draft.totalMinor, 300,
          reason: '已知局限：行内数字被取作金额——骨架口径如实抽取，'
              '真机验收迭代（remaining）；确认卡可改');
      expect(draft.warnings.join('；'), isNot(contains('合计金额未识别')),
          reason: '命中关键词且有数字 → 非空候选，不报「未识别」');
    });

    test('全部无合计 → null + warning', () {
      final draft = extractReceiptFields(['小卖部', '可乐 3.50']);
      expect(draft.totalMinor, isNull);
      expect(draft.warnings.join('；'), contains('合计金额未识别'));
    });
  });

  group('小票时间抽取（§5.1 真实日历日）', () {
    test('日期格式变体：斜杠 / 年月日', () {
      expect(
        extractReceiptFields(['小卖部', '2026/03/05 12:31']).datetime!.day,
        '2026-03-05',
      );
      expect(
        extractReceiptFields(['小卖部', '2026年3月5日']).datetime!.day,
        '2026-03-05',
      );
    });

    test('时间在日期行下一行（多行小票常见排版）', () {
      final dt = extractReceiptFields(['小卖部', '2026-03-05', '12:31']).datetime;
      expect(dt, isNotNull);
      expect(dt!.time, '12:31');
    });

    test('非法日期（2026-13-40）→ null + warning（不猜）', () {
      final draft = extractReceiptFields(['小卖部', '2026-13-40 12:31']);
      expect(draft.datetime, isNull);
      expect(draft.warnings.join('；'), contains('小票时间未识别'));
    });

    test('非法时刻（25:99）→ day 保留、time 丢弃（不猜）', () {
      final dt = extractReceiptFields(['小卖部', '2026-03-05 25:99']).datetime;
      expect(dt, isNotNull);
      expect(dt!.day, '2026-03-05');
      expect(dt.time, isNull);
    });
  });

  group('明细行抽取', () {
    test('数量后缀 x2（元→分零浮点）', () {
      final draft = extractReceiptFields(['小卖部', '可乐 x2 7.00']);
      expect(draft.lineItems.single.name, '可乐');
      expect(draft.lineItems.single.amountMinor, 700);
      expect(draft.lineItems.single.quantity, 2.0);
    });

    test('明细行数上限（kMaxReceiptLineItems=30）+ 超限 warnings', () {
      final lines = <String>[
        '小卖部',
        '实收 40.00',
        for (var i = 1; i <= 35; i++) '果汁第$i瓶 1.00',
      ];
      final draft = extractReceiptFields(lines);
      expect(draft.lineItems, hasLength(kMaxReceiptLineItems));
      expect(draft.warnings.join('；'), contains('5 行未能解析为明细'));
    });
  });

  group('垃圾小票（降级手填口径，§7.4）', () {
    test('全噪声 → 无任何预填字段 + 逐项 warnings', () {
      final draft = extractReceiptFields(kGarbageReceiptLines);
      expect(draft.merchant, isNull);
      expect(draft.datetime, isNull);
      expect(draft.totalMinor, isNull);
      expect(draft.lineItems, isEmpty);
      expect(draft.hasText, isTrue, reason: 'OCR 有文本，仅字段理解全空');
      expect(draft.hasPrefillFields, isFalse);
      final warnings = draft.warnings.join('；');
      expect(warnings, contains('商户名未识别'));
      expect(warnings, contains('小票时间未识别'));
      expect(warnings, contains('合计金额未识别'));
      expect(warnings, contains('2 行未能解析为明细'));
    });

    test('空输入 → hasText=false（管线据此一级降级）', () {
      expect(extractReceiptFields(<String>[]).hasText, isFalse);
    });
  });

  group('parseReceiptYuanToFen（元→分 §5.1 口径单元）', () {
    test('合法变体', () {
      expect(parseReceiptYuanToFen('¥18.50'), 1850);
      expect(parseReceiptYuanToFen('￥ 18'), 1800);
      expect(parseReceiptYuanToFen('1,234.56'), 123456);
      expect(parseReceiptYuanToFen('18.5'), 1850);
      expect(parseReceiptYuanToFen('0.05'), 5);
    });

    test('非法/负数/超精度 → null（不猜）', () {
      expect(parseReceiptYuanToFen('18.555'), isNull);
      expect(parseReceiptYuanToFen('-3'), isNull);
      expect(parseReceiptYuanToFen('abc'), isNull);
      expect(parseReceiptYuanToFen(''), isNull);
    });
  });
}
