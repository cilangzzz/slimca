/// OCR 文本行 → [ReceiptDraft] 字段抽取（纯 Dart、端侧执行，§3.7）。
///
/// 「识别」与「理解」分层：ML Kit/Vision 平台通道只负责取文本行（识别），
/// 字段理解（商户/合计/时间/明细）全部在本抽取器内以保守正则启发式完成
/// ——通道协议因此保持极简（textLines 进、ReceiptDraft 出），双平台共享
/// 同一理解逻辑，fixture 冒烟（FakeReceiptOcrAdapter.fromTextLines）也走
/// 同一真实路径。
///
/// 骨架纪律（W16）：抽取不到的字段一律 null + warnings，**不猜测**——
/// 金额错一分都是账目事故（§5.1 金额口径）。已知局限（remaining：真机
/// 验收后按真实小票样本迭代）：多行合计（关键词与金额分处两行）、抹零/
/// 负数优惠行、行尾纯数字的会员/单号噪声可能被误作明细、二维码区噪声。
library;

import 'package:core_domain/core_domain.dart' as dom;

import 'receipt_models.dart';

/// 合计行关键词——高优先级（实际支付额，优惠券/抹零场景与应付可能不同）。
const List<String> kReceiptTotalKeywordsHigh = <String>['实收', '实付'];

/// 合计行关键词——普通优先级。
const List<String> kReceiptTotalKeywords = <String>[
  '合计',
  '总计',
  '总额',
  '应付',
  '总金额',
];

