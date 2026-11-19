# feature_capture 已知坑点

> 排查本模块 bug 前先过一遍；跨模块影响已标注。

## 1. capture_photo_test 已知 flaky（pump+runAsync 轮询桥）

- **根因**：testWidgets 的 FakeAsync zone 不投递真实文件 IO 事件——拍照链含 Fake 落盘/即焚删除（真实临时文件），必须用 `pump` + `tester.runAsync(Future.delayed)` **交替**桥接：runAsync 让真实事件循环推进一拍，pump 再推进其后的 fake-zone 微任务链（`_pumpUntilFound` 等三个轮询 helper，capture_photo_test.dart）。
- **症状**：热机（高负载）下偶发超帧预算，等待控件/落库行/即焚收口的 150~240 次轮询超限 `fail('等待控件超时…')`；单独重跑通常即绿。
- **护栏判据陷阱**：即焚收口判据同时要求 attachments burned 行数 **和** photo_confirm 终点漏斗事件——「状态已到、终点微任务未冲刷」的窗口期会假通过，改判据时两条件缺一不可。
- **修复方向**：改轮询上限/间隔时保持 pump 与 runAsync 交替结构；不要改成纯 `pumpAndSettle`（真实 IO 永远等不到）。

## 2. CaptureAiStage 枚举禁止加值（编译期跨模块破坏）

Dart 3 对枚举穷举 switch 是编译期硬约束——本包与宿主面板（语音通道等）多处穷举 switch 该枚举，**加值会让宿主编译失败**。拍照通道的先例：处理中复用 `parsing` + `CaptureFormState.photoProcessingLabel` 分段文案；通道语义用 `pendingSource` / `pendingPhoto` 承载，不靠阶段值区分。新增输入通道照此模式（见 [code-patterns.md](code-patterns.md)）。

## 3. Provider 装配纪律：必 override 与缺省兜底不可混淆

- 6 个**必 override**（gateway/parser/imageSource/compressor/photoParser/attachmentStore）读即抛 UnimplementedError——这是设计而非缺陷，装配遗漏必须开发期暴露；测试与壳缺一个都会立刻炸。
- 3 个**缺省兜底**（rawInput 开关恒 false、estimator 恒 NoOnDeviceEstimator、telemetry 恒 null）是**安全最严口径**：忘装配不会炸，但行为会静默变成「字节不出端 + 人工确认 + 无埋点」——排查「拍照永远转手填」「没有漏斗数据」时先查壳层装配。

## 4. 金额：整数分、纯字符串运算、永不原地改

- 浮点全程禁入（§5.1）：键盘输入是字符串步进，`toMinorUnits` 纯整数运算；`fromMinorUnits` 断言非负——负数语义由 `direction` 表达。
- **金额不可变**（§3.4）：确认落库/手动提交后金额行永不 UPDATE，修改一律走 `applyMoneyCorrection` 新增 correction 行 supersede 旧行。直接改行会绕过修正审计、破坏同步 LWW 语义。
- 编辑模式恒走 money 手动表单；只有 status=active 且未墓碑的 money 行可被修正，其余抛 StateError/ArgumentError 快速失败。

## 5. 状态快照过期：await 之后必须复读 state

控制器方法在多个 await 之间持有 `current` 快照；异步间隙 state 可能已被其他交互改写。既有范式：`submitPendingCapture` 即焚后以 `state.value` 最新值收尾（避免旧快照复活 pendingPhoto）；`startPhotoCapture` 取消分支也复读 latest。**新增异步路径时照此办理**，否则会出现「已删除的临时文件路径被再次删除/已清空的待焚原件复活」类幽灵 bug。

## 6. copyWith 哨兵语义（可空字段置 null 的正确姿势）

`CaptureFormState.copyWith` 对 11 个可空字段（categoryId/ledgerId/editTarget/errorText/parseResult/aiParseId/aiInitials/pendingPhoto/photoProcessingLabel/confirmKcal/portionBaseKcal/fallbackHint）用 `_unchanged` 哨兵：不传=保持，显式传 null=清空。传错的结果是「该清的没清」（如旧 pendingPhoto 残留导致降级提交也被即焚）或「该留的清了」。

## 7. 即焚时序与兜底（§3.7/§11.2）

- **确认落库成功之前绝不焚**：任何失败/取消路径（识别失败、用户取消、切 money 档之外的放弃）都必须保留待焚原件与临时文件；只有 `submitPendingCapture` 成功返回后才 `registerBurned` + 删文件。
- 删除文件是尽力而为（失败静默吞掉不重试）；**行状态是即焚真值**，壳层启动时临时目录清扫兜底。attachments 行登记失败不回滚已落库记录。
- attachments 不入 sync_outbox（14 张真值表之外）；blob_ref 恒 NULL=原图不落服务端。

## 8. 枚举口径：kind / 收入 / 餐食

entries.kind 枚举是 food/fitness/expense/mixed/note——**没有** 'meal' 和 'income'。餐食=food；收入=kind 恒 expense + 行级 direction=in。AI 路径 money 行方向恒 outcome；chip 复记继承原行方向。新代码若按「meal/income kind」理解设计文档会写错落库。

## 9. input_hash 缓存：UUIDv7 时间戳判时效、坏缓存视同未命中

ai_parses 无独立时间列——7 天时效由 id（UUIDv7）内嵌 48 位毫秒时间戳判定（非法形态返回 null 不判过期）；同 (input_hash, input_kind) 多行时按 id 字典序（=时间序）倒序取最新。raw_output 反序列化失败视同未命中重新解析。**跨模块注意**：改 CaptureParseResult 的 JSON 形态（字段名/类型）会让所有既有缓存变坏缓存（可接受，但要知道）。

## 10. 相机/存储权限归壳层，不在本模块建模

`CaptureImageSource` 抽象只约定「取消返回 null」；权限拒绝、系统相册 UI、image_picker 插件版本兼容全在壳层薄封装内处理。真机「拍照无反应/直接降级」类问题先查壳层实现与 Android/iOS 权限清单（CAMERA / READ_MEDIA_IMAGES 等），不要在本包找。

## 11. 超时与护栏三件套（别混用）

文本 5s（kCaptureParseTimeout）/ 照片 12s（kCapturePhotoParseTimeout）/ 拍照全程 15s 护栏（kPhotoPathGuardMs，open→confirm 含压缩与确认）。超时一律降级手填。调整护栏时注意 metric 复用 `capture_open_to_confirm_ms`、`tags.path='photo'` 区分路径。

## 12. loadRecentEntries 的查询形态与排除项

逐 entry 再查行与分类（N+1 形态，limit=5 可接受）；burn 行不入 chip；无 active calorie/money 行的事件跳过；装载失败由调用方兜底空列表（不阻塞抽屉）。复记生成**新事件**（不复用旧行 id），日期刷新到今天。

## 13. onSubmitted 是纯通知，抽屉关闭恒由页面自身负责

W7-8 修复过的坑：宿主回调 `onSubmitted`（漏斗终点）不能接管导航——原先「有回调则不 pop」导致 FAB 打开的抽屉提交后滞留。`_finishSubmit` 固定：先回调、再 `Navigator.pop`。宿主不要在回调里再 pop。
