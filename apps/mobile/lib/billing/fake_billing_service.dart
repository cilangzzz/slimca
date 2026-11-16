/// FakeBillingService — 内测/测试用计费实现（§3.9 双轨骨架 W7-8）。
///
/// 用途：
/// - 单元/契约测试（禁真实网络与商店通道，Fake 内存流）；
/// - 内测包的设置页付费墙占位（购买/恢复走内存假流，界面链路可验证）；
/// - 真实 `in_app_purchase` 接线（W8-9，待商店开发者账号）时整体替换，
///   调用方（设置页/权益判定）不动。
///
/// 行为：目录恒返回 kSlimcaSkuCatalog；购买成功即内存记 owned；重复购买
/// 买断返回 alreadyOwned；恢复=已有购买按序返回首个，否则 unavailable。
library;

import 'billing_service.dart';
import 'sku_catalog.dart';

/// Fake 计费服务（§10.4 壳装配口径：测试注入 Fake，禁真实网络）。
class FakeBillingService implements BillingService {
  FakeBillingService({List<Sku>? catalog, this.latency = Duration.zero})
      : _catalog = catalog ?? kSlimcaSkuCatalog;

  /// 可售目录（缺省 = 内置双轨四档）。
  final List<Sku> _catalog;

  /// 人为延迟（模拟商店回调异步性；缺省零延迟，测试用）。
  final Duration latency;

  final Set<String> _owned = <String>{};

  /// 下一次 purchase 强制失败（测试错误路径用）。
  bool failNextPurchase = false;

  /// 是否已拥有某 SKU（Fake 流的权益判定探针，测试断言用）。
  bool isOwned(String skuId) => _owned.contains(skuId);

  Future<PurchaseResult> _settle(PurchaseResult result) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    return result;
  }

  @override
  Future<BillingCatalog> queryProducts() async => BillingCatalog(
        available: true,
        products: List<Sku>.unmodifiable(_catalog),
      );

  @override
  Future<PurchaseResult> purchase(String skuId) async {
    if (!_catalog.any((sku) => sku.id == skuId)) {
      return _settle(PurchaseResult(
        status: PurchaseStatus.unavailable,
        message: '目录中不存在该 SKU',
      ));
    }
    if (failNextPurchase) {
      failNextPurchase = false;
      return _settle(PurchaseResult(
        status: PurchaseStatus.error,
        skuId: skuId,
        message: '支付失败（Fake 注入错误）',
      ));
    }
    if (_owned.contains(skuId)) {
      return _settle(PurchaseResult(
        status: PurchaseStatus.alreadyOwned,
        skuId: skuId,
        message: '已拥有该商品',
      ));
    }
    _owned.add(skuId);
    return _settle(PurchaseResult(
      status: PurchaseStatus.purchased,
      skuId: skuId,
      message: '购买成功',
    ));
  }

  @override
  Future<PurchaseResult> restore() async {
    if (_owned.isEmpty) {
      return _settle(PurchaseResult(
        status: PurchaseStatus.unavailable,
        message: '无历史购买',
      ));
    }
    return _settle(PurchaseResult(
      status: PurchaseStatus.purchased,
      skuId: _owned.first,
      message: '已恢复历史购买',
    ));
  }
}
