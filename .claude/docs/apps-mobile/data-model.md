# apps-mobile 数据模型与配置键

> 壳层无独立真值表——21 张表的 schema 真值在 [core_db](../core_db/README.md)。
> 本文件只记录壳层自有面：视图模型、settings 本地键、dart-define 编译期键、
> 壳层约定的 JSON 形状。

## 1. settings 本地键（§5.6⑲；value 一律 JSON 文本，永不同步）

坏值口径：缺键/坏 JSON/未知枚举一律回落默认（本地件自愈）；隐私开关「坏值回落更严档」。

| 键 | 值形状 | 缺省 | 写入方 |
|----|--------|------|--------|
| `device_id` | JSON string（UUIDv7 前 12 位 hex） | 首启生成 | bootstrap `ensureDeviceId`；损坏重新生成（不影响 HLC 全序） |
| `first_open_day` | JSON string（yyyy-MM-dd） | 首启锚定 | bootstrap `ensureFirstOpenDay`（次日留存 D0 锚点；损坏重新锚定） |
| `raw_input_cloud_enabled` | JSON bool | `false`（关） | 设置页 Switch → `saveRawInputCloudEnabled` |
| `photo_burn_after_parse` | JSON bool | `true`（开=即焚） | 设置页 Switch → `savePhotoBurnAfterParse` |
| `current_theme_id` | JSON string（theme_profiles.id） | `preset-mo`（墨） | `ThemeSettingsController.selectPack` |
| `motion_level` | JSON string（off/reduced/full） | `full` | `setMotionLevel` / 编辑器动效段 |
| `theme_mode_override` | JSON string（system/light/dark） | `system` | `setThemeMode` |
| `dynamic_color_enabled` | JSON bool | `false` | `setDynamicColorEnabled` |
| `body_weight_kg` | JSON number（kg） | 无（缺省基线 60，仅估算输入不写库） | FitnessLogPage 保存随会话同事务落库 |
| （core_db）`kSettingDefaultLedgerId` | JSON string | — | `MultiLedgerService.switchDefaultLedger`（core_db LedgerDao 承担） |

## 2. dart-define 编译期键（`String.fromEnvironment`，运行期/测试不可改写）

**全部为可选；缺省静默回落离线桩/本地回环——不报错**。详见 [pitfalls.md](pitfalls.md)。

| 键 | 常量 | 缺省回落 | 消费方 |
|----|------|----------|--------|
| `SLIMCA_AI_BASE` | `kSlimcaAiBase` | `https://api.openai.com/v1` | capture_parser_factory（文本解析端点） |
| `SLIMCA_AI_KEY` | `kSlimcaAiKey` | 空→`HeuristicFakeLlmAdapter` | 同上（**有 key 才切真实 adapter**） |
| `SLIMCA_AI_MODEL` | `kSlimcaAiModel` | `gpt-4o-mini`（json_schema 档；自定义模型取 json_object 宽档） | 同上 |
| `SLIMCA_BAIDU_API_KEY` + `SLIMCA_BAIDU_SECRET_KEY` | `kSlimcaBaidu*` | 空→先行位恒结构化失败桩 | photo_parser_factory（百度菜品识别） |
| `SLIMCA_VISION_BASE_URL` | `kSlimcaVisionBaseUrl` | `https://api.openai.com/v1` | photo_parser_factory（Vision LLM 兜底位） |
| `SLIMCA_VISION_API_KEY` | `kSlimcaVisionApiKey` | 空→`OfflineStubVisionCapturePhotoParser` | 同上 |
| `SLIMCA_VISION_MODEL` | `kSlimcaVisionModel` | `qwen-vl-plus` | 同上 |
| `SLIMCA_SUPABASE_URL` + `SLIMCA_SUPABASE_ANON_KEY` | `kSlimcaSupabase*` | 空→`LocalLoopbackBackend` | sync_backend_factory（同步后端） |

## 3. 壳层视图模型（只读聚合，不落库）

| 模型 | 文件 | 说明 |
|------|------|------|
| `DashboardDay` / `DashboardEntryView` | dashboard_state | 当日聚合（kcalIn/kcalOut/spend/income + 事件视图）；`DashboardDay.zero()` 空态 |
| `LedgerBillQuery`（值相等 family 参数）/ `LedgerDayGroup` / `LedgerEntryView` | ledger_state | 账本作用域+分类筛选的流水分组（口径外行连事件都不入列） |
| `PlanSavingsGoalView` / `FitnessPlanScheduleView` | plan_state | 存钱进度视图 / 排期视图（宽容解析模板动作） |
| `WorkoutSessionState` | workout_session_controller | 进行中训练（restEndsAtMs 绝对时刻=锁屏可跑正确性来源） |
| `TodoReminder` / `WorkoutTimerNotice` | notifications/ | 提醒请求（值相等）/ 常驻通知请求 |
| `RetentionAnchor` | bootstrap | 留存锚点产出（firstOpenDay/isFirstOpen/dayOffset） |
| `Sku` / `BillingCatalog` / `PurchaseResult` | billing/ | SKU（价格一律分 priceMinor）/ 目录 / 购买终态 |
| `ThemeSettings` | theme/theme_settings | 主题偏好快照（packId/motionLevel/themeMode/dynamicColorEnabled） |

## 4. 壳层约定的 JSON 形状

- **存钱 rhythm**（§5.5⑪）：custom=`{"daily_amount_minor":n}`；daily365=`{"ladder":"day_n_yuan"}`；
  week52=`{"ladder":"week_n_yuan"}`。
- **fitness_plans.exercises 宽容解析**（workout_models `parsePlanExercises`）：基准=feature_plan
  编辑器顶层对象 `{"ver":1,"exercises":[{name,sets,target_reps,target_weight_kg_x10,rest_s}]}`，
  兼容顶层裸数组；动作行键名兼容 name/exercise_ref/ref/exercise/title/动作（大小写不敏感）、
  重量 kg 直填键与 ×10 定点键（定点命中且 >0 时覆盖）；非法项跳过、数值钳制、全空→空列表。
- **附件即焚状态机**（core_db attachments §5.6㉑）：登记即 burned、`blob_ref` 恒 NULL、
  不入 sync_outbox 出网集；content_hash 一址两用（attachments 去重键 + ai_parses input_hash 缓存键）。

## 5. 金额/热量/日期口径（全项目统一，壳层各服务共同遵守）

- 金额一律**分**（INTEGER），展示层换算集中在壳层 `lib/common/format.dart`
  （`yuanFromMinor`/`minorToYuanText`/`parseYuanToFen`——两位小数上限防浮点误差）与
  `calendarDayLabel`；
- 热量一律 INTEGER kcal（fitness MET 估算四舍五入）；
- 日期一律本地日历日 TEXT `yyyy-MM-dd`——字典序=时间序，BETWEEN 即闭区间；
  日偏移计算用 UTC 午末日差（免时区/夏令时漂移，bootstrap `_calendarDayOffset`）。
