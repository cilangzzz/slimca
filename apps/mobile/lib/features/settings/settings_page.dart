/// 我的 Tab：设置页（§4.2：主题/同步状态/AI 开关/数据导出/订阅）。
///
/// W7-8 接入（§11.1）：
/// - **raw_input 上云开关**（§3.7 数据主权、§3.3 默认关=即用即焚）：
///   SwitchListTile 写回 RawInputPolicy 运行期持有 + settings 表落库
///   （§5.6⑲ 本地件、永不同步）；
/// - **同步状态行**（§6.1 原则 1 顶栏小圆点的设置页对应物）：展示当前
///   同步后端装配（Supabase 托管 / 本地回环，待用户凭据标注）；
/// - **付费墙占位**（§3.9 双轨变现骨架）：Fake 计费流的 SKU 目录展示 +
///   购买/恢复按钮；真实 `in_app_purchase` 待商店开发者账号（W8-9 灰度），
///   价格待实测复核（§12.3）。
///
/// W11-12 接入（§11.2 任务 3「隐私：拍照原图解析后即焚开关，默认开」）：
/// - **拍照原图即焚开关**（§3.7、§3.3「原图解析后即焚不落存储」、§5.6㉑）：
///   SwitchListTile 写回 PhotoBurnPolicy 运行期持有 + settings 表落库
///   （§5.6⑲ 本地件、永不同步）；开（默认）=确认落库后原图不留副本；
///   关=附件系统照常登记 burned，但登记焚毁前本机留档一份（photo_archive/，
///   仅设备本地、永不上传，见 lib/photo/photo_attachment_store.dart）。
///
/// 主题编辑器、数据导出等仍为占位（§4.3 /settings/* 子路由后续接入）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../billing/billing_provider.dart';
import '../../settings/photo_burn_setting.dart';
import '../../settings/raw_input_setting.dart';

/// 测试锚点：raw_input 上云开关。
const Key settingsRawInputSwitchKey = Key('settings_raw_input_switch');

/// 测试锚点：拍照原图即焚开关（§11.2 W11-12 任务 3）。
const Key settingsPhotoBurnSwitchKey = Key('settings_photo_burn_switch');

/// 测试锚点：恢复购买入口。
const Key settingsRestorePurchasesKey = Key('settings_restore_purchases');

