# Changelog - core_ai

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。类型映射：修复→fix、新增/支持→feat、优化→perf、调整→refactor。

---

## [2026-11-17] 联调：DeepSeek 通道打通（deepseek-flash）+ 真实冒烟测试

**类型**: feat
**提交**: 818e59f
**风险**: LOW

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/lib/src/llm/openai_adapter.dart | +14/-1 | 新增 `LlmModelPreset.deepseek` 预设（api.deepseek.com/v1、jsonObject 档、vision=true、pricing=null 不虚报）+ 「API id≠展示名」注释记录 400 invalid_request_error 教训 |
| packages/core_ai/test/live_llm_smoke_test.dart | +112/-0 | 真实联调冒烟（全仓唯一网络豁免文件）：文本双解析 + 多模态格式探针；`SLIMCA_AI_KEY` 环境变量缺席整组 skip；失败打印 StructuredFailure 完整诊断 |
| packages/core_ai/test/openai_adapter_test.dart | +12/-3 | 预设清单断言同步（all 含 deepseek） |

### 影响范围
- **API**: 新增可选预设，未改任何既有接口；`LlmModelPreset.all` 多一个元素（遍历 fallback 编排的调用方感知）。
- **跨模块**: 无（本提交只改 core_ai）。凭据纪律同步收紧：key 只走环境变量/--dart-define，`.gitignore` 覆盖 .env。
- **配置**: 无 schema/配置变更；价目 pricing=null → costMicro 恒 0。

---

## [2026-11-17] W16 端侧小票 OCR + HeuristicFake 商户抽取（M3 闸门：V1 收官）

**类型**: feat
**提交**: 11b5ce2
**风险**: MEDIUM（core_ai 侧纯新增子系统；默认 mock 标题行为有向后兼容变化）

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/lib/src/receipt/receipt_models.dart | +161/-0 | ReceiptImageInput/ReceiptDateTime（occurredAtMsUtc 真实日历日双校验）/ReceiptLineItem/ReceiptDraft（rawText 仅端侧内存） |
| packages/core_ai/lib/src/receipt/receipt_field_extractor.dart | +347/-0 | 纯 Dart 保守正则抽取器：合计关键词「实收/实付」优先、行尾金额锚点、宁缺不错 |
| packages/core_ai/lib/src/receipt/receipt_parser.dart | +266/-0 | 三态编排（Prefill/Parsed/Failed）+ `cloudParseConfirmed` 用户确认闸门 |
| packages/core_ai/lib/src/receipt/receipt_text_bridge.dart | +68/-0 | ReceiptDraft→结构化文本（最小字段集上云；明细只带品名 ≤10 条，金额恒单边 money 一行） |
| packages/core_ai/lib/src/receipt/receipt_ocr_adapter.dart | +56/-0 | ReceiptOcrAdapter 抽象 + 通道协议常量（slimca/receipt_ocr）+ 超时骨架 8s |
| packages/core_ai/lib/src/receipt/receipt_ocr_channel.dart | +46/-0 | MethodChannel 桥：MissingPluginException→invalidRequest、PlatformException→badResponse |
| packages/core_ai/lib/src/receipt/platform_receipt_ocr_adapters.dart | +113/-0 | ML Kit（Android）/Vision（iOS）骨架；native handler 待壳层接线（真机验收 remaining） |
| packages/core_ai/lib/src/receipt/receipt_factory.dart | +83/-0 | dart-define 装配工厂（SLIMCA_RECEIPT_OCR=mlkit|vision|fake，未指定按平台） |
| packages/core_ai/lib/src/fake/fake_receipt_ocr_adapter.dart | +137/-0 | scripted/fixed/fromTextLines/repeating 四形态 fixture |
| packages/core_ai/lib/src/fake/heuristic_fake_adapter.dart | +18/-3 | 商户全角引号「X」段抽取（小票确认卡标题可读；无「」返回 null 向后兼容——**默认 mock 标题行为变化**） |
| packages/core_ai/lib/core_ai.dart | +19/-2 | 导出新 receipt 域与 fake |
| packages/core_ai/test/receipt_field_extractor_test.dart 等 4 个测试 | +903/-0 | 抽取器/适配器/管线/共享 fixture 测试 |

### 影响范围
- **API**: 新增 receipt 子系统全量导出；HeuristicFakeLlmAdapter 产出的 title 在输入含「商户」时由原文变商户名（缺省装配行为变化，向后兼容）。
- **跨模块**: 同提交改了 packages/ui_kit（16 文件，主题编辑器/主题包/WCAG 护栏）与 apps/mobile（14 文件，设置页/主题控制器/装配）——主题域变更见 ../ui_kit/ 相应文档。
- **数据模型**: 无（ai_parses/entries 未动；端侧 OCR 不留痕）。
- **配置**: 新增 dart-define 键 `SLIMCA_RECEIPT_OCR`。

---

## [2026-11-17] W11-12 拍照通道：双供应商识别管线+端侧压缩+即焚

