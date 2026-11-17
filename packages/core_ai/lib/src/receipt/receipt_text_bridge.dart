/// ReceiptDraft → 结构化文本桥（§11.2 W16 任务「ReceiptDraft→结构化文本→
/// 复用既有 AiParser 文本管线」）。
///
/// 上云最小化（§3.7「不自动上云」）：结构化文本只含商户/合计/小票时间/明细
/// **品名**（不含明细金额、不含 OCR 全文 [ReceiptDraft.rawText]）——原图与
/// 原文不出端，云端只见预填所需的最小字段集。
///
/// 文本形态（对既有 HeuristicFakeLlmAdapter 与真实 LLM 同构可解析）：
/// `在小票「全家便利店」消费 12.50 元；小票时间 2026-03-05 12:31；购买明细：可乐、饭团`
/// - 金额恰好出现一次（合计）——明细只列品名不带金额，杜绝真实 LLM 逐行
///   拆单（多条 money 行重复入账）的歧义；明细品名（≤[kReceiptTextItemCap]
///   条）供 category_hint 推断；
/// - 无合计金额时省略金额段——文本管线必然 emptyResult → 一级降级手填
///   （§7.4），不猜金额（宁可手填，金额错一分都是账目事故）。
library;

import 'package:core_domain/core_domain.dart' as dom;

import 'receipt_models.dart';

/// 结构化文本携带的明细品名上限（上云最小化口径）。
const int kReceiptTextItemCap = 10;

/// 把 [draft] 组装为结构化文本（进 AiParser 的 [ParseInput.rawText]）。
String buildReceiptStructuredText(ReceiptDraft draft) {
  final parts = <String>[];
  final merchant = draft.merchant;
  final head = merchant == null ? '在小票' : '在小票「$merchant」';
  final total = draft.totalMinor;
  if (total != null) {
    parts.add('$head消费 ${_fenToYuanText(total)} 元');
  } else {
    // 无金额：文本管线 emptyResult → 手填（§7.4）；商户/时间仍可手填预填。
    parts.add('$head消费');
  }
  final dt = draft.datetime;
  if (dt != null) {
    parts.add('小票时间 ${dt.day}${dt.time == null ? '' : ' ${dt.time}'}');
  }
  final names = <String>[
    for (final item in draft.lineItems)
      if (item.name.trim().isNotEmpty) item.name.trim(),
  ];
  if (names.isNotEmpty) {
    parts.add(
        '购买明细：${names.take(kReceiptTextItemCap).join('、')}'
        '${names.length > kReceiptTextItemCap ? ' 等 ${names.length} 项' : ''}');
  }
  return parts.join('；');
}

/// 日期预填（§5.2① entries.date 本地日历日）：小票日期合法 → 用小票日期；
/// 否则回退 [fallbackDate]（请求锚点日/今天）。不猜：小票日期非法（OCR 噪声）
/// 一律回退——错日比缺日更伤账目（§5.1「杜绝 UTC 错日」同一纪律）。
String resolveReceiptSuggestedDate(ReceiptDraft? draft, String fallbackDate) {
  final day = draft?.datetime?.day;
  if (day != null && dom.isValidCalendarDay(day)) {
    return day;
  }
  return fallbackDate;
}

/// 分 → 元文本（两位小数；§5.1 元→分的逆运算，供结构化文本使用）。
String _fenToYuanText(int minor) {
  final yuan = minor ~/ 100;
  final fen = minor % 100;
  return '$yuan.${fen.toString().padLeft(2, '0')}';
}
