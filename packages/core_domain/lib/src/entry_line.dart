/// 产出行（facet 行）实体与枚举（§2.1②、§5.2② entry_lines、§5.3 同步正确性）。
///
/// facet 拆行是差异化的物理落点（§2.1②）：热量行、金额行、消耗行各自
/// 独立变更、独立同步——手机改金额、平板改热量是两行各自的 hlc，
/// 多数同步冲突在数据结构层被消灭而非算法补丁（§5.3）。
/// 修正不删旧行：新增一行引用旧行（correction_of），历史永不改写。
library;

import 'common.dart';

/// 产出行类型（§5.2② type 列）。
enum LineType {
  /// 摄入行：amount=kcal，挂 food_items 菜品明细，带 confidence（§2.2）。
  calorie('calorie'),

  /// 消耗行：amount=kcal，来自 fitness_sessions（§2.2）。
  burn('burn'),

  /// 金额行：amount=分，挂 ledger/category，确认后不可变（§2.2、§6.5）。
  money('money');

  const LineType(this.wire);

  final String wire;

  static LineType fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 LineType: $value（§5.2②）'),
      );
}

/// 资金/热量方向（§5.2② direction 列）。
///
/// calorie=in；burn=out；money 按 expense=out / income=in。
enum LineDirection {
  income('in'),
  outcome('out');

  const LineDirection(this.wire);

  final String wire;

  static LineDirection fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 LineDirection: $value（§5.2②）'),
      );
}

/// 产出行状态（§5.2② status 列）。
enum LineStatus {
  active('active'),

  /// 被修正（correction_of 指向它的旧行，§5.2② correction_of 行）。
  superseded('superseded'),

  /// 作废。
  void_('void');

  const LineStatus(this.wire);

  final String wire;

  static LineStatus fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 LineStatus: $value（§5.2②）'),
      );
}

/// 产出行实体（§5.2② entry_lines）。
///
/// 校验边界：
/// - [amount] 非负；正负语义交给 [direction] 表达（money=分、kcal=整数，§5.1 金额行）；
/// - [confidence] ∈ [0,1]（AI 置信度，§5.2②、§2.3 三色点口径）；
/// - money 行确认后不可变，修改金额的唯一合法路径是新增 correction 行，
///   由仓库接口强制（`EntryLineRepository`，§3.4 金额不可变、§6.5 money 行）。
class EntryLine {
  final String id;

  /// → entries.id（FK，软删不级联物理删，§5.2②）。
  final String entryId;
  final LineType type;

  /// calorie/burn=kcal；money=分（§5.2② amount 行）。
  final int amount;
  final LineDirection direction;

  /// money 行必填，默认账本；kcal 行归集到内置 kcal 账本（§5.2②、§5.4④）。
  final String? ledgerId;

  /// money 行=消费分类；calorie 行可挂餐饮子类（§5.2②）。
  final String? categoryId;

  /// money 行，默认 `CNY`（§5.2②）。
  final String? currency;

  /// AI 置信度 0-1，AI 产出行必填（§5.2②）。
  final double? confidence;

  /// 行级明细引用 JSON：商户/支付方式/MET 参数/菜品数组摘要（§5.2②）。
  final String? payload;

  /// 指向被修正旧行 id；修正=新增行，旧行 status→superseded（§5.2②）。
  final String? correctionOf;
  final LineStatus status;

  /// 公共列（§5.1）。
  final SyncMeta meta;

  EntryLine({
    required this.id,
    required this.entryId,
    required this.type,
    required this.amount,
    required this.direction,
    this.ledgerId,
    this.categoryId,
    this.currency,
    this.confidence,
    this.payload,
    this.correctionOf,
    required this.status,
    required this.meta,
  }) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        '不允许负值，收支方向由 direction 表达（§5.2②）',
      );
    }
    final c = confidence;
    if (c != null && (c < 0 || c > 1)) {
      throw ArgumentError.value(c, 'confidence', '必须落在 [0,1]（§5.2②）');
    }
  }

  /// 金额行（money facet）。行级不可变性的强制点在仓库层：实现须结合
  /// 所属 Entry.status（confirmed/edited 后）拒绝原地改 amount，
  /// 修正一律走新增 correction 行（§3.4 金额不可变、§6.5 money 行）。
  bool get isMoneyLine => type == LineType.money;

  /// 行快照 JSON（§5.6⑯ payload 行快照）。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'entry_id': entryId,
        'type': type.wire,
        'amount': amount,
        'direction': direction.wire,
        'ledger_id': ledgerId,
        'category_id': categoryId,
        'currency': currency,
        'confidence': confidence,
        'payload': payload,
        'correction_of': correctionOf,
        'status': status.wire,
      }..addAll(meta.toRowJson());

  /// [toJson] 的逆运算。
  factory EntryLine.fromJson(Map<String, Object?> json) => EntryLine(
        id: json['id'] as String,
        entryId: json['entry_id'] as String,
        type: LineType.fromWire(json['type'] as String),
        amount: json['amount'] as int,
        direction: LineDirection.fromWire(json['direction'] as String),
        ledgerId: json['ledger_id'] as String?,
        categoryId: json['category_id'] as String?,
        currency: json['currency'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        payload: json['payload'] as String?,
        correctionOf: json['correction_of'] as String?,
        status: LineStatus.fromWire(json['status'] as String),
        meta: SyncMeta.fromRowJson(json),
      );

  /// 不可变更新。注意：实现层必须先用 [isMoneyLine] 结合所属 Entry.status
  /// 把关——已确认金额行的 amount 只能经修正链（新增行）变更（§6.5）。
  EntryLine copyWith({
    String? entryId,
    LineType? type,
    int? amount,
    LineDirection? direction,
    Object? ledgerId = _unchanged,
    Object? categoryId = _unchanged,
    Object? currency = _unchanged,
    Object? confidence = _unchanged,
    Object? payload = _unchanged,
    Object? correctionOf = _unchanged,
    LineStatus? status,
    SyncMeta? meta,
  }) =>
      EntryLine(
        id: id,
        entryId: entryId ?? this.entryId,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        ledgerId: identical(ledgerId, _unchanged)
            ? this.ledgerId
            : ledgerId as String?,
        categoryId: identical(categoryId, _unchanged)
            ? this.categoryId
            : categoryId as String?,
        currency: identical(currency, _unchanged)
            ? this.currency
            : currency as String?,
        confidence: identical(confidence, _unchanged)
            ? this.confidence
            : confidence as double?,
        payload: identical(payload, _unchanged)
            ? this.payload
            : payload as String?,
        correctionOf: identical(correctionOf, _unchanged)
            ? this.correctionOf
            : correctionOf as String?,
        status: status ?? this.status,
        meta: meta ?? this.meta,
      );

  bool get isDeleted => meta.deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EntryLine && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EntryLine($id, ${type.wire}, $amount, ${direction.wire})';

  static const Object _unchanged = Object();
}
