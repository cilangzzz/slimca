# api-llm.md — LLM 通道、缓存与降级

> 覆盖：LlmAdapter 抽象与 OpenAI 兼容实现（供应商预设/错误分类/重试纪律）、缓存实现选择、
> 四级降级接口、Fake 与真实通道切换。解析入口与流程见 [api-parse.md](api-parse.md)。

## LlmAdapter（一次补全调用的抽象）

```dart
abstract interface class LlmAdapter {
  String get providerId;                  // ai_parses.provider
  String get modelId;                     // ai_parses.model
  LlmJsonCapability get jsonCapability;   // none / jsonObject / jsonSchema 两档口径
  Future<LlmResponse> complete(LlmRequest request);
}
```

实现约定：`complete` 自带超时+瞬时重试；抛出的异常一律是 `LlmException` 及其子类（错误
分类已完成）；请求档位高于模型档位时必须自动降档（正确性由 parse 层校验器兜底，降档只
影响引擎级保证）。本层不感知业务语义——提示词组装与受约束解码属 parse 层。

### LlmRequest / LlmResponse

| LlmRequest 字段 | 说明 |
|---|---|
| `messages` | List<LlmMessage>；纯文本用主构造，多模态用 `LlmMessage.parts(role, [LlmTextPart, LlmImageUrlPart])` |
| `jsonIntent` | none / jsonObject（宽档，校验器兜底）/ jsonSchema（最高档，**必填 jsonSchema**，assert 保证） |
| `temperature` / `maxTokens` | 缺省 0.2 / 由适配器决定 |
| `timeoutOverride` | 单次超时覆盖——照片 12s 档由此放宽，适配器配置保留文本缺省 5s |

`LlmResponse`：content（受约束 JSON 字符串）+ provider/model/latencyMs/promptTokens/
completionTokens/costMicro（微元，无价目时 0）+ finishReason + rawBody（排查用不落库）。

## OpenAiCompatibleAdapter（一套协议覆盖多供应商）

`OpenAiCompatibleConfig`：baseUrl（尾部 `/` 会归一化）、apiKey（Bearer）、model、
jsonCapability（缺省 jsonObject）、timeout（缺省 5s）、maxAttempts（缺省 2，含首次）、
retryBackoff（缺省 300ms 线性递增，测试可注入 0）、pricing（null 时 costMicro=0）。

- response_format 选档矩阵：intent=none 不附加；jsonObject → 模型 none 档时不附加；
  jsonSchema → 模型 jsonSchema 档发 json_schema 信封（strict 不强制开启——个别端点不支持），
  jsonObject 档自动降为 json_object，none 档不附加。
- `http.Client` 可注入（测试用 MockClient，禁真实网络）。
- 请求 URL 由 `Uri.resolve('chat/completions')` 拼接：baseUrl 必须先归一化去尾斜杠再补 `/`
  resolve，否则最后一段路径（如 `/v1`）会被相对路径替换（历史 bug，已内建处理）。

### 供应商预设 LlmModelPreset

| id | provider | baseUrl | capability | vision | pricing |
|---|---|---|---|---|---|
| `gpt-4o-mini` | openai | api.openai.com/v1 | jsonSchema | 否 | 已配（¥1.08/¥4.32 per 1M 折算微元） |
| `qwen-vl` | dashscope | dashscope.aliyuncs.com/compatible-mode/v1 | jsonObject | 是 | null（按图计价待实测，不虚报） |
| `glm-4v` | zhipu | open.bigmodel.cn/api/paas/v4 | jsonObject | 是 | null |
| `deepseek-flash` | deepseek | api.deepseek.com/v1 | jsonObject | 是 | null（未公开实测） |

`LlmModelPreset.all` 供双供应商 fallback 编排遍历。**注意：API id ≠ 展示名**——端点只认
`deepseek-flash`/`deepseek-v4-pro`；用户口述的「DeepSeek-V4.1-Flash-1017」是展示名，填错
返回 400 invalid_request_error（2026-11-17 真实联调确认）。

## 错误分类（LlmException sealed 家族）与重试纪律

