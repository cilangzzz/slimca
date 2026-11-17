/// theme_profiles 仓库（§5.6⑳「主题包是一等同步实体，换设备主题跟随」、
/// §11.2 W16 主线「主题编辑器+6 主题包」）。
///
/// 写路径纪律（§6.2，与 core_db FoodItemsDao/SavingsGoalsDao 完全同口径）：
/// 业务行（theme_profiles）与行快照 **同一事务** 读回入队 sync_outbox——经
/// core_db [db.SyncOutboxWriter]（§5.6⑯「一切出网必经之路」；theme_profiles
/// 在其 §5.1 14 张真值表清单内，W1 冻结即含出网语义）。
///
/// 上移注记（W1 核对结论）：core_db 无 ThemeProfilesDao——W1 只建表并冻结
/// schema，主题域写路径当时无调用方；W16 在壳层 data 层补位本实现。建议
/// 下个迭代整体上移 core_db（与 FoodItemsDao 同纪律、同落点），壳层改为
/// provider 装配；本文件 API 面按 DAO 惯例设计，上移零改调用方。
///
/// 读路径：watchAll 响应式流（编辑器网格与自定义包跨设备到达，§10.1 Drift
/// reactive stream 直驱）。软删墓碑（§5.1 删除行、§6.5「墓碑拒绝复活」）：
/// 内置包（is_preset=true）不可删——语义护栏抛 [StateError]。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart';

/// theme_profiles 表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String kThemeProfilesTable = 'theme_profiles';

/// 种子输入（内置包幂等种子用；tokens 为编码后的 §5.6⑳ JSON 文本）。
class ThemeProfileSeedInput {
  const ThemeProfileSeedInput({
    required this.id,
    required this.name,
    required this.tokensJson,
    required this.motionLevel,
    required this.sort,
    this.isPreset = true,
  });

  /// 行 id（内置包恒定 preset_*；自定义包 UUIDv7）。
  final String id;

  /// 包名。
  final String name;

  /// 语义 token 集 JSON（§8.3「主题包 = JSON profile」）。
  final String tokensJson;

  /// 动效等级（off/reduced/full，§9.2 MotionLevel）。
  final String motionLevel;

  /// 排序。
  final int sort;

  /// 内置包不可删（§5.6⑳）。
  final bool isPreset;
}

/// theme_profiles 仓库（§5.6⑳；§6.2 写路径纪律见文件头）。
class DriftThemeProfileRepository {
  DriftThemeProfileRepository(this._db, {db.LocalWriteClock? clock})
      : _clock = clock ?? db.LocalWriteClock(_db),
        _outbox = db.SyncOutboxWriter(_db);

  final db.AppDatabase _db;
  final db.LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：业务行同事务读回快照入队。
  final db.SyncOutboxWriter _outbox;

  /// 全部未删主题包（响应式；编辑器网格数据源）。
  Stream<List<db.ThemeProfile>> watchAll() {
    return (_db.select(_db.themeProfiles)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sort),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<db.ThemeProfile?> byId(String id) => (_db.select(_db.themeProfiles)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 内置包幂等种子（§6.2：业务行 + outbox 同事务；已存在即跳过）。
  ///
  /// 两端独立种子产出同一 preset_* 行：内容恒定（包规格常量），同步层按 id
  /// upsert 收敛（§6.2 幂等键 = outbox.id、行 id 服务端唯一键）。
  Future<void> ensureSeeded(List<ThemeProfileSeedInput> inputs) async {
    await _db.transaction(() async {
      for (final ThemeProfileSeedInput input in inputs) {
        final existing = await (_db.select(_db.themeProfiles)
              ..where((t) => t.id.equals(input.id)))
            .getSingleOrNull();
        if (existing != null) {
          continue; // 幂等：种子行已存在不再发戳/入队。
        }
        final stamp = await _clock.next();
        await _db.into(_db.themeProfiles).insert(
              db.ThemeProfilesCompanion.insert(
                id: input.id,
                name: input.name,
                tokens: input.tokensJson,
                motionLevel: input.motionLevel,
                fontId: const Value(null),
                isPreset: input.isPreset,
                sort: input.sort,
                // §5.1 公共列：非空无默认列取裸值（FoodItemsDao 同款）。
                createdAt: stamp.updatedAtMs,
                updatedAt: stamp.updatedAtMs,
                hlc: stamp.hlc,
                revision: 1,
                deviceId: await _clock.deviceId(),
              ),
            );
        // §6.2 写路径纪律：行快照同事务入队 sync_outbox（§5.6⑯）。
        await _outbox.enqueueRow(kThemeProfilesTable, input.id);
      }
    });
  }

  /// 保存自定义主题包（§8.4「命名与同步：自定义包命名入库，随 theme_profiles
  /// 同步到所有设备」；§11.2 W16 编辑器保存往返）。
  ///
  /// id 应用层生成 UUIDv7（§5.1）；revision 本地起步 1（§5.1）；tokens 由
  /// 调用方编码（ui_kit `ThemeProfile.toTokensJson` → JSON 文本，§8.3「主题包
  /// = JSON profile」）。§6.2：同事务入队。
  Future<db.ThemeProfile> saveCustom({
    required String name,
    required String tokensJson,
    required String motionLevel,
    int sort = 100,
  }) async {
    final stamp = await _clock.next();
    final rowId = db.generateUuidV7();
    await _db.transaction(() async {
      await _db.into(_db.themeProfiles).insert(
            db.ThemeProfilesCompanion.insert(
              id: rowId,
              name: name,
              tokens: tokensJson,
              motionLevel: motionLevel,
              fontId: const Value(null),
              isPreset: false,
              sort: sort,
              createdAt: stamp.updatedAtMs,
              updatedAt: stamp.updatedAtMs,
              hlc: stamp.hlc,
              revision: 1,
              deviceId: await _clock.deviceId(),
            ),
          );
      await _outbox.enqueueRow(kThemeProfilesTable, rowId);
    });
    return (await byId(rowId))!;
  }

  /// 软删墓碑（§5.1 删除行）：自定义包可删；内置包不可删（§5.6⑳ is_preset）。
  ///
  /// 幂等：已墓碑行重复软删 no-op。§6.2：墓碑快照同事务入队——deleted_at
  /// 置位后经 [db.SyncOutboxWriter.enqueueRow] 自动以 delete 语义出网
  /// （§6.5「upsert 命中已删行拒绝复活」）。
  Future<void> softDelete(String id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.themeProfiles)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        return; // 幂等：行不存在视为已删。
      }
      if (row.isPreset) {
        throw StateError('内置主题包不可删（§5.6⑳ is_preset）：$id');
      }
      if (row.deletedAt != null) {
        return; // 已墓碑：幂等 no-op。
      }
      final stamp = await _clock.next();
      await (_db.update(_db.themeProfiles)..where((t) => t.id.equals(id)))
          .write(
        db.ThemeProfilesCompanion(
          deletedAt: Value(stamp.updatedAtMs),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      await _outbox.enqueueRow(kThemeProfilesTable, id);
    });
  }
}