/// 日期候选（yyyy-MM-dd / yyyy/MM/dd / yyyy.MM.dd / 2026年3月5日）。
final RegExp _kDatePattern =
    RegExp(r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?');

/// 时刻候选（HH:mm[:ss]，24 小时制）。
final RegExp _kTimePattern = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?');

/// 行内金额（¥/￥ 前缀可选、千分位可选；合计行取「带小数的首个匹配」，
/// 见 [_totalCandidate] 注）。
final RegExp _kMoneyPattern =
    RegExp(r'(?:[¥￥]\s*)?(\d{1,6}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?');

/// 行尾金额（明细行识别锚点：品名在前、金额贴行尾）。
final RegExp _kTrailingAmountPattern =
    RegExp(r'(?:[¥￥]\s*)?(\d{1,6}(?:,\d{3})*|\d+)(?:\.(\d{1,2}))?\s*$');

/// 数量后缀（x2 / ×2 / *2，紧贴行尾金额之前的品名尾部）。
final RegExp _kQuantityPattern = RegExp(r'[x×*]\s*(\d{1,3})\s*$');

/// 名称/商户行的非数字判定：至少含一个 CJK 表意文字或 ASCII 字母。
bool _hasLetterOrCjk(String line) => line.codeUnits.any((u) =>
    (u >= 0x4E00 && u <= 0x9FFF) ||
    (u >= 0x41 && u <= 0x5A) ||
    (u >= 0x61 && u <= 0x7A));

/// 数字字符占比（名称/商户行要求 < 50%——纯单号/金额行不是名称）。
double _digitRatio(String line) {
  if (line.isEmpty) {
    return 0;
  }
  final digits = line.codeUnits
      .where((u) => u >= 0x30 && u <= 0x39)
      .length;
  return digits / line.length;
}

/// OCR 文本行 → 草稿（商户/合计/时间/明细行 + OCR 全文 + 降档说明）。
///
/// 输入按阅读序（ML Kit textBlocks / Vision observations 的天然顺序）；
/// 空输入返回全空草稿（[ReceiptDraft.hasText]=false → 管线一级降级手填）。
ReceiptDraft extractReceiptFields(
  List<String> textLines, {
  int maxLineItems = kMaxReceiptLineItems,
}) {
  final warnings = <String>[];
  final lines = <String>[
    for (final raw in textLines)
      raw.trim().replaceAll('\t', ' '),
  ].where((line) => line.isNotEmpty).toList();
  if (lines.isEmpty) {
    return const ReceiptDraft();
  }
  final consumed = List<bool>.filled(lines.length, false);

  // ── ① 商户（首页启发式：第一条「像店名」的行）──
  String? merchant;
  for (var i = 0; i < lines.length; i++) {
    if (_looksLikeMerchant(lines[i])) {
      merchant = lines[i];
      consumed[i] = true;
      break;
    }
  }
  if (merchant == null) {
    warnings.add('商户名未识别（首页启发式未命中）');
  }

  // ── ② 小票时间（首个含日期的行；时间缺位时向后探测 2 行）──
  ReceiptDateTime? datetime;
  for (var i = 0; i < lines.length; i++) {
    if (consumed[i]) {
      continue;
    }
    final dt = _parseDateTimeLine(lines, i);
    if (dt != null) {
      datetime = dt;
      consumed[i] = true;
      break;
    }
  }
  if (datetime == null) {
    warnings.add('小票时间未识别（yyyy-MM-dd HH:mm 候选未命中）');
  }

  // ── ③ 合计（关键词行；实收/实付 优先于 合计/应付，同优先级取更靠后者）──
  final totalCandidates = <_TotalCandidate>[];
  for (var i = 0; i < lines.length; i++) {
    if (consumed[i]) {
      continue;
    }
    final candidate = _totalCandidate(lines[i]);
    if (candidate != null) {
      totalCandidates.add(_TotalCandidate(i, candidate.$1, candidate.$2, candidate.$3));
    }
  }
  int? totalMinor;
  if (totalCandidates.isEmpty) {
    warnings.add('合计金额未识别（合计/实收等关键词行未命中）');
  } else {
    totalCandidates.sort((a, b) {
      if (a.priority != b.priority) {
        return b.priority - a.priority; // 优先级高者胜
      }
      return b.lineIndex - a.lineIndex; // 同优先级取更靠后（实收在末尾）
    });
    final picked = totalCandidates.first;
    totalMinor = picked.amountMinor;
    consumed[picked.lineIndex] = true;
    final distinct = totalCandidates.map((c) => c.amountMinor).toSet();
    if (distinct.length > 1) {
      warnings.add(
          '合计候选不一致（${distinct.join('/')} 分），取「${picked.keyword}」行');
    }
  }

  // ── ④ 明细行（非消费行；行尾金额锚点）──
  final items = <ReceiptLineItem>[];
  var unrecognized = 0;
  for (var i = 0; i < lines.length; i++) {
    if (consumed[i]) {
      continue;
    }
    final item = _parseLineItem(lines[i]);
    if (item == null) {
      unrecognized++;
      continue;
    }
    if (items.length >= maxLineItems) {
      unrecognized++;
      continue;
    }
    items.add(item);
  }
  if (unrecognized > 0) {
    warnings.add('$unrecognized 行未能解析为明细（已丢弃，宁缺不猜）');
  }

  return ReceiptDraft(
    merchant: merchant,
    totalMinor: totalMinor,
    datetime: datetime,
    lineItems: List<ReceiptLineItem>.unmodifiable(items),
    rawText: lines.join('\n'),
    warnings: List<String>.unmodifiable(warnings),
  );
}

/// 商户行判定（首页启发式）：2-30 字、含字母/汉字、数字占比 <50%、非日期/
/// 时刻/合计行。
bool _looksLikeMerchant(String line) {
  if (line.length < 2 || line.length > 30) {
    return false;
  }
  if (_kDatePattern.hasMatch(line) || _kTimePattern.hasMatch(line)) {
    return false;
  }
  if (_totalKeywordOf(line) != null) {
    return false;
  }
  return _hasLetterOrCjk(line) && _digitRatio(line) < 0.5;
}

/// 行内合计关键词（高优先级命中即返回）。
String? _totalKeywordOf(String line) {
  for (final keyword in kReceiptTotalKeywordsHigh) {
    if (line.contains(keyword)) {
      return keyword;
    }
  }
  for (final keyword in kReceiptTotalKeywords) {
    if (line.contains(keyword)) {
      return keyword;
    }
  }
  return null;
}

/// 合计行候选金额：优先「带小数」的首个匹配（`合计 3 件 18.50` 的件数 3
/// 无小数被跳过；`实收 12.50（优惠 2.00）` 的首个小数即实收）；全行无小数
/// 则取首个匹配（`实收 18`）。无匹配返回 null（关键词行缺金额 → 非候选）。
(int, int, String)? _totalCandidate(String line) {
  final keyword = _totalKeywordOf(line);
  if (keyword == null) {
    return null;
  }
  final matches = _kMoneyPattern.allMatches(line).toList();
  if (matches.isEmpty) {
    return null;
  }
  final priority = kReceiptTotalKeywordsHigh.contains(keyword) ? 2 : 1;
  final decimals = matches
      .where((m) => (m.group(2) ?? '').isNotEmpty)
      .toList();
  final fen = _amountMatchToFen(decimals.isEmpty ? matches.first : decimals.first);
  if (fen == null) {
    return null;
  }
  return (fen, priority, keyword);
}

/// 小票时间解析：第 [index] 行含日期即取（同行找时刻，缺位向后探测 2 行）；
/// 非真实日期（如 2026-13-40）返回 null——不猜。
ReceiptDateTime? _parseDateTimeLine(List<String> lines, int index) {
  final dateMatch = _kDatePattern.firstMatch(lines[index]);
  if (dateMatch == null) {
    return null;
  }
  final y = int.parse(dateMatch.group(1)!);
  final m = int.parse(dateMatch.group(2)!);
  final d = int.parse(dateMatch.group(3)!);
  final rounded = DateTime(y, m, d);
  if (rounded.year != y || rounded.month != m || rounded.day != d) {
    return null; // DateTime 构造会归一化越界值——组件回读不一致即非法
  }
  final time = _timeFrom(lines[index]) ??
      _timeFrom(index + 1 < lines.length ? lines[index + 1] : '') ??
      _timeFrom(index + 2 < lines.length ? lines[index + 2] : '');
  return ReceiptDateTime(
    day: dom.formatCalendarDay(rounded),
    time: time,
  );
}

/// 行内时刻抽取（校验 0-23:0-59；非法返回 null——时刻缺失优于脏值）。
String? _timeFrom(String line) {
  final match = _kTimePattern.firstMatch(line);
  if (match == null) {
    return null;
  }
  final hh = int.parse(match.group(1)!);
  final mm = int.parse(match.group(2)!);
  if (hh > 23 || mm > 59) {
    return null;
  }
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// 明细行解析：行尾金额锚点 + 品名尾部数量后缀；品名必须含字母/汉字且
/// 数字占比 <50%（纯单号/金额行不是品名）。不合条件返回 null（调用方计数）。
ReceiptLineItem? _parseLineItem(String line) {
  if (_totalKeywordOf(line) != null || _kDatePattern.hasMatch(line)) {
    return null;
  }
  final amountMatch = _kTrailingAmountPattern.firstMatch(line);
  if (amountMatch == null) {
    return null;
  }
  final amountMinor = _amountMatchToFen(amountMatch);
  if (amountMinor == null) {
    return null;
  }

  var name = line
      .substring(0, amountMatch.start)
      .trim();
  double? quantity;
  final qtyMatch = _kQuantityPattern.firstMatch(name);
  if (qtyMatch != null) {
    final base = name.substring(0, qtyMatch.start).trim();
    if (base.isNotEmpty) {
      quantity = double.parse(qtyMatch.group(1)!);
      name = base;
    }
  }
  name = name.replaceAll(RegExp(r'^[¥￥:：,，、.\-—]+\s*'), '').trim();
  if (name.isEmpty || name.length > 30) {
    return null;
  }
  if (!_hasLetterOrCjk(name) || _digitRatio(name) >= 0.5) {
    return null;
  }
  return ReceiptLineItem(
    name: name,
    amountMinor: amountMinor,
    quantity: quantity,
  );
}

/// 金额匹配 → 分（§5.1 元→分逆运算；千分位剥离，两位小数上限，杜绝浮点）。
int? _amountMatchToFen(RegExpMatch match) {
  final yuanText = (match.group(1) ?? '').replaceAll(',', '');
  final yuan = int.tryParse(yuanText);
  if (yuan == null || yuan < 0) {
    return null;
  }
  final frac = match.group(2) ?? '';
  final fen = frac.isEmpty
      ? 0
      : (frac.length == 1 ? int.parse(frac) * 10 : int.parse(frac));
  return yuan * 100 + fen;
}

/// 金额文本 → 分（§5.1）：剥离 ¥/￥/逗号/空白后按 `整数[.1-2位小数]` 解析；
/// 非法返回 null（不猜）。供抽取器与测试/宿主共享同一元→分口径。
int? parseReceiptYuanToFen(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[¥￥,\s]'), '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) {
    return null;
  }
  return _amountMatchToFen(match);
}

/// 合计候选（内部载荷）：行号、金额（分）、优先级、命中关键词。
class _TotalCandidate {
  const _TotalCandidate(
    this.lineIndex,
    this.amountMinor,
    this.priority,
    this.keyword,
  );

  final int lineIndex;
  final int amountMinor;
  final int priority;
  final String keyword;
}