/// 我的 Tab 页（§4.2）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 开关的页面态（toggle 立即反映；写盘异步跟随）。
  bool _rawInputCloud = false;

  /// 拍照原图即焚开关页面态（§11.2 W11-12 任务 3；默认开 §3.7）。
  bool _photoBurnAfterParse = true;

  /// 付费墙目录 Future（initState 拉取一次；Fake 流恒即时完成）。
  Future<BillingCatalog>? _catalogFuture;

  /// 防重入：购买请求进行中禁用按钮（§3.9 双轨购买流）。
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _rawInputCloud = ref.read(rawInputPolicyProvider).enabled;
    _photoBurnAfterParse = ref.read(photoBurnPolicyProvider).enabled;
    _catalogFuture = ref.read(billingServiceProvider).queryProducts();
  }

  /// 切换 raw_input 上云开关（§3.7）：先改运行期持有（AI 请求构造时读取），
  /// 再异步落库 settings 表（§5.6⑲；失败仅 SnackBar，不回滚页面态——
  /// 下次启动按落库值装配，本地件自愈口径）。
  Future<void> _toggleRawInputCloud(bool enabled) async {
    setState(() => _rawInputCloud = enabled);
    ref.read(rawInputPolicyProvider).enabled = enabled;
    try {
      await saveRawInputCloudEnabled(
        ref.read(appDatabaseProvider),
        enabled: enabled,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开关保存失败（本地保留本次选择）：$error')),
      );
    }
  }

  /// 切换拍照原图即焚开关（§3.7/§11.2 任务 3）：先改运行期持有（附件存储在
  /// 「登记即焚」时刻同步读取——toggle 即刻生效），再异步落库 settings 表
  /// （§5.6⑲；失败仅 SnackBar，不回滚页面态，本地件自愈口径同上）。
  Future<void> _togglePhotoBurnAfterParse(bool enabled) async {
    setState(() => _photoBurnAfterParse = enabled);
    ref.read(photoBurnPolicyProvider).enabled = enabled;
    try {
      await savePhotoBurnAfterParse(
        ref.read(appDatabaseProvider),
        enabled: enabled,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开关保存失败（本地保留本次选择）：$error')),
      );
    }
  }

  /// Fake 流购买（§3.9 骨架；真实商店通道 W8-9 接线，交互语义保持一致）。
  Future<void> _purchase(Sku sku) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      final result =
          await ref.read(billingServiceProvider).purchase(sku.id);
      if (!mounted) return;
      final message = switch (result.status) {
        PurchaseStatus.purchased => '已购买（Fake 内测流）：${sku.title}',
        PurchaseStatus.alreadyOwned => '已拥有：${sku.title}',
        PurchaseStatus.canceled => '已取消',
        PurchaseStatus.pending => '购买处理中…',
        PurchaseStatus.unavailable =>
          '暂不可购买（Fake 内测流）：${result.message ?? ''}',
        PurchaseStatus.error => '购买失败：${result.message ?? '未知错误'}',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }

  /// Fake 流恢复历史购买（换机/重装场景，商店口径）。
  Future<void> _restore() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      final result = await ref.read(billingServiceProvider).restore();
      if (!mounted) return;
      final message = result.status == PurchaseStatus.purchased
          ? '已恢复（Fake 内测流）：${result.skuId ?? ''}'
          : (result.message ?? '无历史购买（Fake 内测流）');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncLabel = ref.watch(syncBackendLabelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // ── 同步状态（§6.1 原则 1：只读展示，不阻塞任何操作）。
          ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('同步'),
            subtitle: Text(syncLabel),
            onTap: () => unawaited(
              ref.read(syncCoordinatorProvider).syncNow(),
            ),
          ),
          const Divider(height: 1),
          // ── raw_input 上云开关（§3.7 数据主权、§3.3 默认关=即用即焚）。
          SwitchListTile(
            key: settingsRawInputSwitchKey,
            secondary: const Icon(Icons.privacy_tip_outlined),
            title: const Text('原文上云（raw_input）'),
            subtitle: const Text(
              '关闭（默认）时 AI 请求仅携带规范化最小集，原文不出设备；'
              '开启时原文随请求上传便于排查（§3.3/§3.7）',
            ),
            value: _rawInputCloud,
            onChanged: _toggleRawInputCloud,
          ),
          const Divider(height: 1),
          // ── 拍照原图即焚开关（§3.7/§3.3/§5.6㉑、§11.2 W11-12 任务 3，
          //    默认开=解析后即焚；关=本机留档一份、永不上传）。
          SwitchListTile(
            key: settingsPhotoBurnSwitchKey,
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: const Text('拍照原图解析后即焚'),
            subtitle: const Text(
              '开启（默认）：确认落库后立即删除原图，仅留结构化结果与审计'
              '元数据，不落存储（§3.3/§5.6㉑）；关闭：本机留档一份原图便于'
              '复查（仅设备本地，永不上传）',
            ),
            value: _photoBurnAfterParse,
            onChanged: _togglePhotoBurnAfterParse,
          ),
          const Divider(height: 1),
          // ── 付费墙（§3.9 双轨：买断 + AI 订阅；W7-8 骨架=Fake 流）。
          const _SectionHeader(title: '升级 Slimca Pro'),
          _PaywallSection(
            catalogFuture: _catalogFuture,
            purchasing: _purchasing,
            onPurchase: _purchase,
            onRestore: _restore,
          ),
          const Divider(height: 1),
          // ── 既有占位（§4.3 子路由后续接入）。
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('主题'),
            subtitle: Text('深浅色跟随系统（§8.3）· 主题编辑器 W8+ 接入'),
          ),
          const ListTile(
            leading: Icon(Icons.ios_share_outlined),
            title: Text('数据导出'),
            subtitle: Text('JSONL/CSV 导出与清空 W8+ 接入（§3.9 数据主权）'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 区块标题（付费墙等分组）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// 付费墙区块（§3.9 双轨 SKU 目录 + 购买/恢复；Fake 流，W7-8 骨架）。
class _PaywallSection extends StatelessWidget {
  const _PaywallSection({
    required this.catalogFuture,
    required this.purchasing,
    required this.onPurchase,
    required this.onRestore,
  });

  final Future<BillingCatalog>? catalogFuture;
  final bool purchasing;
  final Future<void> Function(Sku sku) onPurchase;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BillingCatalog>(
      future: catalogFuture,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            catalog == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Column(
          children: [
            for (final sku in catalog.products)
              ListTile(
                key: Key('settings_paywall_sku_${sku.id}'),
                leading: Icon(
                  sku.kind == SkuKind.buyout
                      ? Icons.workspace_premium_outlined
                      : Icons.auto_awesome_outlined,
                ),
                title: Text('${sku.title} · ${sku.priceLabel}'),
                subtitle: Text(sku.note),
                trailing: OutlinedButton(
                  key: Key('settings_paywall_buy_${sku.id}'),
                  onPressed: purchasing ? null : () => onPurchase(sku),
                  child: const Text('购买'),
                ),
              ),
            ListTile(
              key: settingsRestorePurchasesKey,
              leading: const Icon(Icons.restore_outlined),
              title: const Text('恢复购买'),
              onTap: purchasing ? null : () => onRestore(),
            ),
            // 骨架边界注记（§3.9 W7-8）：真实 in_app_purchase 待商店账号。
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '内测为 Fake 计费流（不产生真实扣款）；真实内购待商店开发者账号'
                '（W8-9 灰度接线），价格待实测复核（§12.3）。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
