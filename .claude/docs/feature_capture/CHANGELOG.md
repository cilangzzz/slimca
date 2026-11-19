# Changelog - feature_capture

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。
> 类型口径：修复→fix、新增/支持→feat、优化→perf、调整→refactor。

---

## [2026-11-19] 移除「最近记录」chips（用户拍板：录入弹窗去最近记录）

**类型**: refactor（功能移除）
**提交**: 待提交（工作区）
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/widgets/capture_recent_chips.dart | 删除 | chip 横滑条组件整体移除 |
| lib/src/capture_page.dart | +3/-80? 见 numstat | AI 输入区不再渲染 chips；composer 结构保留（Expanded 有界中介注：Flexible 直接子级不得再套 ParentDataWidget） |
| lib/src/capture_controller.dart | -80 | recentEntries 装载、applyRecentChip 移除（source=chip 路径随功能移除） |
| lib/src/capture_models.dart | -57 | kRecentChipLimit/CaptureRecentEntry/recentEntries 字段与 copyWith 参数移除 |
| lib/src/capture_gateway.dart | -69 | loadRecentEntries 查询移除 |
| lib/feature_capture.dart | +2/-2 | barrel/库文档同步 |
| test/capture_flow_test.dart | +12/-99 | chip 复记用例移除；其余金额链路 enterText 口径保持 |

### 影响范围

- **行为**：录入抽屉 AI 输入区只保留 composer 输入面；「最近记录复记」入口不再存在（P7 极简美学——单一功能聚焦）。
- **API 破坏性**：CaptureRecentEntry/kRecentChipLimit/applyRecentChip/loadRecentEntries 公开移除（外部如有引用需随移）。
- **数据**：无表变更；复记历史行不受影响。

### 回滚指南（LOW）
- 回滚：revert 上表 7 文件（删除的 widget 文件恢复）。

---

## [2026-11-18] 仅记钱金额改滚动直输（移除钉底自绘键盘）+ 控制器键盘步进 API 移除

**类型**: refactor（用户拍板：自绘键盘吃满空间 → 改允许用户输入的滚动金额字段）
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/widgets/capture_amount_input.dart | 重写 | `CaptureAmountField`（TextField 直输）：numeric+decimal 键盘类型（§7.3）、两位小数 formatter、¥ 前缀 24pt 居中、tabular figures、方向语义色；原 `CaptureAmountDisplay`/`CaptureAmountKeypad` 合并移除（keypad 仅一处使用） |
| lib/src/capture_page.dart | 重构 | money 阶段回归整段滚动（无钉底键盘）；表单加「金额（元）」持久标签（P6/D7） |
| lib/src/capture_controller.dart | -32 | 移除 `inputDigit`/`inputDot`/`backspace`（自绘键盘步进 API，唯一调用方已移除；`setAmountText` 承接；CaptureMoney 纯函数保留） |

### 影响范围

- **行为**：仅记钱表单 = 方向 → 金额字段（系统数字键盘直输，两位小数 formatter 端拦截）→ 标题/分类/账本/日期/备注，全部滚动；提交页脚钉底不变。自绘键盘与系统键盘双输入面的资源争抢消除。
- **API**：`CaptureAmountField`（key `capture_amount_display` 保留在字段上，既有断言兼容）；controller 键盘步进三方法移除（破坏性——外部如有引用需改 `setAmountText`）。
- **测试**：capture_flow_test 键盘点按改 enterText。

### 回滚指南（MEDIUM）

- 回滚：revert 三文件。
- 回归：capture_flow / capture_money / e2e_record / widget_test / e2e_ledger（金额链路）。

---

## [2026-11-18] 大厂设计规范对齐：弹层 M3 容器/触控 48/字阶/tabular/错误双编码/按钮胶囊

**类型**: refactor（依据 docs/design/大厂设计规范.md 执行口径）
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件（git diff --numstat 口径，含三轮累计）

