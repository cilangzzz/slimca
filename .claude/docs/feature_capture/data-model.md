# feature_capture 数据模型

> 本包的状态与载荷模型都在 lib/src/capture_models.dart、capture_parser.dart、capture_photo_models.dart；
> 底层表 schema（21 表、facet 拆行、HLC 公共列）与同步语义见 [../core_db/README.md](../core_db/README.md)。

## 一、表单状态机（CaptureFormState）

控制器值类型，不可变，经 `copyWith` 更新。可空字段用哨兵参数 `Object? xxx = _unchanged` 区分「不改动」与「置 null」（见 [code-patterns.md](code-patterns.md) 哨兵模式）。

**三态枚举**：

- `CaptureSide { both, money, calorie }`（单边开关；`wire` 存储文本）。money=W2 手动表单，也是降级目标；calorie=只产 calorie 行。
- `CaptureAiStage { input, parsing, confirm, manualFallback }`（AI 流状态机）。**禁止加值**——拍照通道复用 `parsing` + `photoProcessingLabel` 分段文案，不新增枚举值（Dart 3 穷举 switch 编译期硬约束）。

**关键派生量**（决定按钮可用性，别在 UI 里重复实现）：

| 派生量 | 语义 |
|---|---|
| `amountMinor` | `CaptureMoney.toMinorUnits(amountText)`；非法/空 = null |
| `isEditing` | `editTarget != null`（编辑恒走 money 表单） |
| `isAiFlow` | `side != money` |
| `hasPendingPhoto` | `pendingPhoto != null`（source 恒记 photo，与 aiStage 无关） |
| `showCalorieInConfirm` / `showMoneyInConfirm` | 单边开关裁剪确认卡区域 |
| `canSubmit` | money 档：金额>0 且 ledgerId 已选且非 submitting |
| `canConfirm` | confirm 阶段：至少一行产出；有金额必须已选账本；calorie 档必须有热量 |
| `manualKcalValue` / `manualKcalInvalid` | 降级热量输入：空=未填；非法/超 [0,5000]=null（禁提交） |
| `canSubmitFallback` | manualFallback 阶段：至少一行产出 + 热量合法 + 账本约束 |
| `selectedCurrency` | 所选账本币种（money 行默认 CNY） |

**在途拍照态**：`pendingPhoto: CapturePendingPhoto?`（contentHash/mime/sizeBytes/localPath）——确认落库成功后才焚；`photoProcessingLabel: String?`——非空=parsing 阶段的拍照处理等待文案（压缩中…→识别中…/端侧粗估中…）。

## 二、提交载荷

### CaptureAiSubmitRequest（确认卡/降级/复记统一写路径）

| 字段 | 类型 | 口径 |
|---|---|---|
| date / tzOffsetMin | String / int | yyyy-MM-dd 本地日历日 + 时区偏移 |
| title / note | String / String? | AI 建议/用户改写/原文；备注空白归一 null |
| source | EntrySource | text（AI 解析）/ chip（复记）/ manual（降级）/ photo（拍照含降级） |
| aiParseId | String? | → ai_parses.id 溯源；chip/manual/端侧粗估路径为 null |
| kcal / kcalConfidence | int? / double? | calorie 行；AI 产出行 confidence 必填 |
| amountMinor / moneyDirection / ledgerId / currency | | money 行（分）；direction 默认 outcome；ledgerId 在有金额时必填 |
| items | List\<CaptureConfirmedItem> | 菜品明细（份量滑杆联动重算后数值）→ food_items 逐行 |
| portionMultiplier | double? | 1.0 可空省略；随 calorie 行 payload 摘要留痕 |
| aiInitials | CaptureAiInitials? | AI 初值快照；非空时网关写差异审计行；chip/manual 为 null |

`hasCalorie` / `hasMoney` = 数值>0。**kind 推导**（网关内）：双行=mixed、仅热量=food、仅金额=expense。文档枚举无 meal/income kind——收入由行级 direction=in 表达。

### CaptureCorrectionRequest（编辑模式）

entryId + oldLineId（被修正旧行）+ 金额/方向/分类/账本/标题/备注/日期/时区。仅 money 行可修正，且旧行必须 status=active、未墓碑；无真实变更时零写入直接返回 entryId。

### CaptureAiInitials（差异审计「前值」）

title/kcal/kcalConfidence/moneyMinor/moneyConfidence/categoryId——来自解析结果（或缓存），落库时与用户确认值逐字段比对，差异落 corrections（source='ai_corrected'，append-only）。

## 三、解析模型（ai_parses.raw_output 的 JSON 口径）

`CaptureParseResult` 及其子对象全部可 JSON 序列化（toJson/fromJson），**序列化形态即 ai_parses.raw_output 缓存回放格式**——改字段会破坏既有缓存反序列化兼容。

