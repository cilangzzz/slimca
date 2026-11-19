# feature_capture —— 录入域（V1 核心动线）

> 源码：`packages/feature_capture`（pub workspace 业务层包）
> 一句话：**记一笔的完整动线**——手动记账 / AI 双解析（文本、拍照）→ 确认卡 → 同事务落库 + 出网入队 + 拍照即焚 + 漏斗埋点。

## 模块概述

录入域承载 V1 的核心写路径，三条动线共用一个 Riverpod 控制器状态机：

- **W2 手动记账**：数字键盘金额（整数分存储）→ 方向/分类/账本/日期/备注 → `CaptureGateway.submitMoneyCapture` 落库；编辑模式恒走此表单，金额不可变（新增 correction 行 supersede 旧行）。
- **W3-4 AI 双解析（文本）**：一句话输入 → `input_hash` 缓存（7 天）→ 注入的 `CaptureParser`（adapter 在 core_ai）→ 校验器 → 确认卡（AI 初值预填 + count-up + 热量环 sweep + 置信度三档 + 份量滑杆联动重算）→ `submitAiCapture` 同事务落 5 类表；失败自动降级手填、原文保留。
- **W11-12 拍照通道**：拍照/相册 → 端侧压缩（长边 1280、JPEG q80）→ raw_input 上云闸门分流（默认关=字节不出端走端侧粗估；开=12s 云端识别，百度→Vision 双供应商）→ 确认卡复用 → 落库成功后「解析后即焚」（attachments 登记 burned + 临时文件删除）。

## 依赖关系

| 方向 | 包 | 依赖内容 |
|------|-----|---------|
| 上游 | core_domain | 领域实体（Entry/EntryLine）、HlcClock、LineDirection/EntryKind/EntrySource 枚举、TelemetryService 接口 |
| 上游 | core_db | DriftEntryRepository / DriftEntryLineRepository / SyncOutboxWriter / AttachmentsDao / AppDatabase / generateUuidV7（**持久化实现全在 core_db，本包只编排**） |
| 上游 | core_ai | LLM adapter 与受约束解码（本包只定义 `CaptureParser` 接口，宿主桥接，见 [../core_ai/README.md](../core_ai/README.md)） |
| 上游 | ui_kit | SlimcaConfirmCard / SlimcaBreath / SlimcaCountUp / SlimcaCalorieRing / SlimcaConfidenceDot / 语义 token |
| 下游 | apps/mobile | 壳装配（override 全部注入点）、image_picker 薄封装、相机权限、go_router 唤起抽屉 |

## 对外 API 索引

完整签名与动线步骤见 [api-capture.md](api-capture.md)。总量 52 个：10 Provider + 12 网关实例方法（另有装配工厂 `createCaptureGateway`）+ 20 控制器方法 + 6 注入接口 + 3 页面入口。

**Provider（10 个，`§10.4 壳负责装配`纪律）**：

| Provider | 装配要求 | 缺省行为 |
|---|---|---|
| `captureGatewayProvider` | **必 override**（`createCaptureGateway(db, clock, projection?)`） | 读即抛 UnimplementedError |
| `captureParserProvider` | **必 override**（core_ai adapter 桥接） | 读即抛 |
| `captureImageSourceProvider` | **必 override**（image_picker 薄封装） | 读即抛 |
| `captureImageCompressorProvider` | **必 override**（端侧压缩插件） | 读即抛 |
| `capturePhotoParserProvider` | **必 override**（百度→Vision 组合） | 读即抛 |
| `captureAttachmentStoreProvider` | **必 override**（`DbCaptureAttachmentStore(AttachmentsDao(db))`） | 读即抛 |
| `captureRawInputCloudEnabledProvider` | 可 override（settings 同步读） | 恒 false（字节不出端） |
| `captureOnDeviceEstimatorProvider` | 可 override（端侧 OCR/模型） | `NoOnDeviceEstimator` 恒 null → 人工确认 |
| `capturePhotoTelemetryProvider` | 可 override（TelemetryService） | null（不发事件） |
| `captureControllerProvider` | 无需装配（family.autoDispose，参数 `CaptureSeed`） | 控制器本体 |

**页面入口（3 个）**：`showCaptureSheet(context, seed, onSubmitted)`（弹簧 bottomSheet）、`CapturePage`（可嵌入路由）、`CapturePhotoEntry`（拍照/相册双按钮 + 隐私提示段）。

