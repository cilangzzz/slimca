/// 分类色 token → 具体颜色的运行时解析（§8.2 语义 token 纪律：categories
/// 只存 token 名（§5.4⑤ color_token），渲染时经 SlimcaTheme 解析，主题
/// 切换/明暗模式自动跟随，不落 hex）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 分类色 token 解析：返回 [SlimcaTheme] 中对应语义色；token 名不在
/// 白名单（kLedgerColorTokens）或为空时返回 null，由调用方回退到中性色。
Color? ledgerColorFromToken(SlimcaTheme tokens, String? tokenName) {
  return switch (tokenName) {
    'primary' => tokens.primary,
    'kcalIn' => tokens.kcalIn,
    'kcalOut' => tokens.kcalOut,
    'net' => tokens.net,
    'moneyIn' => tokens.moneyIn,
    'moneyOut' => tokens.moneyOut,
    'success' => tokens.success,
    'warn' => tokens.warn,
    'danger' => tokens.danger,
    _ => null,
  };
}
