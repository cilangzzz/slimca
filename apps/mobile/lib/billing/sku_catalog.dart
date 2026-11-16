/// SKU 目录配置（§3.9 双轨定价、§12 开放问题 #7 SKU 表达、§12.3 定价验证）。
///
/// **定价锚（§3.9）**：买断 98–128 元——锚竞品一木记账 98 元（Pro 档）与
/// 钱迹 128 元（买断）；AI 订阅 12–18 元/月——AI 能力档（§12 开放问题 #7
/// 「价格用 SKU 表达」）。
///
/// **待实测复核（§12.3 定价验证实验 / 风险 #8）**：以下价格均为上线前
/// 锚点假设，须以内测转化率实测数据复核后定稿；真实商品 ID 待商店开发者
/// 账号创建后替换（占位 ID 仅用于 Fake 流与设置页展示）。
library;

import 'billing_service.dart';

/// 轨 1 · 买断 · 首发档（锚一木 98 元，§3.9；价格待实测复核）。
const Sku kSkuProLifetimeLaunch = Sku(
  id: 'slimca_pro_lifetime_launch',
  kind: SkuKind.buyout,
  title: 'Pro 买断（首发档）',
  priceMinor: 9800,
  currency: 'CNY',
  note: '一次性解锁完整功能 · 首发 98 元（锚一木）· 价格待实测复核（§12.3）',
);

/// 轨 1 · 买断 · 标准档（锚钱迹 128 元，§3.9；价格待实测复核）。
const Sku kSkuProLifetimeStandard = Sku(
  id: 'slimca_pro_lifetime_standard',
  kind: SkuKind.buyout,
  title: 'Pro 买断（标准档）',
  priceMinor: 12800,
  currency: 'CNY',
  note: '一次性解锁完整功能 · 标准档 128 元（锚钱迹）· 价格待实测复核（§12.3）',
);

/// 轨 2 · AI 订阅 · 基础档（12 元/月，§12 开放问题 #7；价格待实测复核）。
const Sku kSkuAiMonthlyBase = Sku(
  id: 'slimca_ai_monthly_base',
  kind: SkuKind.subscription,
  title: 'AI 能力订阅（基础档）',
  priceMinor: 1200,
  currency: 'CNY',
  billingPeriod: 'month',
  note: '月订阅解锁 AI 解析额度 · 12 元/月 · 价格待实测复核（§12.3）',
);

/// 轨 2 · AI 订阅 · 完整档（18 元/月，§12 开放问题 #7；价格待实测复核）。
const Sku kSkuAiMonthlyFull = Sku(
  id: 'slimca_ai_monthly_full',
  kind: SkuKind.subscription,
  title: 'AI 能力订阅（完整档）',
  priceMinor: 1800,
  currency: 'CNY',
  billingPeriod: 'month',
  note: '月订阅解锁完整 AI 能力 · 18 元/月 · 价格待实测复核（§12.3）',
);

/// W7-8 内置目录（§3.9 双轨各两档；真实商店目录接线后以此为准替换，
/// 商品 ID 占位待商店账号）。
const List<Sku> kSlimcaSkuCatalog = <Sku>[
  kSkuProLifetimeLaunch,
  kSkuProLifetimeStandard,
  kSkuAiMonthlyBase,
  kSkuAiMonthlyFull,
];