| 文件 | 变更 | 说明 |
|------|------|------|
| packages/ui_kit spring_sheet.dart / count_up.dart | +72/-12 | **见 ui_kit CHANGELOG 本日条目**（弹层路由 M3 化 + tabular，capture 面板自动受益） |
| lib/src/capture_page.dart | +253/-91 | _FieldLabel→Label Large 14/20/500（§5/UI-规范 §4.2）；money/降级错误行→`CaptureErrorText`（D8 颜色+图标双编码）；提交钮胶囊 + 行高 56（§7.1/§12.2） |
| lib/src/widgets/capture_error_text.dart | 新增 | 错误文案行共享组件：error 图标 + 12sp danger 文本（§10.1 P8/D8），capture 域错误行统一出口 |
| lib/src/widgets/capture_text_field.dart | +19/-7 | input 16pt（§7.3 M3 文本框字号）、contentPadding 16→容器 56dp、圆角 radiusGroupCard 12 |
| lib/src/widgets/capture_side_toggle.dart | +6/-5 | 分段触控 40→48（§6.3 minTouchTarget）、圆角 12、选中字重 w500（Label Large 口径） |
| lib/src/widgets/capture_photo_entry.dart | +59/-47 | 按钮 44→48 + 胶囊（§7.1）、图标 24（iconVisual）、间距/字号 token 化、提示 11→12sp（§5 决策 3） |
| lib/src/widgets/capture_amount_input.dart | +17/-20 | 金额大字 tabular figures（§5.4） |
| lib/src/widgets/capture_ai_input.dart | +20/-18 | 解析钮胶囊 + 48、错误行 CaptureErrorText、间距 token |
| lib/src/widgets/capture_confirm_card.dart | +40/-12 | 确认钮胶囊 + 48、错误行 CaptureErrorText |
| lib/src/widgets/capture_confirm_stage.dart | 新增（+80） | 确认阶段区（卡面滚动+动作钉底）+ 阶段级 errorText 插槽（CaptureErrorText） |
| lib/feature_capture.dart | +2/-0 | barrel 导出 capture_error_text/capture_confirm_stage |
| apps/mobile capture_channels_sheet.dart | +80/-45 | 通道条贴底三等宽（第二轮）+ 分段 48/圆角 12/图标 24 token 化 |
| apps/mobile photo/voice_capture_panel.dart | +164/-73 | 取景卡/转写卡扩展吃满 + 主操作贴底 + 胶囊按钮 + 错误 CaptureErrorText + token 化 |
| apps/mobile test（2 文件） | +14/-9 | e2e 拍照路径改道 + 单一入口断言 |

### 影响范围

- **规范映射**：§8.1 弹层容器（把手/圆角 28/限宽 640，经 ui_kit 路由全局生效）、§6.3+§13.2 触控 ≥48、§5.1 字阶（Label Large/Body Small）、§5.4 tabular figures、§7.1 按钮胶囊、§7.3 文本框 56/16pt、§10.1+D8 错误双编码、D1 新改区域 token 化（SlimcaSpacing/SlimcaSizes）。
- **存量债务注记**：capture 域未触及区域（capture_category_picker/ledger_picker/date_row/recent_chips、仪表盘等）仍为既有裸值——D1 全量 token 化属独立清欠任务，不在本轮。
- **无动效路径变更**；ui_kit 变更见其 CHANGELOG（弹层路由全局对齐）。

### 回滚指南（MEDIUM）

- 回滚：revert 本工作区 capture 相关 12 文件 + ui_kit 2 文件（新组件文件一并删除）。
- 重点回归：capture_flow/capture_photo（包）、widget_test/e2e 系列、ui_kit transitions_smoke、feature_plan 编辑器弹层（39 例已绿）。

---

## [2026-11-18] 录入抽屉统一高度 + 拍照单一入口 + 确认卡 CTA 钉底（稳定输入面）

**类型**: refactor（UX 修复）
**提交**: 待提交（工作区）
**风险**: MEDIUM

