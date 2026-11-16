/// 四级降级的执行接口（§7.4「降级方案（健壮性即产品体验）」）。
///
/// 级别与落点（§7.4 表行序）：
///
/// | 级别 | 场景 | 行为 | W3-4 状态 |
/// |---|---|---|---|
/// | 1 | 超时（文本 5s）/解析失败 | 原输入保留 → 自动降级手填表单 | **内建**：[StructuredFailure]（degradeLevel=manualForm，rawInput 保留） |
/// | 2 | 断网 | 记录落 draft + 延迟解析队列，联网自动补解析 | 接口预留：[DeferredParseQueue]（§3.3 离线延迟解析，W5-6 接） |
/// | 3 | 免费额度耗尽 | 明确提示当日剩余额度与升级入口，手填不受限 | 接口预留：[AiQuotaGate]（商业化接入时接） |
/// | 4 | 供应商单点故障/涨价 | 双供应商 fallback（GPT-4o-mini↔Qwen/GLM） | 接口预留：编排层组合多个 [LlmAdapter]（core_ai 不内置） |
///
/// 本库只定义接缝，不实现策略：宿主 feature 层按产品节奏接入。
library;

import '../parse/parse_models.dart';

/// 二级降级：延迟解析队列（§7.4「断网：记录落 draft + 延迟解析队列，
/// 联网自动补解析」；§3.3 离线延迟解析 P0）。
///
/// W5-6 由同步域接入（联网后消费队列 → [AiParser.parse] → 确认卡）；
/// 入队项已携带规范化前的原输入与上下文，重放语义与首发一致。
abstract interface class DeferredParseQueue {
  Future<void> enqueue(DeferredParse item);
}

/// 一条待补解析的输入（离线时暂存；§7.4 二级降级载荷）。
class DeferredParse {
  const DeferredParse({
    required this.rawInput,
    required this.context,
    required this.inputKind,
    required this.createdAtMs,
    required this.inputHash,
  });

  /// 原输入（规范化前；§7.4「原输入保留」同样适用于断网场景）。
  final String rawInput;

  /// 解析上下文（日期锚点 + 单边模式）。
  final ParseContext context;

  /// 输入通道（text/voice/photo）。
  final AiInputKind inputKind;

  /// 入队时刻 UTC ms。
  final int createdAtMs;

  /// 缓存键（入队时预计算，联网补解析时先查缓存防重复计费）。
  final String inputHash;
}

/// 三级降级：免费额度闸门（§7.4「免费额度耗尽：明确提示当日剩余额度与
/// 升级入口，手填不受限」；商业化双轨 IAP 接入时由宿主实现）。
abstract interface class AiQuotaGate {
  /// 解析前额度检查（本地计数 + 服务端配额）；[AiQuotaStatus.allowed]
  /// 为 false 时 UI 提示额度并保留手填路径（永不阻断手填，§7.4）。
  Future<AiQuotaStatus> check();
}

/// 额度状态。
class AiQuotaStatus {
  const AiQuotaStatus({required this.allowed, required this.remainingToday});

  /// 是否允许再解析。
  final bool allowed;

  /// 今日剩余次数（免费档每日 3 次口径，§3.9/§7.5）。
  final int remainingToday;
}
