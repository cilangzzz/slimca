/// Slimca 纯 Dart 领域层（§10.4 packages/core_domain）。
///
/// 内容：统一事件模型实体与枚举（§2.1-§2.2、§5.2）、HLC 混合逻辑时钟
/// （§6.3 定宽编码）、仓库抽象（§10.4）、SyncEngine 抽象与 outbox 模型
/// （§6.2）、遥测抽象与隐私闸门（§3.9 监控）。本包无 Flutter 依赖，供
/// core_db / feature_sync / feature_* 复用；行快照 JSON 键名与 Drift 列
/// 同构（§6.2 单侧定义双侧生成）。
library;

export 'src/common.dart';
export 'src/entry.dart';
export 'src/entry_line.dart';
export 'src/hlc.dart';
export 'src/repository.dart';
export 'src/sync_engine.dart';
// W7-8（§3.9 监控）：遥测接口与值对象入包级 barrel——壳层（apps/mobile）
// 按公开路径引用，不再经 src 实现路径（各文件头「导出注记」的属主收敛）。
export 'src/telemetry.dart';
