/// 账本管理页（§5.4④ ledgers 生命周期、§3.4 多账本 P1「账本切换抽屉（Hero
/// 转场）、账本归档」、§11.2 W15 主线「多账本」）。
///
/// - 可用账本清单（默认徽标 + 重命名/设为默认/归档操作）；
/// - 归档账本清单（恢复入口；归档=产品态软移除，历史账单保留）；
/// - 内置 kcal 账本行只读展示（§5.4④「不可删除不可多开」——无归档/默认
///   操作，仅允许改名）；
/// - 写路径全部经 [LedgerManageRepository] → core_db LedgerDao（outbox
///   同事务入队与 kcal 保护由 DAO 强制，§6.2）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ledger_manage_repository.dart';
import '../ledger_models.dart';

/// 账本管理页测试锚点（页面同屏大量同名文本，统一按 key 定位）。
const Key ledgerManageCreateKey = ValueKey<String>('ledger_manage_create');

/// 账本名称输入框锚点（新建/重命名共用）。
const Key ledgerManageNameFieldKey = ValueKey<String>('ledger_manage_name_field');

/// 账本对话框保存按钮锚点（新建/重命名共用）。
const Key ledgerManageSaveKey = ValueKey<String>('ledger_manage_save');

/// 归档确认对话框「归档」按钮锚点。
const Key ledgerManageConfirmArchiveKey =
    ValueKey<String>('ledger_manage_confirm_archive');

/// 账本管理页（构造注入仓库，§10.4）。
class LedgerManagePage extends StatelessWidget {
  const LedgerManagePage({super.key, required this.repository});

  final LedgerManageRepository repository;

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _LedgerNameDialog(
        title: '新建账本',
        initialName: null,
        onSave: (String name) async {
          await repository.createLedger(name: name);
        },
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    LedgerSwitchOption option,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _LedgerNameDialog(
        title: '重命名账本',
        initialName: option.name,
        onSave: (String name) => repository.renameLedger(option.id, name: name),
      ),
    );
  }

  void _showArchiveDialog(BuildContext context, LedgerSwitchOption option) {
    final SlimcaTheme tokens = context.slimca;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('归档账本「${option.name}」？'),
        content: const Text(
          '归档后不再出现在记账与账单筛选中，历史账单原样保留；可随时恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: ledgerManageConfirmArchiveKey,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.onPrimary,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              repository.setArchived(option.id, archived: true);
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        backgroundColor: tokens.surface,
        title: const Text('账本管理'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          SlimcaStaggerItem(
            index: 0,
            child: _ActiveLedgersCard(
              repository: repository,
              onCreate: () => _showCreateDialog(context),
              onRename: (LedgerSwitchOption option) =>
                  _showRenameDialog(context, option),
              onArchive: (LedgerSwitchOption option) =>
                  _showArchiveDialog(context, option),
              onSetDefault: (LedgerSwitchOption option) =>
                  repository.setDefault(option.id),
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 1,
            child: _ArchivedLedgersCard(repository: repository),
          ),
        ],
      ),
    );
  }
}

/// 可用账本卡（§5.4④）：默认徽标 + 操作列；kcal 内置账本只读行。
class _ActiveLedgersCard extends StatelessWidget {
  const _ActiveLedgersCard({
    required this.repository,
    required this.onCreate,
    required this.onRename,
    required this.onArchive,
    required this.onSetDefault,
  });