| 对象 | 要点 |
|---|---|
| CaptureParseResult | title / parseNotes? / lines[] / provider / model / promptVersion / latencyMs / costMicro / confidence |
| CaptureParsedLine | typeWire（'calorie'/'money'）、amountKcal 或 amountMinor、confidence、categoryHint、items[] |
| CaptureParsedItem | name/portionG/kcal/proteinG/carbG/fatG/refSource(usda/off/baidu/local/llm)/refId/confidence |
| CaptureParseRequest | rawText（原文，adapter 不留档）/ normalizedText / inputHash / inputKind(text/photo/voice) |

校验器 `checkUsable()`：title 非空、lines 非空、每行 confidence∈[0,1]、kcal∈[0,5000]（kMaxParseKcal）、金额>0。返回错误串=结构化失败 → 降级，**坏输出不落 ai_parses**。

`CaptureInputNormalizer`：normalize = 去首尾空白 + 连续空白折叠单空格；inputHash = sha256(规范化输入)。拍照通道被哈希的内容 = 压缩后图片字节（content_hash 一址两用）。

## 四、拍照通道值对象

```
CapturePhotoFile{bytes, mime, localPath?}        原图字节=raw_input（不落任何表）；localPath=即焚对象
  → CaptureCompressedImage{bytes, mime='image/jpeg', contentHash=sha256(bytes), sizeBytes}
  → CapturePendingPhoto{contentHash, mime, sizeBytes, localPath?}   在途态（确认前绝不焚）
  → CaptureAttachmentDraft{entryId, contentHash, kind='photo', mime, sizeBytes, localPath?}
      → core_db attachments 行（登记即 burned，blob_ref 恒 NULL，不入 sync_outbox）
```

## 五、落库映射（→ core_db）

| 写路径 | 表 | 行要点 |
|---|---|---|
| submitMoneyCapture | entries | kind=expense、source=manual、status=confirmed、ai_parse_id=null |
| | entry_lines | type=money、confidence=null（人工行无置信度）、currency：显式>账本>CNY |
| applyMoneyCorrection | entries | 仅主干变更时：status=edited、revision+1、created_at 保持 |
| | entry_lines | 旧行→superseded；新行 correction_of=旧行 id；currency 跟随账本不可变 |
| | corrections | 字段级审计（date/tz_offset_min/title/note line_id=NULL；amount/direction/category/ledger 携 lineId），source='user' |
| submitAiCapture | entries | kind 推导、source=text/chip/manual/photo、status=confirmed、ai_parse_id 溯源 |
| | entry_lines(calorie) | amount=kcal、direction=in、ledgerId=内置 kcal 账本、payload={items 摘要, portion_multiplier} |
| | entry_lines(money) | amount=分、direction=请求值、ledger 必填、confidence=AI 产出必填/人工 null |
| | food_items | 逐菜品一行（name/portion_g/kcal/营养/ref_source/confidence/user_adjusted=false） |
| | corrections | 差异审计（title/kcal/amount/category），source='ai_corrected' |
| ensureDefaultLedger / ensureKcalLedger | ledgers | money '默认账本'(CNY) / kcal '热量账本'(currency='kcal')；幂等 |
| saveAiParse | ai_parses | input_kind/input_hash/provider/model/raw_output/latency/cost/confidence/prompt_version；**本地件永不同步** |
| registerBurned | attachments | insert active（blob_ref 恒 NULL）→ markBurned 单向状态机；**不入 sync_outbox** |

**出网纪律**：entries / entry_lines / food_items / corrections / ledgers 是同步真值表——所有写入经 `SyncOutboxWriter.enqueueRow` 在**同一事务**内读回行快照入队 sync_outbox；同 (table,row) 未 ack 出网项折叠为一条（payload=终态）。ai_parses / settings / attachments 不入网。全表清单与同步协议见 [../core_db/README.md](../core_db/README.md) 与 [../feature_sync/README.md](../feature_sync/README.md)。

## 六、选项模型（只读装载）

- `CaptureLedgerOption{id, name, currency}`；`CaptureCategoryOption{id, name, icon, colorToken, isPreset}`——colorToken 是语义 token 名（如 'moneyOut'），渲染时映射 SlimcaTheme，未知 token 回退中性色。
- `CaptureRecentEntry{entryId, title, date, kind, kcal?, moneyMinor?, moneyDirection, categoryId?, ledgerId?, categoryName?}`——`summary` 生成「550 kcal · ¥18.50」chip 文案；复记生成新事件不复用旧行 id。
- `CaptureSeed{editEntryId?, initialDate?}`——控制器 family 参数，== 按字段值比较。
- `CaptureMoney`（abstract final class）：`toMinorUnits`（元文本→分，正则 `^\d{1,9}(\.\d{0,2})?$`，纯字符串运算）、`fromMinorUnits`（1850→"18.50"，断言非负）、`appendDigit`（前导 0 替换、小数 ≤2 位、整数 ≤9 位）、`appendDot`、`backspace`、`displayText`（空→"0.00"）。