| 异常 | 触发 | retryable | StructuredFailure.reason | 降级级别 |
|---|---|---|---|---|
| `LlmTimeoutException` | 调用超时 | 是 | timeout | manualForm（一级手填） |
| `LlmNetworkException` | 传输层错误/断网 | 是 | network | deferredQueue（二级延迟队列） |
| `LlmServerException` | 5xx/408 | 是 | providerError | manualForm |
| `LlmRateLimitException` | 429 非 insufficient_quota | 是 | rateLimit | manualForm |
| `LlmQuotaException` | HTTP 402 / 429+insufficient_quota | 否 | quota | quotaNotice（三级） |
| `LlmAuthException` | 401/403 | 否 | auth | manualForm |
| `LlmInvalidRequestException` | 400/404/413/422、空字节、native 未实现 | 否 | invalidRequest | manualForm |
| `LlmBadResponseException` | 2xx 但 body 非 JSON/缺 choices/content | 否 | badResponse | manualForm |

- 适配器层只重试 retryable=true 的分类（线性退避）；解析级失败（校验违例）由管线带纠错
  回喂重试 1 次——两层互不叠加。sealed 家族保证 switch 穷尽：新增分类必须显式接入降级映射
  （编译器强制）。
- 该分类体系同时被百度菜品识别与小票 OCR 适配器复用（百度侧不新增分类）——三条管线共用
  同一张降级映射表。内容级失败（badResponse）适配器层重试无意义，由 parse 层处理。

## 缓存实现选择

| 实现 | 用途 | 注意 |
|---|---|---|
| `InMemoryAiParseCache` | 测试/预览；**壳层文本通道与拍照工厂的现行缺省** | 进程内 memo，重启即失 |
| `DriftAiParseCache(appDatabase)` | 生产持久留痕（ai_parses 表，本地件永不同步） | 需注入 AppDatabase；文本通道当前未接线（留痕由 feature_capture CaptureGateway 同事务落库） |

时效判定：`AiParseRecord.isFreshAt`（UUIDv7 内嵌时间，TTL `kAiParseCacheTtl`=7 天）+
promptVersion 闸门（文本 `w3-4-v1` / 拍照 `w11-12-photo-v1` 分轨，改提示词必须改版本号）。
同 hash 多条历史留痕取最新（UUIDv7 字典序=时间序）。

## 四级降级（degrade_hooks.dart，接缝在 core_ai、策略由宿主实现）

| 级别 | 场景 | 落点 | 状态 |
|---|---|---|---|
| 1 manualForm | 超时/解析失败 | 内建于 StructuredFailure（rawInput 保留 → 手填预填） | **已实现** |
| 2 deferredQueue | 断网 | `DeferredParseQueue.enqueue(DeferredParse)`（载荷含原输入/上下文/预计算 inputHash 防重复计费） | 接口预留，同步域接入 |
| 3 quotaNotice | 免费额度耗尽 | `AiQuotaGate.check()` → AiQuotaStatus(allowed, remainingToday)；**手填永不受限** | 接口预留，商业化接入 |
| 4 providerFallback | 供应商单点故障/涨价 | 编排层组合多个 LlmAdapter（拍照通道的 PhotoParser 双供应商已是该模式的落地实例） | 接口预留 |

## Fake 与真实通道切换

| Fake | 形态 | 用途 |
|---|---|---|
| `HeuristicFakeLlmAdapter` | 正则抽取任意输入（kcal/金额/商户「X」段）产受约束 JSON，**走完整管线** | 缺省装配默认 mock（key 未配）；与真实 adapter 行为同构，离线跑通闭环 |
| `FakeLlmAdapter.scripted/keyed` | 脚本桩（响应文本或异常按序弹出/关键字路由）；`requests` 记录请求供断言 | adapter 层单测；脚本耗尽抛 StateError |
| `FakeAiParser` | 绕过整条管线的 ParseResult 脚本桩 | feature 层控制器测试隔离网络与缓存 |
| `FakeDishAdapter.fixed/scripted` | 固定候选（宫保鸡丁+米饭）/脚本 | 拍照缺省装配与测试 |
| `FakeReceiptOcrAdapter.fixed/fromTextLines/repeating` | fixture 草稿 / 经共享抽取器走真实理解路径 / 恒定重复 | 小票缺省装配与测试 |

**切换条件**（三条通道一致）：真实凭据经 dart-define/环境变量编译期注入即自动切换——文本
看 `SLIMCA_AI_KEY` 是否非空；拍照看百度/AI 凭据组合；小票看 `SLIMCA_RECEIPT_OCR` 或平台。
唯一例外：拍照「仅配百度」时不以 Fake 充数（兜底缺位直接降级）。`String.fromEnvironment`
是编译期常量——运行期/测试不可改写，测试以显式参数注入覆盖。真实联调冒烟只经
`test/live_llm_smoke_test.dart`（`SLIMCA_AI_KEY` 缺席整组 skip，唯一网络豁免）。