**类型**: feat
**提交**: 19d439b
**风险**: MEDIUM（core_ai 侧新增拍照子系统 + LlmMessage 多模态 API 扩展；同提交含 core_db 数据模型加列）

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/lib/src/photo/photo_parser.dart | +488/-0 | 双供应商 fallback 编排 PhotoParser + computePhotoInputHash + assembleDishParseJson（联查>直报>本地估计、未联查置信度 ×0.8） |
| packages/core_ai/lib/src/photo/baidu_dish_adapter.dart | +385/-0 | 百度菜品识别 v2 适配器：AK/SK OAuth2 token 进程内缓存（到期前 60s）、业务错误码分类（17/19 额度、18 限流、6/100/110/111 鉴权、216201/216202 图片非法） |
| packages/core_ai/lib/src/photo/vision_dish_adapter.dart | +169/-0 | Vision LLM 兜底（data-url 内联压缩图）+ extractDishes 宽容提取 |
| packages/core_ai/lib/src/photo/photo_factory.dart | +137/-0 | dart-define 装配工厂（SLIMCA_BAIDU_*/SLIMCA_AI_*；全缺省 Fake；仅百度不以 Fake 充数） |
| packages/core_ai/lib/src/photo/image_compressor.dart | +119/-0 | PureDartImageCompressor：EXIF 烘焙→长边 1280 只缩不放大→JPEG q80 |
| packages/core_ai/lib/src/photo/photo_models.dart | +148/-0 | PhotoImageInput/CompressedImage/DishCandidate/ImageDishAdapter 抽象 + 三个基准常量 |
| packages/core_ai/lib/src/llm/llm_adapter.dart | +52/-3 | **API 扩展**：sealed LlmContentPart（LlmTextPart/LlmImageUrlPart）+ LlmMessage.parts 多模态构造（非 const，List.unmodifiable） |
| packages/core_ai/lib/src/llm/openai_adapter.dart | +27/-2 | 多模态 content 数组序列化（text/image_url 段） |
| packages/core_ai/lib/src/parse/parse_schema.dart | +35/-0 | buildPhotoSystemPrompt（拍照恒单边热量口径） |
| packages/core_ai/lib/src/fake/fake_dish_adapter.dart | +111/-0 | scripted/fixed 菜品识别假适配器 |
| packages/core_ai/lib/core_ai.dart | +20/-3 | 导出 photo 域 |
| packages/core_ai/pubspec.yaml | +4/-1 | 新增 `image: ^4.5.0` 依赖（纯 Dart 编解码，测试离线可跑真实 codec） |
| packages/core_ai/test/baidu_dish_adapter_test.dart 等 7 个测试 | +1670/-0 | 适配器/压缩/管线/草稿/工厂测试 |

### 影响范围
- **API**: LlmMessage 新增多模态构造（纯文本主构造不变，向前兼容）；新增 PhotoParser 全量导出。
- **跨模块**: 同提交改了 packages/core_db（attachments 加 status/burned_at 两列 + AttachmentsDao 即焚状态机——**数据模型变更**，见 ../core_db/README.md）、packages/feature_capture（16 文件，拍照录入域）、apps/mobile（20 文件，权限/相机/装配）。
- **集成修复（同提交）**: http ≥1.5 中文响应体必须带 charset=utf-8（MockClient 契约）；LlmMessage.parts 去除非法 const。
- **数据模型**: core_db attachments 表加列（schemaVersion 保持 1，beforeOpen 幂等回填）。

---

## [2026-11-16] W5-6 语音 Fake 链路：HeuristicFakeLlmAdapter（缺省离线桩）

**类型**: feat
**提交**: 3022e4d
**风险**: LOW（纯新增文件 + 导出；无既有行为变化）

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/lib/src/fake/heuristic_fake_adapter.dart | +136/-0 | 确定性启发式假 LLM：正则抽取 kcal/金额（元→分）产 §7.2 受约束 JSON——key 未配时经 LlmAiParser 走完整管线的默认 mock |
| packages/core_ai/lib/core_ai.dart | +4/-1 | 导出新 fake |

### 影响范围
- **API**: 新增 HeuristicFakeLlmAdapter（const 构造）；壳层语音 Fake 链路（同提交 apps/mobile 接线）依赖它离线跑通 AI 闭环。
- **跨模块**: 同提交改了 feature_sync（新增包）、feature_plan、feature_ledger、core_db、apps/mobile——本包侧无接口变化。
- **数据模型/配置**: 无。

---

## [2026-11-16] W3-4 AI 双解析闭环（文本路径）：管线/缓存/Fake 全量初建