**核心方法速查**：控制器 `startParse` / `startPhotoCapture(fromCamera)` / `submitPendingCapture` / `submit`（手动）/ `applyRecentChip` / `setPortionMultiplier`；网关 `submitMoneyCapture` / `applyMoneyCorrection` / `submitAiCapture` / `findCachedParse` / `saveAiParse` / `matchCategoryByHint` / `loadRecentEntries` / `ensureDefaultLedger` / `ensureKcalLedger`。

## 关键流程（非平凡部分）

- **手动写路径**：表单校验（`canSubmit`）→ `submit()` → 网关单事务 `entries + entry_lines` 落库 + 行快照同事务入队 sync_outbox。
- **AI 文本路径**：`startParse()` 骨架先于任何 await（≤100ms）→ 缓存命中直复用 → 解析（5s 超时）→ `checkUsable` 校验（坏输出不落 ai_parses）→ 确认卡 → `submitPendingCapture()`。
- **拍照路径**：呼吸态分段文案（压缩中…→识别中…/端侧粗估中…）→ `content_hash=sha256(压缩字节)` 一址两用（attachments 去重键 + ai_parses photo 缓存键）→ 闸门分流 → 确认落库成功后才登记 attachments（登记即 burned）并删临时文件；失败降级时待焚原件**保留**（确认前绝不焚）。
- **漏斗埋点**：photo_capture_open → photo_parse_result（outcome: success/cache/on_device/manual/fallback）→ photo_confirm；全程护栏 15s（`kPhotoPathGuardMs`），metric 复用 `capture_open_to_confirm_ms`、`tags.path='photo'`。

## 数据模型

表单状态机、提交载荷、解析模型（JSON 口径 = ai_parses.raw_output 缓存格式）、落库映射表 → [data-model.md](data-model.md)。底层 21 表 schema 与同步语义见 [../core_db/README.md](../core_db/README.md)。

## 模块配置（宿主装配）

```dart
captureGatewayProvider.overrideWithValue(
  createCaptureGateway(db: AppDatabase, clock: HlcClock 单例,
      projection: DaySummaryProjection?))   // 可选，联动仪表盘投影
captureParserProvider.overrideWithValue(coreAiAdapterBridge)  // 见 ../core_ai/
captureAttachmentStoreProvider.overrideWithValue(
  DbCaptureAttachmentStore(AttachmentsDao(db)))
// 拍照通道另需：captureImageSource / captureImageCompressor /
// capturePhotoParser（dart-define 键 SLIMCA_AI_*、SLIMCA_BAIDU_*，
// 凭据一律走 --dart-define，真实凭据待联调，缺省 Fake）
```

## 详细文档

- [api-capture.md](api-capture.md) —— 三条动线完整链路 + Provider/方法/接口全量索引
- [data-model.md](data-model.md) —— CaptureFormState 状态机、提交载荷、解析模型、落库映射
- [code-patterns.md](code-patterns.md) —— 注入接缝/事务编排/哨兵 copyWith 等模式与扩展点
- [pitfalls.md](pitfalls.md) —— 已知坑点（含 capture_photo_test 已知 flaky）
- [CHANGELOG.md](CHANGELOG.md) —— 模块变更历史（6 条，最新在上）

## 已知坑点摘要

1. `CaptureAiStage` 枚举**禁止加值**——Dart 3 穷举 switch 是编译期硬约束，会破坏宿主面板；新通道复用 `parsing` + `photoProcessingLabel` 分段文案模式。
2. AI/拍照任何失败都降级手填、原文保留，输入页永不卡死；拍照降级时已拍原件保留到确认落库成功。
3. 金额一律整数分、纯字符串运算，浮点禁入；编辑=新增 correction 行，金额永不原地改。
4. capture_photo_test 已知 flaky（pump+runAsync 桥热机负载偶发超帧预算），详见 [pitfalls.md](pitfalls.md)。
5. 相机/存储权限与真实插件实现归壳层（`CaptureImageSource` 抽象不建模权限），真机验收时权限拒绝路径在壳层测。

## 测试布局（4 文件 31 例）

| 文件 | 内容 |
|---|---|
| test/capture_flow_test.dart（853 行） | 手动 + AI 文本流 widget 测试（8 例） |
| test/capture_money_test.dart（101 行） | CaptureMoney 元↔分互转与键盘步进单测（3 组） |
| test/capture_outbox_test.dart（600 行） | 网关事务写入 + outbox 同事务入齐断言（7 例，内存真库） |
| test/capture_photo_test.dart（830 行） | 拍照通道全链路（6 例：主链路/缓存/上云关/端侧无法估计/失败降级/相册），宿主缺 sqlite3 时温和跳过 |
