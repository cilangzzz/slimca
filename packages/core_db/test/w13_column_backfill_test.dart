/// W13 v1 内补列回填测试（§6.4 只加列、schemaVersion 保持 1；§11.2 W13）。
///
/// 覆盖（todos.rrule_anchor_date / savings_contributions.source 两列）：
/// 1. 新库（onCreate createAll 已含两列）：回填 no-op，drift 生成查询可用；
/// 2. 旧形态库（按 §5.5⑩⑫ 冻结字段清单重建缺列表、放入存量行）：幂等补列、
///    存量行落默认值（source='manual' / rrule_anchor_date NULL）、drift 生成
///    查询可用、重跑幂等。
///
/// 与 attachments 即焚两列回填（attachments_dao_test）同一测试口径。
library;

import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('新库：两列回填 no-op、drift 生成查询可用、重跑幂等', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，W13 补列回填测试未执行');
      return;
    }
    try {
      // 新库（createAll 已含两列）：回填幂等 no-op。
      await backfillTodoRruleAnchorColumn(db);
      await backfillSavingsContributionSourceColumn(db);

      // 探针：生成查询含新列可直接落行（TodoDao 锚点缺省=计划日）。
      final todo = await TodoDao(db).create(
        title: '重复待办',
        date: '2026-02-08',
        repeatRule: 'FREQ=DAILY;INTERVAL=1',
      );
      expect(todo.rruleAnchorDate, '2026-02-08');

      await SavingsGoalsDao(db).create(
        name: '探针目标',
        targetMinor: 100,
        method: kSavingsMethodCustom,
        rhythm: '{}',
        id: 'bf-goal',
      );
      final contrib = await SavingsContributionsDao(db).append(
        goalId: 'bf-goal',
        amountMinor: 10,
        date: '2026-02-08',
        id: 'bf-contrib',
      );
      expect(contrib.source, kSavingsSourceManual, reason: '列默认 manual');

      // 幂等重跑：数据不动。
      await backfillTodoRruleAnchorColumn(db);
      await backfillSavingsContributionSourceColumn(db);
      expect((await TodoDao(db).findById(todo.id))!.rruleAnchorDate,
          '2026-02-08');
      expect(
        (await SavingsContributionsDao(db).findById('bf-contrib'))!.source,
        kSavingsSourceManual,
      );
    } finally {
      await db.close();
    }
  });

  test('旧形态库：缺列幂等补齐、存量行落默认值、drift 查询可用', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，W13 补列回填测试未执行');
      return;
    }
    try {
      // 模拟 v1 旧形态库：丢弃现表，按 §5.5⑩ 冻结字段清单（无
      // rrule_anchor_date）重建 todos 并放入存量行。
      await db.customStatement('DROP TABLE todos');
      await db.customStatement(
        'CREATE TABLE todos ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'title TEXT NOT NULL, '
        'note TEXT NULL, '
        'date TEXT NULL, '
        'done_at INTEGER NULL, '
        'due_at INTEGER NULL, '
        'repeat_rule TEXT NULL, '
        'remind_at INTEGER NULL, '
        'goal_link TEXT NULL, '
        'created_at INTEGER NOT NULL, '
        'updated_at INTEGER NOT NULL, '
        'deleted_at INTEGER NULL, '
        'hlc TEXT NOT NULL, '
        'revision INTEGER NOT NULL, '
        'schema_ver INTEGER NOT NULL, '
        'device_id TEXT NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO todos (id, title, note, date, done_at, due_at, "
        "repeat_rule, remind_at, goal_link, created_at, updated_at, "
        "deleted_at, hlc, revision, schema_ver, device_id) VALUES "
        "('legacy-todo', '旧待办', NULL, '2026-02-08', NULL, NULL, "
        "'FREQ=DAILY', NULL, NULL, 1, 1, NULL, "
        "'0001763251200000:000001:3F8A12C0B7D4', 1, 1, '3F8A12C0B7D4')",
      );

      // savings_contributions 同口径（无 source 列）。
      await db.customStatement('DROP TABLE savings_contributions');
      await db.customStatement(
        'CREATE TABLE savings_contributions ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'goal_id TEXT NOT NULL, '
        'date TEXT NOT NULL, '
        'amount_minor INTEGER NOT NULL, '
        'slot INTEGER NULL, '
        'note TEXT NULL, '
        'created_at INTEGER NOT NULL, '
        'updated_at INTEGER NOT NULL, '
        'deleted_at INTEGER NULL, '
        'hlc TEXT NOT NULL, '
        'revision INTEGER NOT NULL, '
        'schema_ver INTEGER NOT NULL, '
        'device_id TEXT NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO savings_contributions (id, goal_id, date, amount_minor, "
        "slot, note, created_at, updated_at, deleted_at, hlc, revision, "
        "schema_ver, device_id) VALUES ('legacy-contrib', 'legacy-goal', "
        "'2026-02-08', 500, 1, NULL, 1, 1, NULL, "
        "'0001763251200000:000002:3F8A12C0B7D4', 1, 1, '3F8A12C0B7D4')",
      );

      await backfillTodoRruleAnchorColumn(db);
      await backfillSavingsContributionSourceColumn(db);

      // 补列后 drift 生成查询可用：存量行 rrule_anchor_date NULL、source 落
      // 列默认值（SQLite ADD COLUMN DEFAULT 语义，§6.4 只加列）。
      final legacyTodo = await (db.select(db.todos)
            ..where((t) => t.id.equals('legacy-todo')))
          .getSingle();
      expect(legacyTodo.rruleAnchorDate, isNull);
      expect(legacyTodo.repeatRule, 'FREQ=DAILY', reason: '既有列不动');
      final legacyContrib = await (db.select(db.savingsContributions)
            ..where((t) => t.id.equals('legacy-contrib')))
          .getSingle();
      expect(legacyContrib.source, kSavingsSourceManual,
          reason: '补列默认值落位：存量贡献视为人工打卡');
      expect(legacyContrib.amountMinor, 500);
      expect(legacyContrib.deletedAt, isNull);

      // 幂等重跑：不报错、数据不动。
      await backfillTodoRruleAnchorColumn(db);
      await backfillSavingsContributionSourceColumn(db);
      expect((await db.select(db.todos).get()).length, 1);
      expect((await db.select(db.savingsContributions).get()).length, 1);
    } finally {
      await db.close();
    }
  });
}
