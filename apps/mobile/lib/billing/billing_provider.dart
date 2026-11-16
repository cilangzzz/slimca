/// 计费装配与 barrel（§10.4 壳负责装配；§3.9 双轨 W7-8 骨架）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_service.dart' show BillingService;
import 'fake_billing_service.dart';

export 'billing_service.dart'
    show
        BillingCatalog,
        BillingService,
        PurchaseResult,
        PurchaseStatus,
        Sku,
        SkuKind;
export 'fake_billing_service.dart' show FakeBillingService;
export 'sku_catalog.dart'
    show
        kSkuAiMonthlyBase,
        kSkuAiMonthlyFull,
        kSkuProLifetimeLaunch,
        kSkuProLifetimeStandard,
        kSlimcaSkuCatalog;

/// 计费服务注入点（§10.4 壳负责装配）。
///
/// W7-8 缺省 = [FakeBillingService]（内测 Fake 流）；真实 `in_app_purchase`
/// 平台通道待商店开发者账号后接线（W8-9 灰度），届时在此 override/替换。
/// 购买/恢复结果经调用方（设置页）以 SnackBar 反馈；付费漏斗埋点随 W8-9
/// 真实商店接线细化（§3.9 监控）。
final Provider<BillingService> billingServiceProvider = Provider<BillingService>(
  (ref) => FakeBillingService(),
);
