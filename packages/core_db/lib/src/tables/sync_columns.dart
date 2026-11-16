/// §5.1 通用约定（W1 随 schema v1 冻结）——所有同步真值表的公共列。
///
/// 14 张同步真值表（entries/entry_lines/food_items/ledgers/categories/budgets/
/// todos/fitness_sessions/fitness_plans/exercise_sets/savings_goals/
/// savings_contributions/corrections/theme_profiles）以 mixin 方式统一携带
/// 下列 7 列；本地件（day_summary/ai_parses/sync_outbox/sync_cursors/settings）
/// 与服务端为主件（devices/attachments）不携带——见文档 §5.1 表分组。
///
/// 注意：主键 `id`（UUIDv7，TEXT 存储，时间有序、天然同步友好）不在本 mixin
/// 内——每张表自行声明主键（day_summary/sync_cursors/settings 等主键形态不同）。
library;

import 'package:drift/drift.dart';

/// §5.1 公共列 mixin：混入 `on Table` 由 drift_dev 一并采集进建表 DDL。
mixin SyncColumns on Table {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  IntColumn get createdAt => integer()();

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  IntColumn get updatedAt => integer()();

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  IntColumn get deletedAt => integer().nullable()();

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  TextColumn get hlc => text()();

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  IntColumn get revision => integer()();

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  IntColumn get schemaVer => integer().withDefault(const Constant(1))();

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  TextColumn get deviceId => text()();
}