### 变更文件（git diff --numstat 口径）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_page.dart | +238/-72 | 新增 `captureSheetHeight`（视口 62%、带限 480–640，大厂输入面板口径）+ `captureSheetSizeKey`；showCaptureSheet 包统一高度 SizedBox + viewInsets 键盘避让；CapturePage 增 `showPhotoEntry` 开关 + 加载帧填充式居中；阶段编排重构 `_stageArea`——money=字段滚动 + **数字键盘钉底**（系统键盘弹出时自绘键盘收起），AI 输入=composer（chips 顶置、字段扩展吃满、解析钮贴底），解析呼吸态居中，确认卡与降级表单「字段滚动 + 动作页脚钉底」 |
| lib/src/widgets/capture_amount_input.dart | +14/-18 | 拆分为 `CaptureAmountDisplay`（大字金额+原金额对照，滚动区）与 `CaptureAmountKeypad`（4×3 键盘，钉底恒全可见）——原合并组件仅一处使用即移除 |
| lib/src/widgets/capture_ai_input.dart | +14/-7 | `expanded` composer 模式（字段 `expands` 吃满剩余空间、按钮贴底；缺省 false 紧凑三行不变） |
| lib/src/widgets/capture_text_field.dart | +9/-1 | `expands` 透传（TextField expands 契约：lines 置 null、顶端对齐） |
| lib/src/widgets/capture_confirm_stage.dart | 新增 80 行 | 共享确认阶段区：卡面滚动 + `CaptureConfirmActions` 钉底 + 阶段级 `errorText` 插槽（写/说/拍三面板共用，§10.4） |
| lib/src/widgets/capture_confirm_card.dart | +34/-3 | 动作区抽出为公开 `CaptureConfirmActions`；`showActions` 开关（缺省 true，包内直嵌用法不变） |
| lib/src/widgets/capture_photo_entry.dart | +59/-45 | `showGalleryEntry` 开关（缺省 true=双入口，CapturePage 独立抽屉与包测试口径不变）；单入口态=全宽「拍照识别」主按钮；按钮构造抽出复用 |
| lib/feature_capture.dart | +1/-0 | barrel 导出 capture_confirm_stage.dart |
| apps/mobile/lib/features/capture/capture_channels_sheet.dart | +74/-40 | 通道抽屉包统一高度 SizedBox + viewInsets 键盘避让；**通道切换条挪到抽屉底部 + 三段 Expanded 等宽**（此前仅「拍」被拉伸致大小不一）；写通道传 showPhotoEntry=false（拍照入口收敛到「拍」通道） |
| apps/mobile/lib/features/capture/photo_capture_panel.dart | +83/-16 | 确认卡阶段改经 CaptureConfirmStage；**取景引导卡扩展吃满（整卡可点）+ 主操作贴底**；拍通道单一入口（showGalleryEntry=false）；降级簇贴底 |
| apps/mobile/lib/features/capture/voice_capture_panel.dart | +68/-33 | 确认卡阶段改经 CaptureConfirmStage；**转写卡常驻扩展吃满（空态占位文案）+ 麦克风簇贴底**（source=voice 提交口不变）；确认阶段传面板 `errorText`（语音提交失败就地提示，不再静默）；降级簇贴底 |
| apps/mobile/test/capture_sheet_uniform_size_test.dart | 新增 211 行 | 守护测试：独立/通道抽屉装载帧、档位切换、写↔说↔拍切换全程同高；键盘弹出外框恒定 + 钉底 CTA 让出键盘；拍照入口唯「拍」通道单一按钮 |
| apps/mobile/test/e2e_photo_capture_test.dart、test/widget_test.dart | +14/-9 | 相册 e2e 改拍照路径（漏斗 from_camera=true 口径）；拍通道断言无相册按钮（单一入口） |

### 影响范围

- **行为（三轮定稿）**：抽屉高度与内容状态解耦（中低高度 480–640 带，money 键盘一屏可见）；各状态内容**填充**统一高度框——写=composer 扩展输入面、说=转写卡扩展（空态占位）、拍=取景引导卡扩展（整卡可点）、解析呼吸态居中、长内容滚动 + CTA 钉底，无空白死角；通道切换条贴底三等宽。键盘避让按 viewInsets.bottom 收缩内容区（Android 15+ edge-to-edge 口径）。
- **⚠ Flutter 布局坑（本次踩中）**：Column 对非 flex 子项下发**无界高度**（flex.dart `_constraintsForNonFlexChild` 不传高度）——含 `Expanded` 的组件（CaptureAiInput composer）必须包 `Expanded` 成为 flex 子项，否则 Infinity 布局崩溃；LayoutBuilder/滚动包裹会掩盖该问题（前两轮填充式居中借此通过）。
- **单一入口（两轮收紧）**：写通道 AI 输入区不再内嵌拍照入口；「拍」通道内只剩取景卡+全宽「拍照识别」单按钮，相册选择不再并列露出（相册路径语义保留在控制器与包测试）。
- **API**：`CapturePage.showPhotoEntry`（缺省 true）+ 顶层 `captureSheetHeight` / `captureSheetSizeKey` + 新组件 `CaptureConfirmStage`（含 `errorText` 插槽）/ `CaptureConfirmActions` + `CaptureAiInput.expanded` / `CaptureTextField.expands` / `CapturePhotoEntry.showGalleryEntry`。
- **无动效路径变更**：纯布局约束（无新动画，MotionLevel=off 纪律不受影响）；ui_kit 未动。
- **注意**：统一抽屉高度为本次用户新增口径，不对应 docs/design §9.3 既有条目（§9.3 为转场清单，§9.3#3 弹簧 bottomSheet 是其延伸约束）。

