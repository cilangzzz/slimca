/// FoodItemsDao — 菜品明细 CRUD 与按 entry 查询（§5.2③ food_items）。
///
/// food_items 是 §5.1「同步真值表 14 张」之一（calorie 行子表，§7.3
/// 「items[] → food_items 逐菜品」），因此本 DAO 全部写路径遵守 §6.2 写路径
/// 纪律：业务行与行快照**同一事务**读回入队 sync_outbox（§5.6⑯）——W5-6
/// 补课后 food_items 与 todos/entries/entry_lines 同口径（feature_capture
/// 网关 submitAiCapture 的内联写入已按此纪律入队；本 DAO 把同一纪律固化为
/// core_db 一等写路径，供拍照通道（§11.2 W11-12）等调用方复用）。
///
/// user_adjusted 口径（§5.2③「用户是否改过（校准信号）」）：经本 DAO 的
/// updateDetails 属于用户写路径——任一营养事实字段（name/portion/kcal/
/// 宏量/ref 来源/置信度）发生真实变化即自动置 true；P2 校准闭环
/// （§5.6⑮ corrections→个性化系数）依赖该信号区分「AI 初值」与「用户改过」。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'local_write_clock.dart';
import 'sync_outbox_writer.dart';

/// 菜品明细 DAO（§5.2③）。
class FoodItemsDao {
  FoodItemsDao(this._db, {LocalWriteClock? clock})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：业务行同事务读回快照入队。
  final SyncOutboxWriter _outbox;

  /// 新建菜品明细行（§5.2③）：entry_id/line_id 为逻辑引用（无外键，
  /// pull 依赖序由同步层保证）——父行由调用方在同一上游事务内先落
  /// （§6.2 嵌套事务：本 DAO 的 transaction join 外层）。
  ///
  /// [id] 可注入（缺省本地生成 UUIDv7，§5.1）。§6.2 写路径纪律：业务行
  /// 与 outbox 行快照同事务提交（§5.6⑯）。
  Future<FoodItem> create({
    required String entryId,
    required String lineId,
    required String name,
    required double portionG,
    required int kcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    required String refSource,
    String? refId,
    required double confidence,
    bool userAdjusted = false,
    String? id,
  }) async {
    final stamp = await _clock.next();
    final rowId = id ?? generateUuidV7();
    await _db.transaction(() async {
      await _db.into(_db.foodItems).insert(
            FoodItemsCompanion.insert(
              id: rowId,
              entryId: entryId,
              lineId: lineId,
              name: name,
              portionG: portionG,
              kcal: kcal,
              proteinG: proteinG,
              carbG: carbG,
              fatG: fatG,
              refSource: refSource,
              refId: Value(refId),
              confidence: confidence,
              userAdjusted: userAdjusted,
              // §5.1 公共列：非空无默认列在 Companion.insert 中取裸值。
              createdAt: stamp.updatedAtMs,
              updatedAt: stamp.updatedAtMs,
              hlc: stamp.hlc,
              revision: 1,
              deviceId: await _clock.deviceId(),
            ),
          );
      // §6.2 写路径纪律：food_items 行快照同事务入队 sync_outbox（§5.6⑯）。
      await _outbox.enqueueRow('food_items', rowId);
    });
    return (await findById(rowId))!;
  }

