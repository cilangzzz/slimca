# feature_capture API —— 录入动线与方法索引

> 本包是 Flutter feature 层，无 REST/RPC 端点；「API 表面」= Riverpod Provider + 控制器/网关方法 + 注入接口 + 页面入口。
> AI adapter 的真实管线（超时/重试/纠错/供应商）在 core_ai，见 [../core_ai/README.md](../core_ai/README.md)；落库表语义见 [../core_db/README.md](../core_db/README.md)。

## 一、三条动线端到端链路

### 1. 手动记账（W2，money 档）

```
宿主 FAB / 路由
→ showCaptureSheet(context, seed) 或嵌入 CapturePage
→ captureControllerProvider(seed)（build：装载账本[空库惰性建默认账本]/分类/最近 chips/编辑回填）
→ 表单操作：inputDigit/inputDot/backspace/setAmountText/setDirection/setDate/setTitle/...
→ submit()
   ├─ 新建 → CaptureGateway.submitMoneyCapture(date, tzOffsetMin, title, amountMinor, direction,
   │        ledgerId, categoryId?, currency?)
   └─ 编辑 → CaptureGateway.applyMoneyCorrection(CaptureCorrectionRequest)（金额不可变=新增修正行）
→ 单事务：entries(kind=expense) + entry_lines(type=money) 落库
   + 两行快照同事务入队 sync_outbox（SyncOutboxWriter）
→ 返回 entryId；失败写 state.errorText 返回 null（不打断表单）
```

### 2. AI 双解析（W3-4，文本）

```
CaptureAiInput（input 阶段）→ CaptureController.startParse()
① 骨架先于任何 await（aiStage=parsing，§9.4 ≤100ms）
② 归一化 CaptureInputNormalizer.normalize + inputHash=sha256(规范化输入)
③ CaptureGateway.findCachedParse(inputHash, inputKind='text') → 命中(<7天)直接进确认卡
④ captureParserProvider.parse(CaptureParseRequest)（core_ai 桥接；文本 5s 超时 kCaptureParseTimeout）
⑤ result.checkUsable() 校验（title 非空/行非空/置信度∈[0,1]/kcal∈[0,5000]/金额>0）
   不过 → CaptureStructuredFailure(schema) → _enterManualFallback（原文保留）
⑥ saveAiParse → ai_parses 留痕（本地件，永不同步）→ _enterConfirm（AI 初值快照入 state）
→ 确认卡（CaptureConfirmCard：份量滑杆 setPortionMultiplier 联动 confirmKcal=round(base×倍率)）
→ CaptureController.submitPendingCapture() → CaptureGateway.submitAiCapture(CaptureAiSubmitRequest)
→ 单事务：entries + entry_lines(calorie/money) + food_items(逐菜品) + corrections 差异审计
   （aiInitials 非空时，source='ai_corrected'）+ 全部行快照入队 sync_outbox
```

### 3. 拍照通道（W11-12）

```
CapturePhotoEntry（拍照/相册双按钮 + §3.7 隐私提示）→ CaptureController.startPhotoCapture(fromCamera)
① captureImageSourceProvider.capturePhoto()/pickGallery()（image_picker 薄封装由壳注入；
   null=用户取消 → 原地回输入区）
② captureImageCompressorProvider.compress()（长边 1280/JPEG q80）→ content_hash=sha256(压缩字节)
③ findCachedParse(kind='photo')（本地查询，上云关闭口径仍可用）
④ raw_input 上云闸门 captureRawInputCloudEnabledProvider()：
   关(默认) → captureOnDeviceEstimatorProvider.estimate()（端侧粗估，不联网；
             null=无法估计 → _enterPhotoFallback 人工确认，字节全程不出端）
   开      → capturePhotoParserProvider.parse()（百度→Vision 双供应商，
             kCapturePhotoParseTimeout=12s；组合子 CapturePhotoParserFallback）
⑤ checkUsable 校验 → saveAiParse(kind='photo') → 确认卡（source=photo，pendingPhoto 在途态）
→ submitPendingCapture() → 落库（同上，kind 由行集合推导）→ 确认落库成功后：
   captureAttachmentStoreProvider.registerBurned(CaptureAttachmentDraft)（登记即 burned，
   blob_ref 恒 NULL）→ 删除本地临时文件 → photo_confirm 漏斗终点 + ≤15s 护栏 metric
```

## 二、Provider 索引（10）

