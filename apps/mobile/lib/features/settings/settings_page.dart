/// 我的 Tab：设置页（《UI-规范与重设计》§4 菜单/设置页重设计定稿 + §4.2 Tab）。
///
/// V1 UX 优化插曲重设计（§4.1 IA 分组，参照 iOS 18 Settings 三层结构）：
/// ```
/// 我的
/// ├─ 顶部账号/同步卡（非 ListTile）：同步状态只读一行 + 头像位
/// │   └─ Pro 状态收进此卡一行小字 pill（不占整行；无购买时不显示）
/// ├─ 分组「数据与隐私」：原文上云开关 / 拍照原图即焚开关（两 Switch 行迁入）
/// ├─ 分组「外观」：主题（副标题=当前包名·深浅色；动效等级在主题编辑面板内）
/// ├─ 分组「数据」：同步（点击=手动 syncNow）/ 数据导出（占位）
/// └─ 尾部低频组（与上方隔 Divider）：关于 / 版本 ＋ 独立危险组：清空数据
/// ```
///
/// **「升级计划」移除决策（§4.1 产品拍板项，无规范出处可引）**：
/// `_SectionHeader('升级 Slimca Pro')` + `_PaywallSection` 整块从主列表移除，
/// 裸「恢复购买」入口一并移出（§4.3：仅当已有购买记录时才在「关于」分组
/// 显示状态行——V1 无购买记录，不渲染）。**IAP 抽象代码保留不删**
/// （lib/billing/billing_provider.dart、billing_service.dart、fake_billing_service.dart、
/// sku_catalog.dart 及 billing_fake_test.dart 测试锚点原样），UI 不露出；
/// 商业化后置，转化触点收敛到 AI 免费额度耗尽的降级提示（设计文档 §7.4）。
///
/// 行组件 = SlimcaMenuGroup/SlimcaMenuTile（§4.2 行规格：56/72 行高、卡内
/// 水平 12、分组头 Label Large 14/500、按压统一 state layer、分组卡圆角 12/
/// 组间 24/页边 24，见 menu_components.dart 规格注释）。
///
/// 页面转场（§4.4）：主题入口保留弹簧面板（showThemeEditorPanel，
/// spring.snappy 速度继承=HIG 可取消+跟手）；/settings/* 子路由随数据主权页
/// 接入时走共享轴 PageRouteBuilder（§4.3 路由表、§9.5）。
///
/// W7-8 接入（§11.1）保留：raw_input 上云开关（§3.7/§3.3 默认关）与拍照原图
/// 即焚开关（§11.2 W11-12 任务 3，默认开）均为 Switch 行写回运行期持有 +
/// settings 表落库（§5.6⑲ 本地件、永不同步）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
// §8.2 三层架构：危险红字/卡底读 SlimcaTheme 语义 token（窄 show 子句，
// §10.4 只引所需符号，避免与 ui_kit 后续导出冲突）。
import 'package:ui_kit/ui_kit.dart'
    show SlimcaTheme, SlimcaThemeBuildContext;

import '../../app/providers.dart';
import '../../settings/photo_burn_setting.dart';
import '../../settings/raw_input_setting.dart';
import '../../telemetry/w16_funnel_events.dart';
import 'menu_components.dart';
import 'theme_editor_panel.dart' show showThemeEditorPanel;

/// 测试锚点：主题编辑器入口（§11.2 W16 任务 1）。
const Key settingsThemeEntryKey = Key('settings_theme_entry');

/// 测试锚点：raw_input 上云开关（Switch 行内 trailing Switch）。
const Key settingsRawInputSwitchKey = Key('settings_raw_input_switch');

/// 测试锚点：拍照原图即焚开关（§11.2 W11-12 任务 3）。
const Key settingsPhotoBurnSwitchKey = Key('settings_photo_burn_switch');

/// 测试锚点：清空数据危险项（§4.3 危险项确认弹窗链路）。
const Key settingsClearDataKey = Key('settings_clear_data');

