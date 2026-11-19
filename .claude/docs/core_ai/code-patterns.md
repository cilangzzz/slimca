# code-patterns.md — 扩展点操作路径

> 本模块最常被问的两个扩展问题：接入新 LLM 供应商、接入新识别/OCR 渠道。以下路径全部
> 基于现有代码的接缝写法，改动面最小。

## 一、接入新 LLM 供应商（OpenAI 兼容端点）

**若端点是 OpenAI 兼容协议（绝大多数）→ 不需要写任何 adapter 代码**：

1. `openai_adapter.dart` 的 `LlmModelPreset` 加一条 const 预设（id/provider/baseUrl/model/
   jsonCapability/vision/pricing），并加入 `all` 列表（供 fallback 编排遍历）。
   参照 DeepSeek 预设（818e59f）——从加预设到联调通过只改了 15 行。
2. capability 档位选择原则：端点支持 json_schema 信封才配 `jsonSchema` 档；兼容端点对信封
   支持参差时一律 `jsonObject` 宽档（正确性由 parse 层校验器兜底，不影响正确性）。
3. pricing：价目未实测就留 null（costMicro=0，**不虚报**）；实测后按「微元/1M tokens」补。
4. 冒烟联调：复用 `test/live_llm_smoke_test.dart` 模式——凭据走 `SLIMCA_AI_KEY`/`SLIMCA_AI_BASE`/
   `SLIMCA_AI_MODEL` 环境变量，缺席整组 skip（离线纪律不破）；失败时打印 StructuredFailure
   完整诊断（reason/errors/lastRawOutput/cause）。**严禁把 key 写进任何仓库文件**。
5. 壳层装配（apps/mobile `capture_parser_factory.dart`）：现行分支逻辑是「gpt-4o-mini 缺省
   模型配 jsonSchema 档、自定义模型配 jsonObject 档」——新供应商若走 SLIMCA_AI_MODEL 注入，
   无需改壳；若要改缺省模型，同步核对该分支的 capability 选择。
6. 模型 id 注意：**API id ≠ 展示名**（DeepSeek 教训），preset 的 model 字段必须是端点接受的 id。

**若端点协议非 OpenAI 兼容**：不要新造异常体系——按 `BaiduDishAdapter` 的写法把端点错误
映射进 `LlmException` sealed 家族（sealed switch 穷尽会强制你接入降级映射），重试纪律
（只重试 retryable=true）与超时语义对齐。

## 二、接入新菜品识别渠道（拍照通道）

1. 实现 `ImageDishAdapter` 四成员：providerId/modelId/dishRefSource（识别库=baidu 类、
   Vision LLM=llm）/`recognize(CompressedImage)`。
2. 契约红线：输入恒为端侧压缩规范形（原图不出压缩机）；**识别不出返回空列表**（不抛异常
   ——编排层据此切兜底供应商）；失败抛 LlmException 分类异常；自带超时+瞬时重试（口径同
   LlmAdapter）。
3. 装配：`createPhotoParser` 的 `visionAdapter` 参数可注入任意 ImageDishAdapter（测试/灰度）；
   正式接入改 photo_factory.dart 的装配顺序（**顺序=优先级**，百度先行）。
4. 候选字段容错参照 `extractDishes`/百度 adapter 的写法：`is` 检查代替硬 cast，坏类型逐项
   跳过而非崩溃（TypeError 逃出 LlmException 分类体系会绕过降级映射）。
5. 若新渠道有份量输出，直接填 DishCandidate.grams；无份量输出填 defaultPortionG 基准。

## 三、接入新端侧 OCR 渠道（小票通道）

1. native 侧（Kotlin/Swift，壳层 apps/mobile）按通道协议实现 handler：通道名
   `slimca/receipt_ocr`、method `recognizeReceipt`、args `{imageBytes, mime}`、result
   `{textLines: [...]}`（按阅读序；兼容整段 text）。core_ai 侧骨架已就绪（MlKit/Vision
   两个类只是 providerId/modelId 不同）。
2. core_ai 侧零改动即可用：`defaultReceiptOcrAdapter` 按平台装配；显式指定用
   `--dart-define=SLIMCA_RECEIPT_OCR=mlkit|vision`。MissingPluginException 已被
   `MethodChannelReceiptOcrChannel` 包装为 invalidRequest（未接线平台 → 一级降级手填，
   不崩不造假）。
3. 新平台（如桌面端 OCR）：实现 `ReceiptOcrAdapter`，**禁 HTTP/云端路径**（契约红线）；通道
   结果形状违约抛 badResponse；字段理解复用共享抽取器 `extractReceiptFields`（不要在
   adapter 里自行解析字段——「识别/理解」分层保证双平台共享同一理解逻辑与测试路径）。
4. 已知抽取局限（真机样本后迭代）：多行合计、抹零/负数优惠行、行尾纯数字噪声、二维码区。

## 四、接入食物库联查（解锁校准红线）

两条独立钩子，宿主注入实现，core_ai 缺省透传：

- 文本侧 `AiRefCalibrator.calibrate(ParsedFoodItemDraft)`：改写 item 的 kcal/ref_source/ref_id
  （是否回写行级金额由实现决定并在 parse_notes 说明）。构造 LlmAiParser 时传 refCalibrator。
- 拍照侧 `DishRefLookup.lookup(dishName) → DishRefEntry?`：命中后覆写份量/每百克热量/
  ref_source/ref_id，并**取消置信度 0.8 降档**（未联查的热量必须低置信标注是红线）。构造
  PhotoParser 时传 refLookup。
- 快表数据（USDA CC0 + OpenFoodFacts ODbL）属后续里程碑；接入时 id 映射同样走「宿主注入」
  模式，勿在 core_ai 内复制数据。

## 五、新增确定性 Fake（测试/缺省装配风格）

遵循本包既有三形态风格（ scripted / fixed / fromTextLines(repeating)）：

1. 脚本项要么是结果类型、要么是 LlmException；**脚本耗尽抛 StateError**（显式暴露测试与
   预期调用次数不符，不静默重复）。
2. 记录收到的输入（`inputs`/`images` 列表 + lastXxx getter）供断言；零延迟零网络零时钟。
3. 缺省装配工厂（photo_factory/receipt_factory）的纪律：**真实凭据缺位 → Fake；但真实凭据
   配了一半（如仅百度）→ 不以 Fake 充数**，宁可降级。

## 六、修改提示词 / Schema（高危操作路径）

1. 改 `buildSystemPrompt` / `buildParseJsonSchema` / `buildPhotoSystemPrompt` 后**必须同步
   bump `kPromptVersion` 或 `kPhotoPromptVersion`**——否则旧缓存按新版本语义回放（回放
   兼容性闸门失效）。
2. 校验规则改动同步核对 parser_validation_test 的断言矩阵；kcal 上限 5000、金额单位分等
   口径在 schema、校验器、测试三处一致。
3. 内置分类名单改动：core_db seed（运行期真值）与 `kDefaultPresetCategoryNames`（提示词
   枚举兜底名单）两处同步，见 [pitfalls.md](pitfalls.md)。