### 回滚指南（MEDIUM）

- 回滚：revert 本工作区 8 处源文件改动（新测试/新组件文件一并删除）。
- 检查文件：上表全部；重点回归 capture_flow_test / capture_photo_test / e2e_ai_confirm / e2e_voice / e2e_photo（确认卡与降级链路）。

---

## [2026-11-17] W11-12 拍照通道：双供应商识别管线+端侧压缩+即焚+确认卡复用（V1 留存钩子）

**类型**: feat
**提交**: 19d439b
**风险**: HIGH

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_controller.dart | +391/-7 | startPhotoCapture 主流程（取图→压缩→上云闸门分流→确认→即焚）、_enterPhotoFallback、_deleteTempFile、_photoFunnel/_photoMetric/_photoConfirmTelemetry、setSide 切钱档弃置原件 |
| test/capture_photo_test.dart | +830/-0 | 拍照通道 6 例（主链路/缓存/上云关/端侧无法估计/失败降级/相册）；pump+runAsync 交替轮询桥 |
| lib/src/capture_photo_models.dart | +142/-0 | CapturePhotoFile/CompressedImage/PendingPhoto/AttachmentDraft 值对象；content_hash=sha256(压缩字节) 一址两用 |
| lib/src/capture_photo_fakes.dart | +184/-0 | FakeImageSource（可落真实临时文件）/FakeImageCompressor/FakeCapturePhotoParser/FakeCaptureOnDeviceEstimator/FakeCaptureAttachmentStore |
| lib/src/capture_attachment_store.dart | +76/-0 | CaptureAttachmentStore 窄接口（registerBurned 登记即焚）+ DbCaptureAttachmentStore 桥接 core_db AttachmentsDao |
| lib/src/capture_photo_estimator.dart | +65/-0 | CaptureOnDeviceEstimator 抽象 + NoOnDeviceEstimator 缺省最严兜底 + captureRawInputCloudEnabledProvider（默认关） |
| lib/src/widgets/capture_photo_entry.dart | +109/-0 | 拍照/相册双按钮 + 随上云开关切换的隐私提示行 |
| lib/src/capture_photo_parser.dart | +77/-0 | CapturePhotoParser 抽象 + CapturePhotoParserFallback 组合子（百度先行→Vision 兜底）+ 12s 超时常量 |
| lib/feature_capture.dart | +48/-0 | 库文档重写（拍照通道数据流/DI 契约）+ 新文件导出 |
| lib/src/capture_photo_compressor.dart | +42/-0 | 压缩接缝（长边 1280/JPEG q80 常量）；真实实现由壳注入 |
| lib/src/capture_photo_source.dart | +37/-0 | CaptureImageSource 抽象（拍照/相册；取消返回 null） |
| lib/src/capture_photo_telemetry.dart | +48/-0 | CapturePhotoFunnel 三事件常量 + kPhotoPathGuardMs=15s + photoPathWithinGuard + 遥测注入点 |
| lib/src/widgets/capture_confirm_card.dart | +10/-2 | 来源徽标区分拍照识别/端侧粗估（aiParseId 有无） |
| lib/src/capture_models.dart | +40/-4 | pendingPhoto/photoProcessingLabel/pendingSource 状态字段与哨兵 copyWith 扩展 |
| lib/src/capture_page.dart | +17/-4 | input 阶段挂载 CapturePhotoEntry；_aiFlowBody 拍照分段文案 |
| lib/src/capture_parser.dart | +4/-0 | CaptureInputNormalizer.kindPhoto 常量 |

### 影响范围