| Provider | 类型 | 签名/缺省 | 说明 |
|---|---|---|---|
| `captureControllerProvider` | AsyncNotifierProvider.family.autoDispose | `<CaptureController, CaptureFormState, CaptureSeed>` | 表单状态机本体；seed.editEntryId 非空=编辑模式 |
| `captureGatewayProvider` | Provider\<CaptureGateway> | 必 override，读即抛 | 装配入口 `createCaptureGateway(db, clock, projection?)` |
| `captureParserProvider` | Provider\<CaptureParser> | 必 override，读即抛 | 文本解析接缝；宿主桥接 core_ai adapter |
| `captureImageSourceProvider` | Provider\<CaptureImageSource> | 必 override，读即抛 | 拍照/相册薄封装接缝；测试注入 FakeImageSource |
| `captureImageCompressorProvider` | Provider\<CaptureImageCompressor> | 必 override，读即抛 | 端侧压缩接缝；content_hash 同源键 |
| `capturePhotoParserProvider` | Provider\<CapturePhotoParser> | 必 override，读即抛 | 云端照片识别接缝（真实凭据 dart-define 注入，缺省 Fake） |
| `captureAttachmentStoreProvider` | Provider\<CaptureAttachmentStore> | 必 override，读即抛 | 即焚行登记；壳注 `DbCaptureAttachmentStore(AttachmentsDao(db))` |
| `captureRawInputCloudEnabledProvider` | Provider\<bool Function()> | 缺省恒 false | raw_input 上云开关（settings 同步读）；缺省=最严口径 |
| `captureOnDeviceEstimatorProvider` | Provider\<CaptureOnDeviceEstimator> | 缺省 `NoOnDeviceEstimator`（恒 null） | 端侧粗估；缺省即人工确认，**不抛错** |
| `capturePhotoTelemetryProvider` | Provider\<TelemetryService?> | 缺省 null | 漏斗/指标接收器；null=零副作用 |

## 三、页面入口（3）

| 入口 | 签名 | 说明 |
|---|---|---|
| `showCaptureSheet` | `Future<void> showCaptureSheet(BuildContext, {CaptureSeed seed, void Function(String entryId)? onSubmitted})` | 弹簧 bottomSheet 唤起；onSubmitted 是宿主**纯通知**（漏斗终点），抽屉关闭恒由页面自身 pop |
| `CapturePage` | `CapturePage({seed, onSubmitted})` | 可嵌入路由；按 side/aiStage 分流渲染 |
| `CapturePhotoEntry` | `CapturePhotoEntry({onCamera, onGallery})` | AI 流 input 阶段的拍照/相册入口段 + 上云口径隐私提示 |

## 四、CaptureGateway 方法索引（12 实例方法 + 1 装配工厂）

构造：`createCaptureGateway({required AppDatabase db, required HlcClock clock, DaySummaryProjection? projection})`——clock 必须应用级单例（HLC 单调性来源）。

| 方法 | 签名要点 | 落库与出网 |
|---|---|---|
| `submitMoneyCapture` | date/tzOffsetMin/title/amountMinor/direction/ledgerId/categoryId?/currency?/occurredAt? → entryId | entries + entry_lines 同事务，两行入 outbox；kind 恒 expense（收入由 direction=in 表达） |
| `applyMoneyCorrection` | CaptureCorrectionRequest → entryId | 主干变更=实体重建（status=edited、revision+1、created_at 保持）；金额行变更=新行 supersede 旧行；字段级 corrections 审计（source='user'）；全部写入同事务入 outbox；无真实变更零写入 |
| `submitAiCapture` | CaptureAiSubmitRequest → entryId | entries(kind 推导) + calorie/money 行 + food_items 逐菜品 + corrections(source='ai_corrected') 全同事务；全行快照入 outbox；ai_parses 不入（本地件） |
| `findCachedParse` | {inputHash, inputKind, maxAge=7d} → ({parseId, result})? | 只查本地 ai_parses；时效由 UUIDv7 id 内嵌时间戳判定；坏缓存视同未命中 |
| `saveAiParse` | {result, inputHash, inputKind} → parseId | ai_parses 留痕（raw_output=结果 JSON=缓存回放键）；raw_input 原文不落任何表 |
| `matchCategoryByHint` | hint?/expense → categoryId? | 按名称精确匹配内置分类；未命中回退「其他支出/其他收入」 |
| `ensureDefaultLedger` | () → CaptureLedgerOption | money 账本惰性建（幂等）；行快照同事务入 outbox |
| `ensureKcalLedger` | () → Ledger | 内置 kcal 账本兜底惰性建（幂等） |
| `loadRecentEntries` | {limit=kRecentChipLimit} → List\<CaptureRecentEntry> | 最近 chips（burn 行不入；装载失败由调用方兜底空列表） |
| `loadMoneyLedgers` | () → List\<CaptureLedgerOption> | money 账本（未归档未软删，按 sort） |
| `loadCategories` | direction → List\<CaptureCategoryOption> | 按 kind=expense/income 过滤 |
| `loadEditTarget` | entryId → CaptureEditTarget? | 编辑回填（entry + active money 行；不存在/已删/无金额行=null 退化新建） |
| `asEntryRepository` / `asEntryLineRepository` | getter | 供宿主把同一实现注册为全局仓库 |

