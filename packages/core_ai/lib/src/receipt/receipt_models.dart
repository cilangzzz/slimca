/// 端侧小票 OCR 数据模型（§11.2 W16 主线「端侧小票 OCR」、§10.1 OCR 行
/// 「ML Kit（Android）/ Vision（iOS）端侧——不传原图（对比云端 OCR 隐私
/// 劣势）」、§3.7 本地优先/端侧优先）。
///
/// 数据流口径：
/// ```
/// 小票原图 [ReceiptImageInput]（即用即焚，不落存储不上云——§3.3 拍照通道
///   同款隐私纪律）
///   → [ReceiptOcrAdapter.recognize]（端侧平台通道，§3.7 OCR 全端侧）
///   → [ReceiptDraft]（商户/合计/时间/明细行；OCR 全文仅端侧内存流转）
///   → 结构化文本（receipt_text_bridge.dart，最小字段集上云）
///   → 既有 AiParser 文本管线（单边 money，§3.3 单边开关）
/// ```
/// 分层边界（§10.4）：本库只产出草稿与解析预填；entries/entry_lines 实体化、
/// source=receipt 标记（§5.2①）与落库由宿主 feature 层经 core_db 编排。
library;

import 'dart:typed_data';

/// 小票原图输入（[ReceiptOcrAdapter] 的输入口径；原图即用即焚——字节只在
/// 端侧内存流转，识别后即弃：不落 attachments 本地存储、不出网（§3.7
/// 「OCR 全端侧，不自动上云」））。
class ReceiptImageInput {
  const ReceiptImageInput({required this.bytes, required this.mime});

  /// 原图字节（相机/相册原始编码）。
  final Uint8List bytes;

  /// MIME 类型（如 `image/jpeg`、`image/png`；端侧识别引擎直接解码——
  /// 与拍照通道压缩机不同，小票通道不做统一重编码，文字保真优先于体积）。
  final String mime;
}

/// 小票时间（OCR 抽取结果；§5.1 本地日历日口径）。
class ReceiptDateTime {
  const ReceiptDateTime({required this.day, this.time});

  /// 小票日期 `yyyy-MM-dd`（抽取器已过格式与真实日期校验；entries.date
  /// 预填候选，§5.2①）。
  final String day;

  /// 小票时刻 `HH:mm`（24 小时制零填充；null=小票只有日期，不猜时刻）。
  final String? time;

  /// entries.occurred_at 预填值（UTC 毫秒，§5.2①）：以 [tzOffsetMin]（录入
  /// 设备时区偏移，§5.1）把小票本地墙钟折算为 UTC——本地=UTC+offset，故
  /// UTC=本地−offset。时刻缺失或字段不可解析返回 null（不虚报精度，§7.1
  /// 红线同口径：宁可缺省不猜）。
  int? occurredAtMsUtc(int tzOffsetMin) {
    if (day.length < 10 || tzOffsetMin.abs() > 14 * 60) {
      return null;
    }
    final y = int.tryParse(day.substring(0, 4));
    final m = int.tryParse(day.substring(5, 7));
    final d = int.tryParse(day.substring(8, 10));
    if (y == null || m == null || d == null) {
      return null;
    }
    final t = time;
    if (t == null || t.length < 5) {
      // 只有日期没有时刻：occurred_at 属可空列（§5.2①），不猜整点。
      return null;
    }
    final hh = int.tryParse(t.substring(0, 2));
    final mm = int.tryParse(t.substring(3, 5));
    if (hh == null || mm == null || hh > 23 || mm > 59) {
      return null;
    }
    // 真实日历日/时刻双校验（§5.1 杜绝错日）：DateTime 构造会归一化越界值
    // （2026-03-00 → 2-28），组件回读不一致即非法——不猜。
    final rounded = DateTime.utc(y, m, d, hh, mm);
    if (rounded.year != y ||
        rounded.month != m ||
        rounded.day != d ||
        rounded.hour != hh ||
        rounded.minute != mm) {
      return null;
    }
    return rounded.millisecondsSinceEpoch - tzOffsetMin * 60000;
  }

  @override
  String toString() => time == null ? day : '$day $time';
}

/// 小票明细行（OCR 抽取结果：品名 + 行小计 + 可选数量；§5.1 金额=分）。
class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    this.amountMinor,
    this.quantity,
  });

  /// 商品名（中文优先）。
  final String name;

  /// 行小计（分，§5.1；null=该行未能解析出金额——骨架抽取器不猜）。
  final int? amountMinor;

  /// 数量（`x2`/`×2` 后缀；null=未识别）。
  final double? quantity;

  @override
  String toString() =>
      'ReceiptLineItem($name, ${amountMinor == null ? '?' : '$amountMinor 分'}'
      '${quantity == null ? '' : ', x$quantity'})';
}

/// 明细行抽取上限（防垃圾文本行爆炸；超出截断并记 warnings）。
const int kMaxReceiptLineItems = 30;

/// 小票 OCR 草稿（[ReceiptOcrAdapter] 的输出口径；W16 任务字段：
/// merchant/total/datetime/lineItems，另携 OCR 全文与抽取降档说明）。
class ReceiptDraft {
  const ReceiptDraft({
    this.merchant,
    this.totalMinor,
    this.datetime,
    this.lineItems = const [],
    this.rawText = '',
    this.warnings = const [],
  });

  /// 商户名（首页启发式抽取；null=未识别）。
  final String? merchant;

  /// 合计金额（分，§5.1；优先「实收/实付」行，null=未识别——宁缺不猜，
  /// 金额错一分都是账目事故）。
  final int? totalMinor;

  /// 小票时间（null=未识别）。
  final ReceiptDateTime? datetime;

  /// 明细行（≤[kMaxReceiptLineItems] 行；null 金额行允许保留——品名对
  /// 分类建议仍有价值）。
  final List<ReceiptLineItem> lineItems;

  /// OCR 全文（按阅读序拼接）。**仅端侧内存留存**：不进结构化文本、不落
  /// ai_parses、不上云（§3.7「不自动上云」）；宿主 debug 排查可自行打印。
  final String rawText;

  /// 字段抽取降档说明（人读中文；确认卡提示/排查用——「未识别即声明」，
  /// 与 §7.4 降级语义同一信任语言）。
  final List<String> warnings;

  /// 是否识别到任何文本（false=坏小票/非小票图，管线据此一级降级手填，§7.4；
  /// 空结果是适配器的正常返回而非异常——对称 ImageDishAdapter 空清单约定）。
  bool get hasText => rawText.trim().isNotEmpty;

  /// 是否抽取到任何可用预填字段（商户/合计/时间/明细任一非空）。
  bool get hasPrefillFields =>
      merchant != null ||
      totalMinor != null ||
      datetime != null ||
      lineItems.isNotEmpty;

  @override
  String toString() =>
      'ReceiptDraft($merchant, total=${totalMinor == null ? '?' : '$totalMinor 分'}, '
      '$datetime, items=${lineItems.length}, warnings=${warnings.length})';
}
