# feature_capture 代码模式

> 本包是三条动线共用的状态机 + 网关编排层，模式高度一致。新增功能前先读本文，可避免重新发明装配与降级纪律。

## 新增一个标准功能的步骤

### A. 新增一条输入通道（如语音 → 结构化解析）

1. **定义接缝接口**（lib/src/ 下新文件）：`abstract interface class XxxParser { Future<CaptureParseResult> parse(XxxRequest request); }`——返回复用 `CaptureParseResult`（校验器/确认卡/落库全链免费复用）。
2. **定义注入 Provider**：`Provider<XxxParser>(ref => throw UnimplementedError('宿主必须 override …'))`——装配遗漏在开发期暴露，禁止静默 no-op 兜底（特例：安全语义的接缝可缺省最严兜底，如 `NoOnDeviceEstimator`）。
3. **控制器编排**（CaptureController 新方法，顺序固定）：守卫（仅 input 阶段响应）→ 呼吸态先于任何 await → 归一化 + input_hash → `findCachedParse` → 注入解析器（带超时 `.timeout(...)`）→ `checkUsable()` → `saveAiParse` → `_enterConfirm(...)`；失败 catch 三层（CaptureStructuredFailure / TimeoutException / 兜底）→ 降级表单。
4. **state 携带通道语义**：source 用 `pendingSource`（EntrySource 枚举）承载；**不新增 `CaptureAiStage` 枚举值**（穷举 switch 编译期硬约束），等待文案复用 `photoProcessingLabel` 模式或新增独立 String 字段。
5. **Fake 集**（capture_photo_fakes.dart 同款）：确定性字节/脚本化返回 + 调用计数器 + 请求录制表；测试禁真实网络/设备。
6. **测试**：widget 流程测试 + 网关落库/outbox 断言（capture_outbox_test.dart 同款 Harness：内存真库 + HlcClock 注入）。

### B. 新增一个提交字段（如 entries 加 meta 字段）

1. core_db 领域实体/表先改（见 [../core_db/README.md](../core_db/README.md) 的 schema 变更流程）；
2. 载荷对象加字段（CaptureAiSubmitRequest / CaptureCorrectionRequest），默认值向后兼容；
3. 网关落库处补列 + 审计行字段（若可修正，补 `_insertCorrectionAudit` 分支）；
4. `CaptureFormState` 加字段时 `copyWith` 必须用哨兵（可空字段），并在派生量校验处接上；
5. capture_outbox_test 补「行快照入队」断言。

## 设计模式用法

| 模式 | 应用 | 关键类/位置 |
|---|---|---|
| DI 接缝 + fail-fast 注入 | 本包不持有插件/供应商依赖，全部经 Provider 接缝；未装配读即抛 UnimplementedError，开发期暴露 | captureParserProvider、captureImageSourceProvider、captureGatewayProvider 等 6 个必 override 点 |
| 缺省最严兜底 | 安全语义接缝的缺省实现取最保守行为而非抛错 | `NoOnDeviceEstimator`（恒 null→人工确认）、`captureRawInputCloudEnabledProvider`（恒 false）、`capturePhotoTelemetryProvider`（null） |
| 组合子（双供应商 fallback） | primary 结构化失败/超时 → fallback；兜底再失败向上抛 | `CapturePhotoParserFallback(primary, fallback)`（capture_photo_parser.dart） |
| 不可变状态 + 哨兵 copyWith | 可空字段区分「不改动」与「置 null」：`Object? categoryId = _unchanged`，`identical(x, _unchanged) ? this.x : x as String?` | `CaptureFormState.copyWith`（capture_models.dart 末尾） |
| 状态机 + 穷举 switch | UI 按 `CaptureAiStage` 穷举分流；通道语义挂 state 字段不挂阶段枚举 | CapturePage._aiFlowBody |
| 网关事务编排 | 业务写入 + `outbox.enqueueRow`（读回终态快照）同事务；Drift 嵌套事务自动 join 外层；任一步失败整体回滚无半途出网 | CaptureGateway 全部写方法（capture_gateway.dart） |
| 审计行由调用方落库 | 仓库层无从得知字段级前后值，corrections 差异审计在网关逐字段比对落行（append-only） | `_insertCorrectionAudit`（source='user'/'ai_corrected'） |
| 降级不打断 | AI 失败 catch 分层映射为降级文案，state 原文保留；提交失败写 errorText 返回 null 不抛异常 | `startParse` / `startPhotoCapture` / `submit` |
| 遥测永不阻塞 | 埋点 try-catch 吞错；props 只允许标量（枚举/布尔/耗时/错误类型码），内容字段禁入 | `_photoFunnel` / `_photoMetric`（capture_controller.dart） |
| UI 语义 token | 组件层禁裸色值；colorToken 名→SlimcaTheme 映射，未知 token 回退中性色 | CaptureCategoryPicker._semanticColor |

## 扩展点

1. **新识别供应商**：实现 `CapturePhotoParser` / `CaptureParser`，在壳层用 `CapturePhotoParserFallback` 或自组组合注入；凭据一律 dart-define 键名（如 `SLIMCA_AI_BASE/KEY/MODEL`、`SLIMCA_BAIDU_AK/SK`），禁止硬编码。
2. **新单边档位**：加 `CaptureSide` 枚举值是**低风险**（该枚举 switch 不是编译期穷举约束场景），但需同步改 `_labels`、`showCalorieInConfirm`/`showMoneyInConfirm` 派生量与 kind 推导。
3. **新落库审计字段**：见上文 B 流程；corrections.field 为自由 TEXT，允许扩展（现有：date/tz_offset_min/title/note/amount/direction/category/ledger/kcal）。
4. **新漏斗事件**：沿 `CapturePhotoFunnel` 常量类模式加常量 + 控制器埋点；事件名需可检索、props 标量。
5. **确认卡插槽**：CaptureConfirmCard 基于 ui_kit `SlimcaConfirmCard` 的 header/slots/footer 插槽模型——新增区块=新增 slot，动效（级联入场）免费获得。
6. **端侧模型接入**：壳层 override `captureOnDeviceEstimatorProvider`（返回 provider/model 标 'on_device' 的 CaptureParseResult，置信度从保守标注）；该路径天然不落 ai_parses。
