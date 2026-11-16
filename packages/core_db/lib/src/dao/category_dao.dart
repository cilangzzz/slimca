/// CategoryDao + 内置分类 seed（§5.4⑤ 分类、§3.4 内置分类 P0）。
///
/// seed 语义（§3.4「内置分类 P0：20+ 中文分类（餐饮-早餐/正餐/外卖、交通、
/// 购物、居住、娱乐、医疗、教育、人情、储蓄等）+自定义」）：
/// - expense / income 两种 kind 并存（§5.4⑤ kind 行）；
/// - ledger_id NULL=全局分类（§5.4⑤，不绑定账本）；
/// - is_preset=1 内置不可删（§5.4⑤）；
/// - colorToken 引用 §8.2 语义 token 名而非裸色值（§5.4⑤ color_token 行）。
/// 幂等：按 (kind, name) 查缺补插，已有行不动。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'local_write_clock.dart';

/// 账本 DAO 同目录；本文件只管分类。
///
/// 内置分类清单（§3.4 文档点名 + 「等」字延展，共 22 条 ≥ 20）：
/// colorToken 取值必须落在 §8.2 语义 token 清单内（primary / kcalIn /
/// kcalOut / net / moneyIn / moneyOut / success / warn / danger）。
const List<_SeedCategory> _kPresetCategories = [
  // ── 支出（§3.4 点名清单）─────────────────────────────────────────
  _SeedCategory(name: '餐饮-早餐', kind: 'expense', icon: 'bakery_dining', colorToken: 'kcalIn'),
  _SeedCategory(name: '餐饮-正餐', kind: 'expense', icon: 'restaurant', colorToken: 'kcalIn'),
  _SeedCategory(name: '餐饮-外卖', kind: 'expense', icon: 'delivery_dining', colorToken: 'kcalIn'),
  _SeedCategory(name: '交通', kind: 'expense', icon: 'commute', colorToken: 'primary'),
  _SeedCategory(name: '购物', kind: 'expense', icon: 'shopping_bag', colorToken: 'moneyOut'),
  _SeedCategory(name: '居住', kind: 'expense', icon: 'home', colorToken: 'primary'),
  _SeedCategory(name: '娱乐', kind: 'expense', icon: 'sports_esports', colorToken: 'warn'),
  _SeedCategory(name: '医疗', kind: 'expense', icon: 'medical_services', colorToken: 'danger'),
  _SeedCategory(name: '教育', kind: 'expense', icon: 'school', colorToken: 'net'),
  _SeedCategory(name: '人情', kind: 'expense', icon: 'redeem', colorToken: 'warn'),
  _SeedCategory(name: '储蓄', kind: 'expense', icon: 'savings', colorToken: 'moneyIn'),
  // ── 支出（§3.4「等」延展）───────────────────────────────────────
  _SeedCategory(name: '通讯', kind: 'expense', icon: 'wifi', colorToken: 'primary'),
  _SeedCategory(name: '日用', kind: 'expense', icon: 'cleaning_services', colorToken: 'moneyOut'),
  _SeedCategory(name: '旅行', kind: 'expense', icon: 'flight_takeoff', colorToken: 'net'),
  _SeedCategory(name: '宠物', kind: 'expense', icon: 'pets', colorToken: 'success'),
  _SeedCategory(name: '其他支出', kind: 'expense', icon: 'more_horiz', colorToken: 'moneyOut'),
  // ── 收入（§5.4⑤ kind=income；文档未点名具体项，取常用中文集合）──
  _SeedCategory(name: '工资', kind: 'income', icon: 'work', colorToken: 'moneyIn'),
  _SeedCategory(name: '兼职', kind: 'income', icon: 'schedule', colorToken: 'moneyIn'),
  _SeedCategory(name: '理财', kind: 'income', icon: 'trending_up', colorToken: 'success'),
  _SeedCategory(name: '退款', kind: 'income', icon: 'replay', colorToken: 'moneyIn'),
  _SeedCategory(name: '红包', kind: 'income', icon: 'card_giftcard', colorToken: 'warn'),
  _SeedCategory(name: '其他收入', kind: 'income', icon: 'more_horiz', colorToken: 'moneyIn'),
];

/// 分类 DAO（§5.4⑤ categories）。
class CategoryDao {
  CategoryDao(this._db, {LocalWriteClock? clock})
      : _clock = clock ?? LocalWriteClock(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 内置分类 seed（空库首次打开由 [seedDefaultData] 调用）：缺哪条补哪条。
  Future<void> seedPresets() {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.categories)
            ..where((t) => t.isPreset.equals(true) & t.deletedAt.isNull()))
          .get();
      final have = existing.map((c) => '${c.kind}/${c.name}').toSet();
      for (var i = 0; i < _kPresetCategories.length; i++) {
        final preset = _kPresetCategories[i];
        if (have.contains('${preset.kind}/${preset.name}')) {
          continue;
        }
        // sort 取清单下标：跨 kind 全局有序、两次 seed 结果一致（幂等）。
        await _insert(preset, i);
      }
    });
  }

  Future<Category?> findById(String id) => (_db.select(_db.categories)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 全量未删分类，expense 在前（sort 次序稳定），供九宫格快选（§3.3）。
  Future<List<Category>> getAll() {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.kind),
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.get();
  }

  /// 按 kind 过滤的响应式分类列表（P0 分类九宫格数据源）。
  Stream<List<Category>> watchByKind(String kind) {
    final query = _db.select(_db.categories)
      ..where((t) => t.kind.equals(kind) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch();
  }

  Future<void> _insert(_SeedCategory seed, int sort) async {
    final stamp = await _clock.next();
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: generateUuidV7(),
            name: seed.name,
            icon: seed.icon,
            sort: sort,
            // ledger_id NULL=全局分类（§5.4⑤）。
            ledgerId: const Value(null),
            kind: seed.kind,
            colorToken: seed.colorToken,
            isPreset: true,
            // 非空无默认列在 Companion.insert 中取裸值（Value 只用于
            // 可空/带默认列，§5.1 公共列均为非空无默认）。
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            hlc: stamp.hlc,
            revision: 1,
            deviceId: await _clock.deviceId(),
          ),
        );
  }
}

/// seed 行的静态描述（业务列；公共列由 [LocalWriteClock] 统一发戳）。
class _SeedCategory {
  const _SeedCategory({
    required this.name,
    required this.kind,
    required this.icon,
    required this.colorToken,
  });

  final String name;
  final String kind;
  final String icon;
  final String colorToken;
}