**类型**: feat
**提交**: 5b456e3
**风险**: HIGH（模块核心流程初建，数据模型与降级映射全部落定；feature_capture/壳层从此依赖本管线）

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/lib/src/parse/parse_validator.dart | +517/-0 | 受约束 JSON 解码+字段校验+§7.3 映射（金额>0 分、kcal∈[0,5000]、confidence 必填、单边越界行丢弃记 note） |
| packages/core_ai/lib/src/parse/parse_models.dart | +357/-0 | ParseInput/ParseContext/ParseMode/ParsedLineDraft/ParsedFoodItemDraft/ParseSuccess/StructuredFailure/AiFailureReason/AiDegradeLevel |
| packages/core_ai/lib/src/parse/ai_parser.dart | +346/-0 | LlmAiParser 管线编排（规范化→input_hash→缓存回放→受约束请求→校验→纠错重试 1 次→值返回失败） |
| packages/core_ai/lib/src/llm/openai_adapter.dart | +349/-0 | OpenAI 兼容适配器（response_format 两档 capability、重试纪律、HTTP 状态码→LlmException 分类） |
| packages/core_ai/lib/src/llm/llm_adapter.dart | +254/-0 | LlmAdapter 抽象 + sealed LlmException 家族（8 分类，retryable 位） |
| packages/core_ai/lib/src/parse/parse_schema.dart | +216/-0 | normalizeParseInput/computeInputHash（信封 v1）/buildParseJsonSchema/buildSystemPrompt/buildRetryInstruction + kPromptVersion='w3-4-v1' |
| packages/core_ai/lib/src/cache/ai_parse_cache.dart | +169/-0 | AiParseRecord（UUIDv7 内嵌时间判 7 天时效）+ AiParseCache 抽象 + InMemoryAiParseCache |
| packages/core_ai/lib/src/cache/drift_ai_parse_cache.dart | +42/-0 | Drift 直读直写 ai_parses（ORDER BY id DESC 取最新、replace upsert） |
| packages/core_ai/lib/src/parse/parse_categories.dart | +125/-0 | CategoryResolver/PresetCategoryResolver + 22 内置分类名单 |
| packages/core_ai/lib/src/degrade/degrade_hooks.dart | +69/-0 | 二级 DeferredParseQueue/三级 AiQuotaGate 接口预留 |
| packages/core_ai/lib/src/fake/fake_adapter.dart + fake_parser.dart | +194/-0 | FakeLlmAdapter（scripted/keyed）+ FakeAiParser（脚本桩，耗尽抛 StateError） |
| packages/core_ai/pubspec.yaml | +16/-38 | workspace 化 + 新增 core_db/core_domain/drift/crypto 依赖 |
| packages/core_ai/test/parser_validation_test.dart 等 6 个测试 | +1615/-12 | 校验矩阵/缓存/重试失败/adapter/fakes 测试（占位 core_ai_test.dart 移除） |

### 影响范围
- **API**: 模块 API 面从零到全量——AiParser/LlmAdapter/AiParseCache 三抽象与全部错误分类；此后 feature_capture 与壳层全部 AI 调用走本管线。
- **跨模块**: 同提交改了 feature_capture（CaptureParser 注入点/确认卡/CaptureGateway.submitAiCapture 落库）、ui_kit（呼吸态/确认卡/count-up）、apps/mobile（lib/ai 装配工厂 SLIMCA_AI_BASE/KEY/MODEL）。
- **数据模型**: ai_parses 表开始被读写（留痕/缓存）；entries.ai_parse_id 溯源建立。
- **同提交修复的初版缺陷**（踩坑记录，勿重蹈）: ai_parser 收尾传参（validated 命名参数）、LlmServerException 降级映射缺失（switch 非穷尽）、baseUrl 尾斜杠 Uri.resolve 丢 /v1 路径、calorie 行 category_hint 未走分类解析。

### 回滚指南（HIGH）
- 回滚: `git revert 5b456e3`（**不建议直接 revert**——后续 W5-6/W11-12/W16 全部叠加在本管线上，revert 必然级联冲突；若需应急，优先在壳层把 createCaptureParser 固定回 HeuristicFakeLlmAdapter 缺省装配而非拆管线）。
- 检查文件: packages/core_ai/lib/src/parse/*、packages/core_ai/lib/src/llm/*、apps/mobile/lib/ai/*（装配工厂/桥）、feature_capture 的 CaptureGateway。
- 副作用: 文本 AI 解析闭环整体失效（feature_capture 确认卡无预填来源）；ai_parses 留痕/缓存消失；e2e_ai_confirm 等测试链路报废。

---

## [2026-11-16] W1 环境与地基：core_ai 包骨架（pub workspace）

**类型**: chore
**提交**: 3b1f64c
**风险**: LOW

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| packages/core_ai/pubspec.yaml | +55/-0 | 包定义（workspace 成员；初始依赖） |
| packages/core_ai/lib/core_ai.dart | +5/-0 | 库入口占位 |
| packages/core_ai/README.md + CHANGELOG.md + LICENSE + analysis_options.yaml | +47/-0 | 包元信息 |
| packages/core_ai/.gitignore + .metadata | +41/-0 | Flutter 包脚手架 |
| packages/core_ai/test/core_ai_test.dart | +12/-0 | 占位冒烟（W3-4 中移除） |

### 影响范围
- **API**: 无（空壳）。
- **跨模块**: 同提交建立全仓 10 包 workspace、core_db schema v1、CI——仓级基建见各模块文档。
- **配置**: pub workspace 布局确定，resolution: workspace。
