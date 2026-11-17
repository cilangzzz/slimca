/// RRULE v1 子集 + 提醒换算 + 存钱法格子推算的纯单元测试（§3.6 待办完整版
/// W13、§5.5⑩⑪⑫、§11.2 W13 主线）。
///
/// 无 IO、无 Flutter 依赖：日期口径全部固定（2026-02-08=周日，§5.1 本地
/// 日历日文本），不触真实通知/网络。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:feature_plan/feature_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造内存目标行（§5.5⑪；仅字段推算用，不落库）。
cdb.SavingsGoal _goal({
  required String method,
  required String rhythm,
  required String startedOn,
  int targetMinor = 100000,
}) =>
    cdb.SavingsGoal(
      id: 'goal-test',
      name: '测试目标',
      targetMinor: targetMinor,
      deadline: null,
      method: method,
      rhythm: rhythm,
      status: cdb.kSavingsGoalStatusActive,
      startedOn: startedOn,
      createdAt: 1,
      updatedAt: 1,
      deletedAt: null,
      hlc: '0001763251200000:000001:3F8A12C0B7D4',
      revision: 1,
      schemaVer: 1,
      deviceId: '3F8A12C0B7D4',
    );

void main() {
  group('TodoRepeatSpec ↔ RRULE 文本（§5.5⑩ repeat_rule）', () {
    test('四种档位构建 RFC5545 文本', () {
      expect(const TodoRepeatSpec.none().toRrule(), isNull);
      expect(const TodoRepeatSpec.daily().toRrule(), 'FREQ=DAILY;INTERVAL=1');
      expect(TodoRepeatSpec.weekly(1).toRrule(), 'FREQ=WEEKLY;INTERVAL=1;BYDAY=MO');
      expect(TodoRepeatSpec.weekly(7).toRrule(), 'FREQ=WEEKLY;INTERVAL=1;BYDAY=SU');
      expect(TodoRepeatSpec.monthly(15).toRrule(),
          'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15');
      expect(TodoRepeatSpec.everyNDays(3).toRrule(), 'FREQ=DAILY;INTERVAL=3');
    });

    test('解析回环（构建 → 解析 → 结构化）', () {
      for (final spec in [
        const TodoRepeatSpec.daily(),
        TodoRepeatSpec.weekly(3),
        TodoRepeatSpec.monthly(15),
        TodoRepeatSpec.everyNDays(3),
      ]) {
        expect(TodoRepeatSpec.fromRrule(spec.toRrule()), spec,
            reason: '${spec.toRrule()} 回环');
      }
    });

    test('防御解析（§7.4）：空/坏文本/未知 FREQ/坏键值 → null', () {
      expect(TodoRepeatSpec.fromRrule(null), isNull);
      expect(TodoRepeatSpec.fromRrule(''), isNull);
      expect(TodoRepeatSpec.fromRrule('FREQ=YEARLY'), isNull);
      expect(TodoRepeatSpec.fromRrule('FREQ=DAILY;INTERVAL=0'), isNull);
      expect(TodoRepeatSpec.fromRrule('FREQ=DAILY;BYDAY=XX'), isNull);
      expect(parseRrule('FREQ=MONTHLY;BYMONTHDAY=0'), isNull);
      // 远端扩展键（UNTIL/COUNT）忽略、基础子集仍可解析。
      expect(
        parseRrule('FREQ=DAILY;INTERVAL=2;UNTIL=20261231T000000Z;COUNT=5')
            ?.interval,
        2,
      );
    });

    test('展示摘要（§3.6 中文文案）', () {
      expect(const TodoRepeatSpec.daily().label, '每天');
      expect(TodoRepeatSpec.weekly(1).label, '每周一');
      expect(TodoRepeatSpec.monthly(15).label, '每月15日');
      expect(TodoRepeatSpec.everyNDays(3).label, '每3天');
      expect(const TodoRepeatSpec.none().label, '不重复');
    });
  });

  group('rruleOccursOn 查询时展开（anchor=DTSTART，§5.5⑩）', () {
    // 2026-02-08 是周日；2026-02-02/09/16 是周一。
    test('每天：锚点日及以后每日命中，锚点前不命中', () {
      final rule = parseRrule('FREQ=DAILY;INTERVAL=1')!;
      expect(
        rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-08'),
        isTrue,
        reason: '闭区间含锚点日（首例即当日）',
      );
      expect(
        rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-09'),
        isTrue,
      );
      expect(
        rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-07'),
        isFalse,
        reason: 'day < anchor 不展开',
      );
    });

    test('每 3 天（自定义间隔）：锚点日、+3、+6 命中，+1/+2 不命中', () {
      final rule = parseRrule('FREQ=DAILY;INTERVAL=3')!;
      expect(
          rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-08'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-11'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-14'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-09'),
          isFalse);
      expect(
          rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: '2026-02-10'),
          isFalse);
    });

    test('每周一（BYDAY）：命中周一、不命中周二，锚点前不命中', () {
      final rule = parseRrule('FREQ=WEEKLY;INTERVAL=1;BYDAY=MO')!;
      expect(
          rruleOccursOn(anchorDay: '2026-02-02', rule: rule, day: '2026-02-09'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-02-02', rule: rule, day: '2026-02-10'),
          isFalse);
      expect(
          rruleOccursOn(anchorDay: '2026-02-09', rule: rule, day: '2026-02-02'),
          isFalse,
          reason: '锚点前的周一不展开（DTSTART 下界）');
    });

    test('每月 15 日（BYMONTHDAY）：命中 15 日；小月无该日自然跳过', () {
      final rule = parseRrule('FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=15')!;
      expect(
          rruleOccursOn(anchorDay: '2026-01-15', rule: rule, day: '2026-02-15'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-01-15', rule: rule, day: '2026-02-16'),
          isFalse);
    });

    test('每月 31 日：1/31、3/31 命中，2 月（28 天）跳过', () {
      final rule = parseRrule('FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=31')!;
      expect(
          rruleOccursOn(anchorDay: '2026-01-31', rule: rule, day: '2026-03-31'),
          isTrue);
      expect(
          rruleOccursOn(anchorDay: '2026-01-31', rule: rule, day: '2026-02-28'),
          isFalse);
    });

    test('坏日期/坏规则防御：不展开、不抛错（§7.4）', () {
      final rule = parseRrule('FREQ=DAILY;INTERVAL=1')!;
      expect(
        rruleOccursOn(anchorDay: 'bad', rule: rule, day: '2026-02-08'),
        isFalse,
      );
      expect(
        rruleOccursOn(anchorDay: '2026-02-08', rule: rule, day: 'not-a-day'),
        isFalse,
      );
    });

    test('dayDiff：跨月/同日/次差一天（DST 安全整日差）', () {
      expect(dayDiff('2026-02-08', '2026-02-08'), 0);
      expect(dayDiff('2026-02-08', '2026-02-09'), 1);
      expect(dayDiff('2026-01-31', '2026-03-01'), 29);
    });
  });

  group('提醒时刻换算（§5.5⑩ remind_at，UTC ms 存储）', () {
    test('计划日 + 时:分 → UTC ms → 本地时:分回环', () {
      final ms = remindAtMsFor(day: '2026-02-08', hour: 9, minute: 5);
      final unpacked = localTimeOfDay(ms);
      expect(unpacked.hour, 9);
      expect(unpacked.minute, 5);
      expect(formatTimeOfDay(hour: 9, minute: 5), '09:05');
      expect(formatTimeOfDay(hour: 23, minute: 0), '23:00');
    });
  });

  group('存钱法格子推算 savingsLadderStep（§3.6 投币打卡）', () {
    // 起始日 2026-02-08（周日）。
    test('365 天挑战：第 N 天 = N×基数；未开跑/坏 rhythm → null', () {
      final goal = _goal(
        method: cdb.kSavingsMethodDaily365,
        rhythm: '{"kind":"daily365","unit_minor":100}',
        startedOn: '2026-02-08',
      );
      final day1 = savingsLadderStep(goal: goal, day: '2026-02-08')!;
      expect(day1.amountMinor, 100);
      expect(day1.slot, 1);
      expect(day1.label, '第1天');
      final day7 = savingsLadderStep(goal: goal, day: '2026-02-14')!;
      expect(day7.amountMinor, 700);
      expect(day7.slot, 7);
      // 未开跑（day < started_on）。
      expect(savingsLadderStep(goal: goal, day: '2026-02-07'), isNull);
      // 坏 rhythm（§7.4）。
      expect(
        savingsLadderStep(
          goal: _goal(
            method: cdb.kSavingsMethodDaily365,
            rhythm: 'not-json',
            startedOn: '2026-02-08',
          ),
          day: '2026-02-08',
        ),
        isNull,
      );
    });

    test('52 周挑战：第 N 周 = N×基数（整 7 天推进，同周同格）', () {
      final goal = _goal(
        method: cdb.kSavingsMethodWeek52,
        rhythm: '{"kind":"week52","unit_minor":1000}',
        startedOn: '2026-02-08',
      );
      final week1 = savingsLadderStep(goal: goal, day: '2026-02-08')!;
      expect(week1.slot, 1);
      expect(week1.amountMinor, 1000);
      // 起始周内（+6 天）仍是第 1 周。
      final stillWeek1 = savingsLadderStep(goal: goal, day: '2026-02-14')!;
      expect(stillWeek1.slot, 1);
      // 第 2 周（+7 天）。
      final week2 = savingsLadderStep(goal: goal, day: '2026-02-15')!;
      expect(week2.slot, 2);
      expect(week2.amountMinor, 2000);
    });

    test('格子号越顶钳制到末格（挑战时长封顶）', () {
      final goal = _goal(
        method: cdb.kSavingsMethodWeek52,
        rhythm: '{"kind":"week52","unit_minor":1000}',
        startedOn: '2026-02-08',
      );
      final step = savingsLadderStep(goal: goal, day: '2027-12-01')!;
      expect(step.slot, 52);
      expect(step.amountMinor, 52000);
      expect(step.label, contains('已收官'));
    });

    test('自定义目标：每日固定额、slot=null', () {
      final goal = _goal(
        method: cdb.kSavingsMethodCustom,
        rhythm: '{"kind":"custom","daily_amount_minor":500}',
        startedOn: '2026-02-08',
      );
      final step = savingsLadderStep(goal: goal, day: '2026-02-08')!;
      expect(step.amountMinor, 500);
      expect(step.slot, isNull);
      expect(step.label, '每日存入');
    });
  });

  group('存钱法目标金额推导（SavingsGoalDraft，§3.6）', () {
    test('365 天挑战目标 = 基数×Σ(1..365)；52 周挑战 = 基数×Σ(1..52)', () {
      expect(
        SavingsGoalDraft.daily365(name: 'a', unitMinor: 100)
            .effectiveTargetMinor,
        6679500,
      );
      expect(
        SavingsGoalDraft.week52(name: 'a', unitMinor: 1000)
            .effectiveTargetMinor,
        1378000,
      );
      expect(
        SavingsGoalDraft.custom(
                name: 'a', targetMinor: 10000, dailyAmountMinor: 500)
            .effectiveTargetMinor,
        10000,
      );
    });

    test('rhythm JSON 形状约定（§5.5⑪ rhythm 列）', () {
      expect(
        SavingsGoalDraft.daily365(name: 'a', unitMinor: 100).rhythmJson(),
        '{"kind":"daily365","unit_minor":100}',
      );
      expect(
        SavingsGoalDraft.week52(name: 'a', unitMinor: 1000).rhythmJson(),
        '{"kind":"week52","unit_minor":1000}',
      );
      expect(
        SavingsGoalDraft.custom(
                name: 'a', targetMinor: 10000, dailyAmountMinor: 500)
            .rhythmJson(),
        '{"kind":"custom","daily_amount_minor":500}',
      );
    });
  });
}
