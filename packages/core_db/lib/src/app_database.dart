/// Slimca 本地数据库（Drift schema v1）。
///
/// §5.1：Drift schema v1 共 21 张表——同步真值表 14 张 + 本地件 5 张 +
/// 服务端为主 2 张。`schemaVersion` 只加不改，v1-v3 冻结期禁破坏性迁移
/// （§5.1/§6.4）。破坏性变更走「新表并存+双写过渡+全量重拉重建本地库」。
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/event_tables.dart';
import 'tables/infra_tables.dart';
import 'tables/ledger_tables.dart';
import 'tables/plan_tables.dart';

part 'app_database.g.dart';

/// 应用主库：聚合 schema v1 全部 21 张表。
///
/// 依赖注入友好：测试可传内存执行器
/// `AppDatabase(NativeDatabase.memory())`；生产走 [openConnection]
///（drift_flutter，按平台落 path_provider 目录）。
@DriftDatabase(tables: [
  // ── 同步真值表 14 张（§5.1 表分组）──────────────────────────────
  Entries, //          ① §5.2 事件主干
  EntryLines, //       ② §5.2 产出行（facet 行）
  FoodItems, //        ③ §5.2 菜品明细
  Ledgers, //          ④ §5.4 账本
  Categories, //       ⑤ §5.4 分类
  Budgets, //          ⑥ §5.4 预算
  Todos, //            ⑩ §5.5 待办
  FitnessSessions, //  ⑦ §5.5 健身会话
  FitnessPlans, //     ⑧ §5.5 健身计划（P1）
  ExerciseSets, //     ⑨ §5.5 组明细（P1 启用，W1 建表）
  SavingsGoals, //     ⑪ §5.5 存钱目标（P1）
  SavingsContributions, // ⑫ §5.5 存钱贡献（P1，append-only）
  Corrections, //      ⑮ §5.6 修正审计（append-only）
  ThemeProfiles, //    ⑳ §5.6 主题包（一等同步实体）
  // ── 本地件 5 张（永不同步）──────────────────────────────────────
  DaySummaries, //     ⑬ §5.6 当日聚合投影（表类名 DaySummaries，行类 DaySummary）
  AiParses, //         ⑭ §5.6 AI 留痕与缓存
  SyncOutbox, //       ⑯ §5.6 出网队列
  SyncCursors, //      ⑱ §5.6 拉取游标
  Settings, //         ⑲ §5.6 键值配置
  // ── 服务端为主 2 张（本地引用登记）──────────────────────────────
  Devices, //          ⑰ §5.6 设备注册
  Attachments, //      ㉑ §5.6 附件引用登记（P1）
])
class AppDatabase extends _$AppDatabase {
  /// 生产/测试通用构造：缺省时用 drift_flutter 打开平台目录下的 slimca.db。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  /// §5.1：schema v1 冻结；schemaVersion 只加不改。
  @override
  int get schemaVersion => 1;

  /// §5.1/§6.4：onCreate 一次性建全部 21 张表（含 §5.2 声明的索引）。
  ///
  /// 迁移注记：v1-v3 冻结期禁破坏性迁移；后续只加列（行级 schema_ver 前向
  /// 兼容），破坏性变更按「新表并存+双写+全量重拉重建」演进（§6.4）。
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          // 依赖 §5.2 显式声明的行间引用（entry_lines.entry_id FK）——
          // NativeDatabase 默认开启外键，这里显式打开作双保险。
          // 同步层注意：pull 需按父表→子表依赖序落库（§6.2 per-table 游标）；
          // 物理 GC（墓碑 90 天）需先删子行再删父墓碑（§5.1）。
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// 生产连接：drift_flutter 按平台选择目录（移动端 path_provider 应用文档
/// 目录），文件名固定 slimca.db（§10.1 数据层选型 Drift 2.x）。
QueryExecutor openConnection() => driftDatabase(name: 'slimca');
