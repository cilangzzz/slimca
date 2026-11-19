# pitfalls.md — core_ai 坑点清单

> 排序按跨模块影响面。每条都来自代码现状或真实联调记录。

## 1. 凭据纪律：key 只走 SLIMCA_* dart-define / 环境变量，绝不入仓库

所有凭据（`SLIMCA_AI_BASE/KEY/MODEL`、`SLIMCA_BAIDU_ACCESS_TOKEN` 或
`SLIMCA_BAIDU_API_KEY`+`SLIMCA_BAIDU_SECRET_KEY`、`SLIMCA_RECEIPT_OCR`）一律编译期注入；
文档与代码中只出现键名/占位符。`.gitignore` 已覆盖 `.env/.env.*`。唯一真实网络豁免是
`test/live_llm_smoke_test.dart`（`SLIMCA_AI_KEY` 环境变量缺席整组 skip）；其余测试一律
MockClient/Fake 离线。**跨模块影响**：任何新接入通道都要遵守同一纪律（docs/ops 算法备案
材料同口径）。

## 2. LLM 通道 id ≠ 展示名（DeepSeek 联调教训）

端点只认 API id（`deepseek-flash`/`deepseek-v4-pro`）；「DeepSeek-V4.1-Flash-1017」是展示名，
填入 SLIMCA_AI_MODEL 会得到 400 invalid_request_error。预设里 model 字段必须是端点 id。
**排查路径**：StructuredFailure.reason=invalidRequest + errors 带端点报文 snippet（截 300 字）
时先核对 model id。

## 3. 缓存时效与命中条件：三个闸门缺一不可

`<7 天`（UUIDv7 id 内嵌时间，**表无 created_at 列**）+ `promptVersion 相同`（文本
`w3-4-v1` / 拍照 `w11-12-photo-v1` 分轨）+ `inputHash 相同`。改提示词不 bump 版本 → 旧缓存
按新语义回放（脏数据）；负年龄（时钟回拨/跨设备导入）一律视为过期。input_hash 信封里
**mode 参与、日期与通道不参与**——不要"修复"日期不参与（这是常吃常花跨日命中的前提）。
非 v7 布局 id 抛 FormatException（判时效依赖它，不静默降级）。

## 4. 金额单位是分且类型严格：字符串 "1800"、小数 1800.5 都算类型错

校验器不做元/分猜测换算——口径错就交纠错重试。宿主侧展示层自行元→分换算时必须走与
`_yuanToFen`/`parseReceiptYuanToFen` 同款「两位小数上限、杜绝浮点」实现（壳层 parseYuanToFen
同口径内联，core_ai 不依赖壳层）。food_items 的 kcal 也是 int；菜谱侧数值传 int 入参经
num 归一化处理（历史 TypeError 教训在 core_db FoodItemsDao，见 ../core_db/README.md）。

## 5. 超时与重试是两层的，不要叠加也不要混用

适配器层：超时（文本 5s / 照片 12s / 百度 10s / 端侧 OCR 8s 骨架）+ 只重试 retryable 分类
（超时/网络/限流/5xx，线性退避 maxAttempts=2）。管线层：校验失败带纠错回喂重试 1 次
（maxValidationAttempts=2 含首发）。适配器抛非 LlmException 的异常（如硬 cast TypeError）
会**逃出降级映射**——所有供应商响应字段读取必须 `is` 检查容错。改超时口径时三处同步：
OpenAiCompatibleConfig.timeout、LlmRequest.timeoutOverride 使用点、工厂常量
（kPhotoBaiduTimeout/kPhotoVisionTimeout/kReceiptOcrTimeout）。

## 6. Fake 与真实通道的切换条件（及唯一例外）

切换由**编译期凭据注入**驱动（运行期不可改——`String.fromEnvironment` 是常量）：key 空 →
HeuristicFakeLlmAdapter / FakeDishAdapter.fixed / FakeReceiptOcrAdapter.fixed；key 非空 →
真实 adapter。测试不能靠改环境变量切通道，要用工厂显式参数注入。**唯一例外**：拍照「仅配
百度」时不以 Fake 充数（兜底缺位直接 StructuredFailure 降级手填——Fake 结果不可信，宁降级
不造假）。Fake 结果与真实通道同构走完整管线，因此缺省装配下确认卡也有真数据可改——
e2e 测试依赖这一点，不要绕过管线直接 mock ParseSuccess 之外的路径。

## 7. ai_parses 双写风险：壳层留痕走 CaptureGateway，不走 core_ai 缓存

壳层文本通道给 LlmAiParser 注入的是 `InMemoryAiParseCache`（进程内 memo）；持久留痕由
feature_capture CaptureGateway.saveAiParse 同事务落库。若宿主改为注入 `DriftAiParseCache`
又保留 CaptureGateway 落库，同一输入会出现两行 ai_parses（两套 raw_output 口径、entries.
ai_parse_id 溯源混乱）。接线前先读 ../feature_capture/README.md 的写路径约定。

## 8. http 包 ≥1.5 按响应 content-type 推断字符集

MockClient/联调构造响应体若不带 `charset=utf-8` 头，中文响应体会抛「Contains invalid
characters」（W11-12 集成期真实踩坑）。测试桩构造 http.Response 时必须带 charset 头。

## 9. 隐私字段边界：哪些字段允许上云/落库

拍照原图与小票原图即用即焚（不落 attachments、不进请求日志）；小票 OCR 全文 rawText 仅端侧
内存（不进结构化文本、不落 ai_parses、不上云）；`cloudParseConfirmed=false` 时云解析不得
发生（闸门在宿主 UI，core_ai 契约无法自验）；照片/小票的 StructuredFailure.rawInput 是描述
符（`photo:<hash>`/`receipt:ocr-*`）而非原文。跨模块改动任何留痕/日志路径前先核对本条。

## 10. LLM 直报热量不可信 + 未联查必须降置信度

拍照侧模型 kcal 只作 `kcalPer100gHint` 初值；联查未命中时置信度 ×0.8 且每百克热量退到本地
估计基准 150。宿主若自建解析路径复用 assembleDishParseJson，不要跳过 DishRefLookup 注入
点（红线 §7.1：确认卡 <0.5 强制高亮）。文本侧同理：refCalibrator 缺省透传 = ref_source
恒 llm/local，不要伪造 usda/off 来源。