  /// 更新营养事实字段（份量滑杆联动重算/名称点改/联查来源改写，§3.3）。
  ///
  /// 传 [_unchanged] 哨兵表示「不改动」；显式传 null 表示置空（仅 refId 可空）。
  /// - 任一事实字段真实变化 → user_adjusted 自动置 true（§5.2③ 校准信号）；
  ///   显式传 [userAdjusted] 时以其为准（修正闭环写路径的特殊口径）；
  /// - 无真实变化（事实未动、user_adjusted 目标值等于现值）→ no-op：不推
  ///   revision/hlc、不入队（与 §6.2「只对真实发生的真值行写入入队」同源，
  ///   避免 sync 噪声）；
  /// - §6.2：真实写入与行快照入队同事务（§5.6⑯）。
  Future<void> updateDetails({
    required String id,
    Object? name = _unchanged,
    Object? portionG = _unchanged,
    Object? kcal = _unchanged,
    Object? proteinG = _unchanged,
    Object? carbG = _unchanged,
    Object? fatG = _unchanged,
    Object? refSource = _unchanged,
    Object? refId = _unchanged,
    Object? confidence = _unchanged,
    Object? userAdjusted = _unchanged,
  }) {
    return _db.transaction(() async {
      final row = await (_db.select(_db.foodItems)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('updateDetails: food_items 无此行 $id（§5.2③）');
      }
      var changed = false;
      if (name != _unchanged && (name as String) != row.name) changed = true;
      // 数值事实统一 num 归一化（int 字面量/Dart 侧整型亦可）：滑杆/调用方
      // 传 num 均可，比较与落库以 double 口径（§5.2③ REAL 列）。
      if (portionG != _unchanged &&
          (portionG as num).toDouble() != row.portionG) {
        changed = true;
      }
      if (kcal != _unchanged && (kcal as num).toInt() != row.kcal) {
        changed = true;
      }
      if (proteinG != _unchanged &&
          (proteinG as num).toDouble() != row.proteinG) {
        changed = true;
      }
      if (carbG != _unchanged && (carbG as num).toDouble() != row.carbG) {
        changed = true;
      }
      if (fatG != _unchanged && (fatG as num).toDouble() != row.fatG) {
        changed = true;
      }
      if (refSource != _unchanged &&
          (refSource as String) != row.refSource) {
        changed = true;
      }
      if (refId != _unchanged && (refId as String?) != row.refId) {
        changed = true;
      }
      if (confidence != _unchanged &&
          (confidence as num).toDouble() != row.confidence) {
        changed = true;
      }
      // user_adjusted 目标值：显式参数 > 「有事实变化则 true」（§5.2③）。
      final targetAdjusted = userAdjusted == _unchanged
          ? (changed || row.userAdjusted)
          : userAdjusted as bool;
      if (!changed && targetAdjusted == row.userAdjusted) {
        return; // no-op：无真实写入不推版本、不入队（§6.2）
      }
      final stamp = await _clock.next();
      await (_db.update(_db.foodItems)..where((t) => t.id.equals(id))).write(
        FoodItemsCompanion(
          name: name == _unchanged ? const Value.absent() : Value(name as String),
          portionG: portionG == _unchanged
              ? const Value.absent()
              : Value((portionG as num).toDouble()),
          kcal:
              kcal == _unchanged ? const Value.absent() : Value((kcal as num).toInt()),
          proteinG: proteinG == _unchanged
              ? const Value.absent()
              : Value((proteinG as num).toDouble()),
          carbG: carbG == _unchanged
              ? const Value.absent()
              : Value((carbG as num).toDouble()),
          fatG:
              fatG == _unchanged ? const Value.absent() : Value((fatG as num).toDouble()),
          refSource: refSource == _unchanged
              ? const Value.absent()
              : Value(refSource as String),
          refId: refId == _unchanged
              ? const Value.absent()
              : Value(refId as String?),
          confidence: confidence == _unchanged
              ? const Value.absent()
              : Value((confidence as num).toDouble()),
          userAdjusted: Value(targetAdjusted),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2 写路径纪律：真实写入的行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('food_items', id);
    });
  }

  /// 软删墓碑（§5.1 删除行）：food_items 随 calorie 行/事件删除而墓碑化。
  ///
  /// 幂等：已墓碑行重复软删为 no-op（保留首次墓碑时刻，不入队）。
  Future<void> softDelete(String id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.foodItems)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('softDelete: food_items 无此行 $id（§5.1 删除行）');
      }
      if (row.deletedAt != null) {
        return; // 已墓碑：幂等 no-op（保留首次墓碑时刻）
      }
      final stamp = await _clock.next();
      await (_db.update(_db.foodItems)..where((t) => t.id.equals(id))).write(
        FoodItemsCompanion(
          deletedAt: Value(stamp.updatedAtMs),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2：墓碑写入同事务入队；读回快照携带 deleted_at → 自动以 delete
      // 语义出网（§5.6⑯/§6.5 墓碑拒绝复活）。
      await _outbox.enqueueRow('food_items', id);
    });
  }

  Future<FoodItem?> findById(String id) => (_db.select(_db.foodItems)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 按事件查询菜品明细（§5.2③ entry_id；确认卡/详情页的「这道菜」清单）。
  ///
  /// 排除行自身墓碑（业务清单不展示已删菜品）；同事件各行的菜品按创建序
  /// （created_at/hlc，与 entry_lines 查询同口径）。
  Future<List<FoodItem>> findByEntryId(String entryId) {
    return (_db.select(_db.foodItems)
          ..where((t) => t.entryId.equals(entryId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.hlc),
          ]))
        .get();
  }

  /// 按 calorie 行查询菜品明细（§5.2③ line_id：修正链/行级溯源视图）。
  Future<List<FoodItem>> findByLineId(String lineId) {
    return (_db.select(_db.foodItems)
          ..where((t) => t.lineId.equals(lineId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.hlc),
          ]))
        .get();
  }

  /// updateDetails 的「不改动」哨兵。
  static const Object _unchanged = Object();
}
