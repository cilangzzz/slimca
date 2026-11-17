/// 拍照原图「解析后即焚」开关的存取与运行期持有（§3.7 数据主权、§3.3 拍照
/// 通道行「原图解析后即焚不落存储」、§5.6㉑ attachments「默认解析后即焚：
/// 原图不落服务端」、§11.2 W11-12 任务 3「隐私：拍照原图解析后即焚开关，
/// 默认开」）。
///
/// 语义（任务口径 + §3.3/§5.6㉑）：
/// - **开（默认）**：确认落库成功后 attachments 登记即 burned 行
///   （blob_ref 恒 NULL=原图不落服务端）+ 本地临时文件删除——原图不留任何
///   副本（合规缺省，§3.9 合规红线）；
/// - **关（用户显式选择本机留档）**：附件系统仍按「登记即焚」登记
///   （attachments 行状态 burned、blob_ref 恒 NULL、不入 sync_outbox、
///   永不同步，§5.6⑯ 真值表集之外），但登记焚毁**前**把原图复制一份到应用
///   support 目录 photo_archive/——设备本地文件副本，仅本机可见可导出，
///   任何网络面（同步/服务端）都不可见（§3.7 数据主权「随时可撤回」）。
///
/// 存储位置：settings 表（§5.6⑲ 本地键值配置，value 一律 JSON；内容清单
/// 明确列有「拍照原图即焚开关」）。settings 是本地件、永不同步（§5.1 表
/// 分组）——即焚策略是设备本地隐私选择。
///
/// 缺省最严纪律（§1.6/§6.1）：缺键/坏 JSON/非布尔一律回落**默认开**——即焚
/// 是合规缺省，本地件损坏永不放宽（与 raw_input 开关「坏值回落更严档」同向）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// settings 表键（§5.6⑲ 内容清单「拍照原图即焚开关」，§11.2 W11-12 任务 3）。
const String kSettingPhotoBurnAfterParse = 'photo_burn_after_parse';

/// 运行期持有器（bootstrap 装载初值、设置页写回）。
///
/// 附件存储（lib/photo/photo_attachment_store.dart）在「登记即焚」时同步
/// 读取——登记路径不需要响应式重建，故用可变持有器而非 StateNotifier
/// （与 RawInputPolicy 同款装配纪律，§10.4）。
class PhotoBurnPolicy {
  /// 默认开（§3.3「原图解析后即焚不落存储」、§11.2 W11-12 任务 3「默认开」）。
  bool enabled = true;
}

/// 注入点（§10.4 壳负责装配）：缺省 = 新持有器（默认开）；bootstrap() 读
/// settings 表（§5.6⑲）装入上次的用户选择并 override；设置页写回同一持有器。
final photoBurnPolicyProvider = Provider<PhotoBurnPolicy>(
  (ref) => PhotoBurnPolicy(),
);

/// 读取开关（缺键/坏 JSON/非布尔一律回落默认**开**，§6.1 本地件自愈——
/// 即焚是合规缺省，损坏时取更严档）。
Future<bool> loadPhotoBurnAfterParse(cdb.AppDatabase database) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(kSettingPhotoBurnAfterParse)))
      .getSingleOrNull();
  if (row == null) return true;
  try {
    final value = jsonDecode(row.value);
    return value is bool ? value : true;
  } on FormatException {
    return true; // 坏值视同未设置（§5.6⑲ 本地件自愈口径）。
  }
}

/// 写回开关（设置页 toggle；settings.value 一律 JSON，§5.6⑲）。
Future<void> savePhotoBurnAfterParse(
  cdb.AppDatabase database, {
  required bool enabled,
}) async {
  await database.into(database.settings).insertOnConflictUpdate(
        cdb.SettingsCompanion.insert(
          key: kSettingPhotoBurnAfterParse,
          value: jsonEncode(enabled),
        ),
      );
}