- **API**：新增 6 个 Provider（imageSource/compressor/photoParser/attachmentStore/rawInput 开关/telemetry，其中 4 个必 override）+ `startPhotoCapture`/`registerBurned`；漏斗事件 photo_capture_open/photo_parse_result/photo_confirm。
- **跨模块**：同提交改 core_db（AttachmentsDao 即焚状态机 + attachments 表补 status/burned_at 两列，schemaVersion 保持 1、beforeOpen 幂等回填）、core_ai（百度/Vision 适配器与 dart-define 工厂 SLIMCA_BAIDU_*/SLIMCA_AI_*，缺省 Fake）、apps/mobile（权限清单 CAMERA/READ_MEDIA_IMAGES 等 + iOS 用途描述 + image_picker 接入）。
- **数据模型**：attachments 表加列（见 core_db CHANGELOG）；ai_parses 复用为 photo 缓存（input_kind='photo'）。
- **配置**：真实供应商凭据未提供——dart-define 注入，缺省 Fake（待凭据联调）。

### 回滚指南（HIGH）

- 回滚：`git revert 19d439b`
- 检查文件：上表 16 个文件 + core_db 的 attachments 迁移/beforeOpen 回填 + 壳层权限清单与解析器工厂接线
- 副作用：core_db attachments 表加列在本提交内完成，revert 后 beforeOpen 回填代码一并消失（已建库无碍）；壳层设置页「即焚」设置项与拍段面板将引用失效，需同 revert；aars：core_ai 拍照管线 revert 后 capturePhotoParserProvider 无实现可注入。

---

## [2026-11-16] W7-8 同步一期：全写路径 outbox 补课 + 提交收尾语义修复

**类型**: feat（含 fix）
**提交**: d13c27d
**风险**: HIGH

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_gateway.dart | +78/-63 | 全部写路径改经 core_db SyncOutboxWriter：food_items 逐行、corrections 审计行、修正链全写入集（主干 edited/旧行 superseded/新修正行）、kcal/默认账本懒建——同事务读回终态快照入队；无真实变更零入队 |
| test/capture_outbox_test.dart | +600/-0 | 新增 7 例：双行/food_items+审计/修正链（标题+金额）/仅金额 confirmed→edited 联动/无变更零写/坏 oldLineId 快速失败/kcal 账本懒建，全部断言「出网行 ⇔ 落库行」回放一致 |
| lib/src/capture_page.dart | +6/-2 | _finishSubmit 语义修复：onSubmitted 是宿主纯通知，抽屉关闭恒由页面自身 pop（修复提交后抽屉滞留、确认卡 pumpAndSettle 超时） |

### 影响范围

- **API**：CaptureGateway 全部写方法行为变更——返回值不变，但每次真实写入同事务产出 sync_outbox 行（此前只落业务行不出网）；`asEntryRepository` getter 语义不变。
- **跨模块**：同提交新增 core_db SyncOutboxWriter（入队去重/读回不到行即整体回滚）、server/supabase 0002_sync_rpc.sql（RLS+RPC 幂等）、feature_sync 引擎、core_domain TelemetryService、apps/mobile raw_input 开关接线（RawInputGateCaptureParser 装饰）。
- **数据模型**：无表结构变更；sync_outbox 行为语义强化（同 (table,row) 折叠到终态）。
- **配置**：无。

### 回滚指南（HIGH）

- 回滚：`git revert d13c27d`
- 检查文件：capture_gateway.dart、capture_page.dart + core_db SyncOutboxWriter 及其测试 + feature_sync 引擎（依赖本提交的入队契约）
- 副作用：revert 后采集路径回到「只落业务行不出网」，同步链路将丢 entries/entry_lines/food_items/corrections 出网项——双端同步功能实质失效；capture_outbox_test 同步消失（无回归网）。

---

## [2026-11-16] W5-6 采集路径 outbox 缺口补课（fix）

**类型**: fix
**提交**: 3022e4d
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_gateway.dart | +57/-1 | submitMoneyCapture / submitAiCapture 的 entries+entry_lines 行快照同事务入队 sync_outbox（§6.2 写路径纪律）——修复「采集路径只落业务行不出网、语音 e2e outbox=0」 |

### 影响范围

- **API**：方法签名不变；写路径行为补齐（每次落库同步产出出网项）。
- **跨模块**：同提交新增 feature_sync 包（LocalSyncEngine/InMemorySyncBackend）、修复 core_db DriftEntryLineRepository.upsert 投影联动误传 date、core_ai/壳层语音 Fake 链路、feature_ledger/feature_plan 多项。
- **数据模型**：无表变更。
- **配置**：无。

