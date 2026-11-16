/// 分类解析（§7.3 字段映射表「category_hint → category_id」行）。
///
/// 职责：把 LLM 输出的 `category_hint` 文本对到内置分类（命中）或
/// 「其他 + 建议新建」（未命中）。core_ai 只做**名字域**解析；id 映射由
/// 宿主注入（从 core_db categories 表装载 name→id），避免复制内置分类的
/// id——id 由 core_db seed 生成（§5.4⑤），运行期唯一真值在数据库。
library;

/// 内置分类名清单（§3.4「20+ 中文分类」口径；与 core_db
/// `default_seed.dart` 的 `_kPresetCategories` 同名单——名单以数据库 seed
/// 为运行期真值，宿主应优先从表装载注入 [PresetCategoryResolver.nameToId]）。
const List<String> kDefaultPresetCategoryNames = <String>[
  '餐饮-早餐',
  '餐饮-正餐',
  '餐饮-外卖',
  '交通',
  '购物',
  '居住',
  '娱乐',
  '医疗',
  '教育',
  '人情',
  '储蓄',
  '通讯',
  '日用',
  '旅行',
  '宠物',
  '其他支出',
  '工资',
  '兼职',
  '理财',
  '退款',
  '红包',
  '其他收入',
];

/// 单个 category_hint 的解析结论。
class CategoryResolution {
  const CategoryResolution({
    this.categoryId,
    this.categoryName,
    this.matched = false,
    this.suggestNew = false,
  });

  /// 解析出的分类 id（仅宿主注入了 name→id 映射时非空）。
  final String? categoryId;

  /// 规范化后的分类名（别名归一后；确认卡展示用）。
  final String? categoryName;

  /// 是否命中内置分类。
  final bool matched;

  /// 未命中 → 建议新建（§7.3「未命中挂『其他』并建议新建」）；
  /// 挂靠哪个「其他」分类由宿主决定（[PresetCategoryResolver.fallbackCategoryId]）。
  final bool suggestNew;
}

/// 分类解析器抽象（§7.3 category_hint → category_id）。
abstract interface class CategoryResolver {
  /// 内置分类名清单（提示词枚举注入，§7.2 硬规则 4）。
  Iterable<String> get knownCategoryNames;

  /// 解析 [categoryHint]（null/空白 = 无分类建议）。
  CategoryResolution resolve(String? categoryHint);
}

/// 内置名单解析器（缺省实现）。
///
/// - 命中判定：先过 [aliases] 别名归一，再查 [nameToId]（宿主装载的
///   实时名单）；未注入映射时退回 [kDefaultPresetCategoryNames] 名单；
/// - 未命中：[suggestNew]=true，[categoryId] 给 [fallbackCategoryId]
///   （「其他」分类 id，宿主注入；null 时由宿主自行挂靠）。
class PresetCategoryResolver implements CategoryResolver {
  const PresetCategoryResolver({
    this.nameToId = const {},
    this.aliases = const {},
    this.fallbackCategoryId,
  });

  /// 分类名 → 分类 id（宿主从 core_db categories 表装载）。
  final Map<String, String> nameToId;

  /// 别名 → 规范名（如 '吃饭' → '餐饮-正餐'；宿主按校准数据配置）。
  final Map<String, String> aliases;

  /// 内置「其他」分类 id（未命中挂靠，§7.3；缺省 null）。
  final String? fallbackCategoryId;

  @override
  Iterable<String> get knownCategoryNames =>
      nameToId.isEmpty ? kDefaultPresetCategoryNames : nameToId.keys;

  @override
  CategoryResolution resolve(String? categoryHint) {
    final hint = categoryHint?.trim();
    if (hint == null || hint.isEmpty) {
      // 无提示：不产生分类建议（行落库 categoryId=null，由宿主处理）。
      return const CategoryResolution();
    }
    final canonical = aliases[hint] ?? hint;
    final id = nameToId[canonical];
    if (id != null) {
      return CategoryResolution(
        categoryId: id,
        categoryName: canonical,
        matched: true,
      );
    }
    final inPreset =
        nameToId.isEmpty && kDefaultPresetCategoryNames.contains(canonical);
    if (inPreset) {
      // 命中名单但宿主未注入 id 映射：只回传规范名，id 由宿主二次映射。
      return CategoryResolution(categoryName: canonical, matched: true);
    }
    // 未命中内置分类 → 挂「其他」并建议新建（§7.3）。
    return CategoryResolution(
      categoryId: fallbackCategoryId,
      categoryName: canonical,
      matched: false,
      suggestNew: true,
    );
  }
}