  final LedgerManageRepository repository;
  final VoidCallback onCreate;
  final void Function(LedgerSwitchOption) onRename;
  final void Function(LedgerSwitchOption) onArchive;
  final void Function(LedgerSwitchOption) onSetDefault;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StreamBuilder<List<LedgerSwitchOption>>(
        stream: repository.watchSwitchOptions(),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<LedgerSwitchOption>> snapshot,
        ) {
          final List<LedgerSwitchOption> options =
              snapshot.data ?? const <LedgerSwitchOption>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '账本',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '切换默认账本、重命名与归档（§3.4 多账本；kcal 账本内置不可删，§5.4④）',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
              ),
              const SizedBox(height: 8),
              for (final LedgerSwitchOption option in options)
                _LedgerTile(
                  option: option,
                  onRename: () => onRename(option),
                  onArchive: option.isKcalLedger
                      ? null
                      : () => onArchive(option),
                  onSetDefault: option.isKcalLedger || option.isDefault
                      ? null
                      : () => onSetDefault(option),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ledgerManageCreateKey,
                  icon: const Icon(Icons.add),
                  label: const Text('新建账本'),
                  onPressed: onCreate,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 归档账本卡（§3.4「账本归档」）：恢复入口；空态一行提示。
class _ArchivedLedgersCard extends StatelessWidget {
  const _ArchivedLedgersCard({required this.repository});

  final LedgerManageRepository repository;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StreamBuilder<List<LedgerSwitchOption>>(
        stream: repository.watchArchivedOptions(),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<LedgerSwitchOption>> snapshot,
        ) {
          final List<LedgerSwitchOption> archived =
              snapshot.data ?? const <LedgerSwitchOption>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '已归档',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              if (archived.isEmpty)
                Text(
                  '暂无归档账本（归档=软移除，历史账单保留，§3.4）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                )
              else
                for (final LedgerSwitchOption option in archived)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            option.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: tokens.onSurfaceMuted),
                          ),
                        ),
                        TextButton(
                          key: ValueKey<String>(
                            'ledger_manage_restore_${option.id}',
                          ),
                          onPressed: () => repository.setArchived(
                            option.id,
                            archived: false,
                          ),
                          child: const Text('恢复'),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// 单行账本：图标 + 名称（默认徽标 / 内置徽标）+ 币种 + 操作列。
class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.option,
    required this.onRename,
    required this.onArchive,
    required this.onSetDefault,
  });

  final LedgerSwitchOption option;
  final VoidCallback onRename;

  /// null=不渲染该操作（kcal 无归档；默认账本无「设为默认」）。
  final VoidCallback? onArchive;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Icon(
            option.isKcalLedger
                ? Icons.local_fire_department_outlined
                : Icons.account_balance_wallet_outlined,
            size: 20,
            color: option.isKcalLedger ? tokens.kcalIn : tokens.moneyOut,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.onSurface,
                            ),
                      ),
                    ),
                    if (option.isDefault) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '默认',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tokens.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (option.isKcalLedger) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '内置',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tokens.onSurfaceMuted,
                            ),
                      ),
                    ],
                  ],
                ),
                Text(
                  option.isKcalLedger
                      ? '热量账本 · 不可删除不可多开（§5.4④）'
                      : '币种 ${option.currency}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('ledger_manage_rename_${option.id}'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '重命名',
            onPressed: onRename,
          ),
          if (onSetDefault != null)
            IconButton(
              key: ValueKey<String>('ledger_manage_default_${option.id}'),
              icon: const Icon(Icons.star_outline, size: 18),
              tooltip: '设为默认账本',
              onPressed: onSetDefault,
            ),
          if (onArchive != null)
            IconButton(
              key: ValueKey<String>('ledger_manage_archive_${option.id}'),
              icon: const Icon(Icons.archive_outlined, size: 18),
              tooltip: '归档账本',
              onPressed: onArchive,
            ),
        ],
      ),
    );
  }
}

/// 新建/重命名账本对话框（§5.4④：名称必填；币种 v1 固定 CNY——多币种
/// 留待后续周目，避免货币换算面铺开）。
class _LedgerNameDialog extends StatefulWidget {
  const _LedgerNameDialog({
    required this.title,
    required this.initialName,
    required this.onSave,
  });

  final String title;
  final String? initialName;
  final Future<void> Function(String name) onSave;

  @override
  State<_LedgerNameDialog> createState() => _LedgerNameDialogState();
}

class _LedgerNameDialogState extends State<_LedgerNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? '');
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = '账本名不能为空（§5.4④）';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    await widget.onSave(name);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: ledgerManageNameFieldKey,
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '账本名',
          hintText: '如 旅行备用金',
          errorText: _errorText,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: ledgerManageSaveKey,
          onPressed: _saving ? null : _save,
          child: Text(widget.initialName == null ? '创建' : '保存'),
        ),
      ],
    );
  }
}
