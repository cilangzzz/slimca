/// FakeBillingService 与 SKU 目录测试（§3.9 双轨变现骨架、§12 开放问题 #7
/// SKU 表达；§11.1 W7-8 任务「Fake billing 流」验收）。
///
/// 覆盖：双轨四档目录（买断 98/128 元 + AI 订阅 12/18 元/月，价格「待实测
/// 复核」§12.3）、购买成功/重复购买/注入失败/未知 SKU、恢复历史购买空与有、
/// 价格展示格式（分 → ¥xx.xx[/月]，存储口径永远用分 §3.4）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/billing/billing_provider.dart';

void main() {
  group('SKU 目录（§3.9 双轨定价锚）', () {
    test('双轨四档：买断两档 + AI 订阅两档，价格为「待实测复核」锚点', () {
      expect(kSlimcaSkuCatalog.length, 4);

      final buyouts = kSlimcaSkuCatalog
          .where((s) => s.kind == SkuKind.buyout)
          .toList();
      final subs = kSlimcaSkuCatalog
          .where((s) => s.kind == SkuKind.subscription)
          .toList();
      expect(buyouts.length, 2);
      expect(subs.length, 2);

      // 买断：98–128 元锚（一木 98 / 钱迹 128，§3.9）；分存储（§3.4）。
      expect(kSkuProLifetimeLaunch.priceMinor, 9800);
      expect(kSkuProLifetimeStandard.priceMinor, 12800);
      expect(kSkuProLifetimeLaunch.billingPeriod, isNull);

      // AI 订阅：12–18 元/月（§12 开放问题 #7）。
      expect(kSkuAiMonthlyBase.priceMinor, 1200);
      expect(kSkuAiMonthlyFull.priceMinor, 1800);
      expect(kSkuAiMonthlyBase.billingPeriod, 'month');
      expect(kSkuAiMonthlyFull.billingPeriod, 'month');

      // 「待实测复核」标注随 SKU 携带（§12.3 定价验证实验 / 风险 #8）。
      for (final sku in kSlimcaSkuCatalog) {
        expect(sku.note.contains('待实测复核'), isTrue);
      }
    });

    test('价格展示：分 → ¥xx.xx / ¥xx.xx/月（仅展示层格式化）', () {
      expect(kSkuProLifetimeLaunch.priceLabel, '¥98.00');
      expect(kSkuProLifetimeStandard.priceLabel, '¥128.00');
      expect(kSkuAiMonthlyBase.priceLabel, '¥12.00/月');
      expect(kSkuAiMonthlyFull.priceLabel, '¥18.00/月');
    });
  });

  group('FakeBillingService（内测/测试计费流，禁真实商店通道）', () {
    late FakeBillingService billing;

    setUp(() {
      billing = FakeBillingService();
    });

    test('queryProducts：目录完整、通道就绪', () async {
      final catalog = await billing.queryProducts();
      expect(catalog.available, isTrue);
      expect(catalog.products.length, 4);
      expect(catalog.products.map((s) => s.id), containsAll(<String>[
        kSkuProLifetimeLaunch.id,
        kSkuAiMonthlyFull.id,
      ]));
    });

    test('购买 → purchased 且记入已拥有', () async {
      final result = await billing.purchase(kSkuProLifetimeLaunch.id);
      expect(result.status, PurchaseStatus.purchased);
      expect(result.skuId, kSkuProLifetimeLaunch.id);
      expect(billing.isOwned(kSkuProLifetimeLaunch.id), isTrue);
    });

    test('重复购买 → alreadyOwned（买断幂等语义）', () async {
      await billing.purchase(kSkuProLifetimeLaunch.id);
      final again = await billing.purchase(kSkuProLifetimeLaunch.id);
      expect(again.status, PurchaseStatus.alreadyOwned);
    });

    test('failNextPurchase → error（错误路径注入）', () async {
      billing.failNextPurchase = true;
      final result = await billing.purchase(kSkuAiMonthlyBase.id);
      expect(result.status, PurchaseStatus.error);
      expect(billing.isOwned(kSkuAiMonthlyBase.id), isFalse,
          reason: '失败不产生所有权');
    });

    test('未知 SKU → unavailable', () async {
      final result = await billing.purchase('no_such_sku');
      expect(result.status, PurchaseStatus.unavailable);
    });

    test('恢复：无历史购买 → unavailable', () async {
      final result = await billing.restore();
      expect(result.status, PurchaseStatus.unavailable);
    });

    test('恢复：已有购买 → purchased 携带首个 skuId（换机/重装口径）', () async {
      await billing.purchase(kSkuAiMonthlyBase.id);
      final result = await billing.restore();
      expect(result.status, PurchaseStatus.purchased);
      expect(result.skuId, kSkuAiMonthlyBase.id);
    });

    test('provider 缺省装配 = FakeBillingService（W7-8 骨架；真实通道 W8-9）',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(billingServiceProvider), isA<FakeBillingService>());
    });
  });
}