## 五、CaptureController 方法索引（20）

状态读取：`ref.watch(captureControllerProvider(seed))`；写操作经 `.notifier`。

| 组 | 方法 | 语义要点 |
|---|---|---|
| 键盘 | `inputDigit` / `inputDot` / `backspace` / `setAmountText` | 纯字符串步进；分转换延迟到提交 |
| 手动表单 | `setManualKcalText` / `setDirection` / `selectCategory` / `selectLedger` / `setDate` / `setTitle` / `setNote` | 方向翻转重载分类，不匹配的已选分类清空 |
| 提交 | `submit` → Future\<String?> | W2 路径；失败写 errorText 返回 null |
| AI 文本流 | `setInputText` / `startParse` / `backToInput` | startParse 期间再入被拒；backToInput 保留原文与待焚原件 |
| 复记/滑杆 | `applyRecentChip(chip)` / `setPortionMultiplier(m)` | chip 复记日期刷新到今天、source=chip、无 AI 初值；倍率 clamp 0.5-2.0 |
| 单边开关 | `setSide(side)` | 切 money=放弃拍照通道（待焚文件即刻删）；其余档重置 AI 流但保留输入 |
| 拍照流 | `startPhotoCapture({required fromCamera})` | 守卫：仅 AI 流 input 阶段响应；分段呼吸态 |
| 统一提交 | `submitPendingCapture` → Future\<String?> | 确认卡/降级表单共用；拍照通道落库成功后即焚 |

## 六、注入接口契约（6）

| 接口 | 方法 | 实现约定 |
|---|---|---|
| `CaptureParser` | `parse(CaptureParseRequest)` | 失败抛 `CaptureStructuredFailure`；实现负责受约束解码与留痕字段 |
| `CaptureImageSource` | `capturePhoto()` / `pickGallery()` | 取消/失败返回 null 不抛；权限交互由实现自行处理 |
| `CaptureImageCompressor` | `compress(CapturePhotoFile)` → `CaptureCompressedImage` | contentHash 必须=sha256(输出字节)；失败抛异常走降级 |
| `CapturePhotoParser` | `parse(CapturePhotoParseRequest)` | 双供应商组合语义可用现成 `CapturePhotoParserFallback(primary, fallback)`（结构化失败/超时 → 兜底，兜底再失败向上抛） |
| `CaptureOnDeviceEstimator` | `estimate(CapturePhotoParseRequest)` → `CaptureParseResult?` | null=无法估计；该路径无云端解析，ai_parses 不落行 |
| `CaptureAttachmentStore` | `registerBurned(CaptureAttachmentDraft)` → rowId | **登记即焚**：返回时行已 burned（core_db DAO 先删文件再推状态机）；现成桥接 `DbCaptureAttachmentStore` |

## 七、常量与口径

| 常量 | 值 | 口径 |
|---|---|---|
| `kCaptureParseTimeout` | 5s | 文本解析超时（§7.4） |
| `kCapturePhotoParseTimeout` | 12s | 照片解析超时（全程 ≤15s 护栏含压缩与确认） |
| `kPhotoPathGuardMs` | 15000 | 拍照路径全程护栏；`photoPathWithinGuard(ms)` |
| `kMaxParseKcal` | 5000 | kcal 可信区间上限 |
| `kRecentChipLimit` | 5 | 最近 chips 条数（设计基线 3，实现取 5，常量可调） |
| `kCaptureCompressLongEdge` / `kCaptureCompressJpegQuality` | 1280 / 80 | 端侧压缩口径（实际执行由注入实现承担） |
| `kConfirmRingBudgetKcal` | 2000 | 确认卡热量环刻度（真实每日目标 W5-6 后替换） |
| `CapturePhotoFunnel.*` | photo_capture_open / photo_parse_result / photo_confirm | 漏斗事件名；props 只允许标量（outcome/latency_ms/错误**类型**码） |

提交按钮/锚点 Key：`captureSubmitKey`、`captureFallbackBannerKey`、`captureConfirmCardKey`、`captureConfirmSubmitKey`、`capturePortionSliderKey`、`captureLowConfidenceBannerKey`、`captureParseButtonKey`、`captureAiInputKey`、`capturePhotoCameraKey`、`capturePhotoGalleryKey` 等（widget 测试锚点，全量见各 widget 文件顶部）。