/// 我的 Tab 页（§4.2；§4.1 IA 分组定稿）。
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

  /// 应用版本信息 Future（「关于」分组版本行；package_info_plus 运行时读取，
  /// 插件通道不可用的环境（如 widget 测试）→ 快照 error，渲染占位「—」，
  /// 不阻塞设置页装配）。
  Future<PackageInfo>? _versionFuture;

  @override
  void initState() {
    super.initState();
    _rawInputCloud = ref.read(rawInputPolicyProvider).enabled;
    _photoBurnAfterParse = ref.read(photoBurnPolicyProvider).enabled;
    _versionFuture = PackageInfo.fromPlatform();
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

  /// 清空数据危险项确认弹窗（§4.3 定稿：Cancel 不做默认按钮 + 按钮用具体
  /// 动词「清空」不用「OK」+ 红字危险项独立分组）。
  ///
  /// 确认后的清空执行体随「数据导出」主权页（§4.3 路由表 /settings/export
  /// 「导出/清空/隐私政策」）一并接线——本插曲先落入口+弹窗骨架，动作以
  /// SnackBar 明示边界（不假装已清空）。
  Future<void> _confirmClearData() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: const Text(
          '事件记录（流水/热量/健身）将被软删并随同步扩散到所有设备，'
          '且不可撤销（§5.1 墓碑/§6.5）。建议先完成数据导出备份（§3.9）。',
        ),
        actions: <Widget>[
          // HIG alerts（§4.3）：取消不做默认按钮（普通文本钮，无填充强调）。
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          // 具体动词「清空」（不用「OK」）+ 危险红字（语义 token danger）。
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.slimca.danger,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '清空流程随「数据导出」主权页（/settings/export）一并接线'
                    '（§4.3 占位），本次未删除任何数据',
                  ),
                ),
              );
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncLabel = ref.watch(syncBackendLabelProvider);
    // W16 主题入口副标题（当前包名 + 深浅模式；§8.3/§11.2 W16 任务 1）。
    final themePackLabel = ref.watch(currentThemePackNameProvider);
    final ThemeMode themeMode = ref.watch(slimcaThemeModeProvider);
    final themeModeLabel = switch (themeMode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        // 页边 24dp（§4.2「页边 24」= space300，§1.3 SlimcaSpacing 刻度；
        // 底部 96 预留壳层中央「+」FAB 命中区）。
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
        children: <Widget>[
          // ── 顶部账号/同步卡（§4.1「非 ListTile：同步状态只读一行 + 头像位」）。
          _AccountSyncCard(syncLabel: syncLabel),
          const SizedBox(height: 24), // 组间 24（space300，§1.3）
          // ── 分组「数据与隐私」（§4.1）：两 Switch 行原样迁入（语义不变）。
          SlimcaMenuGroup(
            header: '数据与隐私',
            children: <Widget>[
              SlimcaMenuTile(
                icon: Icons.privacy_tip_outlined,
                title: '原文上云（raw_input）',
                subtitle: const Text(
                  '关闭（默认）时 AI 请求仅携带规范化最小集，原文不出设备；'
                  '开启时原文随请求上传便于排查（§3.3/§3.7）',
                ),
                trailing: Switch(
                  key: settingsRawInputSwitchKey,
                  value: _rawInputCloud,
                  onChanged: _toggleRawInputCloud,
                ),
                onTap: () => unawaited(_toggleRawInputCloud(!_rawInputCloud)),
              ),
              SlimcaMenuTile(
                icon: Icons.local_fire_department_outlined,
                title: '拍照原图解析后即焚',
                subtitle: const Text(
                  '开启（默认）：确认落库后立即删除原图，仅留结构化结果与审计'
                  '元数据，不落存储（§3.3/§5.6㉑）；关闭：本机留档一份原图便于'
                  '复查（仅设备本地，永不上传）',
                ),
                trailing: Switch(
                  key: settingsPhotoBurnSwitchKey,
                  value: _photoBurnAfterParse,
                  onChanged: _togglePhotoBurnAfterParse,
                ),
                onTap: () => unawaited(
                  _togglePhotoBurnAfterParse(!_photoBurnAfterParse),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── 分组「外观」（§4.1）：主题入口（副标题=当前包名·深浅色；
          //    动效等级并入主题编辑面板内，不单列）。
          SlimcaMenuGroup(
            header: '外观',
            children: <Widget>[
              SlimcaMenuTile(
                key: settingsThemeEntryKey,
                icon: Icons.palette_outlined,
                title: '主题',
                subtitle: Text(
                  '当前主题包：$themePackLabel · 深浅色$themeModeLabel',
                ),
                onTap: () {
                  // W16 漏斗首步（theme_editor_opened，§11.2 W16 任务 5）。
                  unawaited(
                    ref
                        .read(telemetryServiceProvider)
                        .funnel(W16TelemetryFunnel.themeEditorOpened),
                  );
                  // §4.4：主题入口保留弹簧面板（spring.snappy 速度继承）。
                  unawaited(showThemeEditorPanel(context));
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── 分组「数据」（§4.1）：同步（现 ListTile 迁入，点击=手动
          //    syncNow §6.2 同步时机）/ 数据导出（占位）。
          SlimcaMenuGroup(
            header: '数据',
            children: <Widget>[
              SlimcaMenuTile(
                icon: Icons.sync_outlined,
                title: '同步',
                // 同步状态只读展示在顶部账号卡；本行为动作行（§6.2 手动
                // syncNow），失败静默——状态以流/回环装配自描述（§6.1）。
                subtitle: const Text('手动触发一轮同步（§6.2 同步时机）'),
                onTap: () => unawaited(
                  ref.read(syncCoordinatorProvider).syncNow(),
                ),
              ),
              SlimcaMenuTile(
                icon: Icons.ios_share_outlined,
                title: '数据导出',
                subtitle: const Text(
                  'JSONL/CSV 导出与清空随 /settings/export 主权页接入（§3.9）',
                ),
                // 占位行：onTap null → 无 chevron、无按压态（§4.2 非导航行）。
              ),
            ],
          ),
          // 尾部低频组与上方隔 Divider（§4.1）；组间 24 + 1px 发丝线 + 24。
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          SlimcaMenuGroup(
            children: <Widget>[
              SlimcaMenuTile(
                icon: Icons.info_outline,
                title: '关于',
                subtitle: const Text('Slimca · 记一件事，钱和卡路里一起入账（§1.2）'),
              ),
              SlimcaMenuTile(
                icon: Icons.numbers_outlined,
                title: '版本',
                subtitle: _buildVersionSubtitle(),
              ),
            ],
          ),
          // ── 危险项独立分组（§4.3「尾部独立分组 + 红色文字按钮 + 与相邻组
          //    隔 Divider」；红色字由 SlimcaMenuTile.danger 承担）。
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          SlimcaMenuGroup(
            children: <Widget>[
              SlimcaMenuTile(
                key: settingsClearDataKey,
                icon: Icons.delete_forever_outlined,
                title: '清空数据',
                danger: true,
                onTap: () => unawaited(_confirmClearData()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 版本行副标题：运行时读取 package_info（pubspec version+build，如
  /// 「1.1.0+2」）；插件通道不可用的环境渲染占位「—」（不阻塞页面装配）。
  Widget _buildVersionSubtitle() {
    return FutureBuilder<PackageInfo>(
      future: _versionFuture,
      builder: (context, snapshot) {
        final PackageInfo? info = snapshot.data;
        final String text = info == null
            ? '—'
            : (info.buildNumber.isEmpty
                ? info.version
                : '${info.version}+${info.buildNumber}');
        return Text(text);
      },
    );
  }
}

/// 顶部账号/同步卡（§4.1「非 ListTile：同步状态只读一行 + 头像位」）。
///
/// V1 本地优先（§6.1）尚无云端账号：账号位=设备账簿占位（Supabase Auth 接入
/// 后替换为用户身份，W8-9 灰度）；同步状态行=当前装配描述（待用户凭据标注）。
///
/// **Pro 状态 pill 位置（§4.1 预留）**：收进本卡一行小字 pill、不占整行，
/// 仅当已有购买记录时渲染（V1 无购买 → 不显示）；商业化后置，转化触点收敛
/// 到 AI 免费额度耗尽的降级提示（§7.4）——接线点随真实商店通道（W8-9）落位。
class _AccountSyncCard extends StatelessWidget {
  const _AccountSyncCard({required this.syncLabel});

  /// 当前同步装配的面向用户描述（syncBackendLabelProvider，§6.1 原则 1
  /// 「设置页对应物」：只读展示，不阻塞任何操作）。
  final String syncLabel;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // 卡内 padding 12 基准 + 头像位 40 视觉（§1.4 leading 视觉上限 40）。
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: tokens.surfaceMuted,
              foregroundColor: tokens.onSurfaceMuted,
              child: const Icon(Icons.person_outline, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '本地账簿',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    syncLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