---

## [2026-11-16] W3-4 AI 双解析闭环（文本路径）：确认卡+降级+input_hash 缓存

**类型**: feat
**提交**: 5b456e3
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_gateway.dart | +409/-7 | submitAiCapture 同事务落库（entries+calorie/money 行+food_items+corrections 差异审计 source='ai_corrected'）、saveAiParse/findCachedParse（UUIDv7 内嵌时间戳 7 天时效、坏缓存视同未命中）、matchCategoryByHint、ensureKcalLedger、loadRecentEntries |
| lib/src/capture_models.dart | +352/-12 | CaptureSide/CaptureAiStage 状态机、CaptureFormState（哨兵 copyWith）、CaptureAiSubmitRequest/CaptureAiInitials/CaptureConfirmedItem/CaptureRecentEntry 等载荷模型 |
| lib/src/capture_controller.dart | +390/-12 | AI 流编排：startParse（缓存→解析 5s 超时→校验→留痕→确认）、_enterConfirm（AI 初值预填）、applyRecentChip、setPortionMultiplier、backToInput、_enterManualFallback、submitPendingCapture |
| lib/src/capture_page.dart | +234/-201 | 重构为按 side/aiStage 分流：AI 输入区/呼吸态/确认卡/降级手填表单；_SpringSubmitButton 提取 |
| lib/src/capture_parser.dart | +316/-0 | CaptureParser 接口 + 注入点、CaptureParseResult/Line/Item（JSON 口径=缓存格式）、checkUsable 校验器、CaptureStructuredFailure/CaptureFailureCode、CaptureInputNormalizer、kCaptureParseTimeout=5s/kMaxParseKcal=5000 |
| lib/src/widgets/capture_confirm_card.dart | +402/-0 | 确认卡：AI 初值预填 + SlimcaCountUp/热量环 sweep + SlimcaConfidenceDot 三档 + 低置信度高亮 + 份量滑杆联动 |
| test/capture_flow_test.dart | +522/-36 | AI 流 widget 测试（缓存命中/降级/单边过滤/复记/滑杆） |
| lib/src/widgets/capture_recent_chips.dart | +118/-0 | 最近 chips 横滑（kRecentChipLimit=5，复记日期刷新今天） |
| lib/src/widgets/capture_text_field.dart | +86/-0 | 公用语义文本输入（initial 外部变化才回写，防光标跳动） |
| lib/src/widgets/capture_ai_input.dart | +87/-0 | 文本输入区 + 解析按钮 + 单边提示 |
| lib/src/widgets/capture_parsing_state.dart | +72/-0 | 解析中呼吸态（ui_kit SlimcaBreath 组装） |
| lib/src/widgets/capture_date_row.dart | +71/-0 | 归属日选择行（可回记） |
| lib/src/widgets/capture_side_toggle.dart | +19/-10 | 单边开关改三段 pill（钱+热量/仅记钱/仅记热量） |
| lib/feature_capture.dart | +27/-6 | 库文档重写 + 新导出 |
| pubspec.yaml | +7/-2 | 依赖补 crypto（input_hash sha256） |

### 影响范围

- **API**：新增 captureParserProvider（必 override）、CaptureGateway 6 个公开方法、CaptureController 10 个公开方法、CaptureConfirmCard 等 6 个 widget。
- **跨模块**：同提交新增 core_ai 包（LlmAiParser 管线/缓存/FakeParser）、ui_kit SlimcaBreath/SlimcaConfirmCard/SlimcaMoneyCountUp/SlimcaCalorieRing sweep、apps/mobile dart-define 装配工厂（SLIMCA_AI_BASE/KEY/MODEL）与 e2e_ai_confirm_test。
- **数据模型**：ai_parses 表开始承载留痕与缓存（raw_output=CaptureParseResult JSON）；corrections 开始承载 source='ai_corrected' 差异审计。
- **配置**：core_ai 侧 LLM 凭据走 dart-define，缺省 FakeParser。

---

## [2026-11-16] W2 主线：手动记账 CRUD 全链路（模块首次真实现）

