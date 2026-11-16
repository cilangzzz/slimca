/// 计费服务抽象与值对象（§3.9 双轨变现 W7-8 骨架、§10.4 壳层装配）。
///
/// **双轨口径（§3.9）**：轨 1 = Pro 买断（一次性解锁完整功能，98–128 元锚
/// 竞品一木/钱迹）；轨 2 = AI 能力订阅（月订阅解锁 AI 解析额度，12–18 元/月，
/// §12 开放问题 #7 SKU 表达）。
///
/// **W7-8 边界（任务口径）**：本层是可替换骨架——接口 + Fake 实现 + SKU 配置
/// + 设置页付费墙占位；真实 `in_app_purchase` 平台通道待商店开发者账号
/// （W8-9 灰度接线，届时换实现不动调用方）。
///
/// 价格口径：[Sku.priceMinor] 一律「分」（全项目金额口径，§3.4 金额以分
/// 存储）；具体价格标注「待实测复核」（§12.3 定价验证实验、风险 #8 价格
/// 上架前实测复核），上架前以商店后台配置为准。
library;

/// SKU 类型（§3.9 双轨）。
enum SkuKind {
  /// 买断（一次性购买，轨 1）。
  buyout,

  /// 订阅（周期扣款，轨 2）。
  subscription,
}

/// 单个 SKU 配置（§12 开放问题 #7：价格用 SKU 表达，档位叠加「待实测复核」）。
class Sku {
  const Sku({
    required this.id,
    required this.kind,
    required this.title,
    required this.priceMinor,
    required this.currency,
    this.billingPeriod,
    required this.note,
  });

  /// 产品 ID（占位：真实 ID 待商店开发者账号创建后替换，见 sku_catalog.dart）。
  final String id;

  /// 轨道类型（buyout / subscription，§3.9）。
  final SkuKind kind;

  /// 展示标题。
  final String title;

  /// 价格（分；§3.4 全项目金额以分存储的统一口径）。
  final int priceMinor;

  /// ISO 4217 货币码（CNY）。
  final String currency;

  /// 计费周期（订阅轨：'month'；买断轨 null）。
  final String? billingPeriod;

  /// 档位说明（定价锚与「待实测复核」标注随 SKU 展示，§12.3）。
  final String note;

  /// 展示价格文本（¥98.00 / ¥12.00/月；仅展示层格式化，存储永远用分）。
  String get priceLabel {
    final amountText = (priceMinor / 100).toStringAsFixed(2);
    return kind == SkuKind.subscription ? '¥$amountText/月' : '¥$amountText';
  }
}

/// 可售目录（queryProducts 的返回；[available]=商店通道是否就绪）。
class BillingCatalog {
  const BillingCatalog({required this.available, required this.products});

  /// 商店通道是否就绪（Fake 恒 true；真机未配置商店账号时为 false）。
  final bool available;

  /// 可售 SKU（价格/可用性以商店后台实测为准，§12.3）。
  final List<Sku> products;
}

/// 购买/恢复结果状态（映射商店回调的常见终态）。
enum PurchaseStatus {
  /// 进行中（pending 购买流，商店异步确认）。
  pending,

  /// 购买成功。
  purchased,

  /// 用户取消。
  canceled,

  /// 已拥有（重复购买买断）。
  alreadyOwned,

  /// 无可售/无历史购买。
  unavailable,

  /// 失败（支付失败/商店错误）。
  error,
}

/// 购买/恢复结果值对象。
class PurchaseResult {
  const PurchaseResult({required this.status, this.skuId, this.message});

  final PurchaseStatus status;

  /// 关联 SKU（成功/已拥有时携带）。
  final String? skuId;

  /// 面向用户的说明（内测 Fake 流提示等）。
  final String? message;
}

/// 计费服务抽象（§3.9 双轨；W7-8 骨架，真实商店通道 W8-9 接线）。
abstract interface class BillingService {
  /// 拉取可售 SKU（买断 + 订阅双轨目录）。
  Future<BillingCatalog> queryProducts();

  /// 发起购买（[skuId] 见 sku_catalog.dart；结果终态见 [PurchaseStatus]）。
  Future<PurchaseResult> purchase(String skuId);

  /// 恢复历史购买（换机/重装场景，商店口径）。
  Future<PurchaseResult> restore();
}