**类型**: feat
**提交**: 1ee4ab4
**风险**: HIGH

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/capture_gateway.dart | +446/-0 | CaptureGateway 创建：createCaptureGateway 装配入口 + submitMoneyCapture（entries+entry_lines 同事务，HlcClock 签发）+ applyMoneyCorrection（supersede 修正链 + corrections 审计 source='user'）+ 选项装载（账本/分类/编辑回填/默认账本懒建） |
| lib/src/capture_page.dart | +513/-0 | CapturePage 手动录入抽屉（W2 money 表单）+ showCaptureSheet + 提交编排 |
| lib/src/capture_controller.dart | +251/-0 | captureControllerProvider（AsyncNotifier.family.autoDispose）+ 键盘/字段方法 + submit（失败写 errorText 不抛） |
| lib/src/capture_models.dart | +258/-0 | CaptureSeed/CaptureEditTarget/CaptureCorrectionRequest/CaptureLedgerOption/CaptureCategoryOption + 初版 CaptureFormState |
| test/capture_flow_test.dart | +367/-0 | 手动表单 widget 测试（键盘步进/方向分类联动/提交落库） |
| lib/src/capture_money.dart | +67/-0 | 元文本↔分互转（纯字符串运算）+ 键盘步进规则（≤9 位整数/≤2 位小数/前导 0 替换） |
| lib/src/widgets/capture_amount_input.dart | +160/-0 | 大字金额 + 自绘 4×3 数字键盘 |
| lib/src/widgets/capture_category_picker.dart | +141/-0 | 分类 chip 组（colorToken→语义色映射，未知 token 回退中性色） |
| lib/src/widgets/capture_direction_toggle.dart | +80/-0 | 支出/收入双 pill（moneyOut/moneyIn 语义色） |
| lib/src/widgets/capture_ledger_picker.dart | +76/-0 | 账本 chip 组 |
| lib/src/widgets/capture_side_toggle.dart | +79/-0 | 单边开关（初版二段） |
| test/capture_money_test.dart | +101/-0 | CaptureMoney 单测 3 组 |
| lib/feature_capture.dart | +30/-5 | 库文档（W2 主线口径）+ 导出 |
| pubspec.yaml | +16/-36 | workspace resolution 重写：core_domain/core_db/core_ai/ui_kit path 依赖 + drift/crypto |
| test/feature_capture_test.dart | +0/-12 | 移除 W1 占位测试 |

### 影响范围

- **API**：本模块 API 表面的起点——1 个 Provider + 2 个网关写方法 + 10 个控制器方法 + 5 个 widget + showCaptureSheet。
- **跨模块**：同提交在 core_db 新增 EntryRepository/EntryLineRepository Drift 实现（软删墓碑/money 不可变守卫/supersede 事务）、day_summary 投影 v1、空库 seed；feature_dashboard 仪表盘真页；apps/mobile Riverpod 装配与 E2E（e2e_record_to_dashboard_test）。
- **数据模型**：依赖 core_db 21 表 schema v1（本提交前后由 W1 建立）；本包首次写 entries/entry_lines/corrections/ledgers。
- **配置**：pub workspace 分包依赖定型。

### 回滚指南（HIGH）

- 回滚：`git revert 1ee4ab4`
- 检查文件：上表 15 个文件 + core_db 仓库/投影/seed + feature_dashboard 真页 + apps/mobile 装配（同提交强耦合，需按依赖反向处理）
- 副作用：本模块回到 W1 占位骨架；壳「+」按钮与仪表盘「今日记录」失去写路径；day_summary 投影失去主要写入方。

---

## [2026-11-16] W1 环境与地基：包骨架（占位）

**类型**: feat
**提交**: 3b1f64c
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +55/-0 | workspace resolution 包声明 + 依赖占位 |
| README.md | +39/-0 | pub 模板 README（TODO 占位） |
| .gitignore | +31/-0 | Flutter/Dart 标准忽略 |
| .metadata | +10/-0 | Flutter 工程元数据 |
| CHANGELOG.md | +3/-0 | 0.0.1 占位 |
| analysis_options.yaml | +4/-0 | lints 引入 |
| lib/feature_capture.dart | +5/-0 | 空库导出 |
| test/feature_capture_test.dart | +12/-0 | 占位测试 |
| LICENSE | +1/-0 | 许可证 |

### 影响范围

- **API**：无（占位骨架）。
- **跨模块**：同提交建立 pub workspace 十包结构、core_db Drift schema v1（21 表）、core_domain HLC、ui_kit token、apps/mobile 壳、CI 与 Supabase 0001 迁移。
- **数据模型/配置**：无独立影响。
