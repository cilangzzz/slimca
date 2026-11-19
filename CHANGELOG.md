# Slimca 更新日志（MVP 期 W1→W16）

> 单仓分包 Flutter 应用：日期仪表盘 + AI 双解析记账（钱·热量双维）+ 离线优先同步。
> 设计依据：docs/design/产品设计文档.md（§11.1 里程碑路线图）。MVP 期 W1-W10
> 对应两个闸门：M1（12-27，功能项）与 M2（01-24，v1.0 公测就绪）；
> W11-16 对应 M3 闸门（V1 收官）。
> 每条里程碑对应一次 git 提交，提交内含当周验收与测试统计。

## 设计阶段（2026-11-16 定稿）

- 设计文档与市场调研定稿：产品设计文档（三案双透镜评审综合，v1.0 冻结）
  与市场调研与竞品分析；P0 红线清单 13 项在 W1 冻结（3683cc2）。
- 仓库协议：MIT LICENSE；.gitignore 环境变量保护（9d924f3）。

## W1 · 环境与地基（3b1f64c）

- 单仓分包落地：apps/mobile + 9 包（core_db / core_domain / core_ai / ui_kit /
  feature_dashboard / feature_capture / feature_ledger / feature_plan /
  feature_sync），Pub workspace 管理。
- Drift schema v1：21 表冻结（facet 拆行 + HLC 定宽列），迁移测试通过。
- HLC 混合逻辑时钟领域层（§6.3 定宽编码：字典序=全序、回拨不影响全序）。
- 主题动效 token v1 + MotionConfig（§8/§9）；App 壳（4 Tab + 中央「+」）。
- Supabase 初始迁移 0001_init.sql；CI 骨架（analyze + test）。

## W2 · 壳先行 + 手动记账全链路（1ee4ab4）

- day_summary 当日投影/仓储/seed；手动记账 CRUD 全链路（无 AI）。
- 仪表盘真页（日期大字 + 周历条 + 卡片墙，空态零值直出、无 spinner）。
- Riverpod 接线：appDatabase/hlcClock/仓库 providers；切日共享轴转场。

## W3-4 · AI 双解析闭环（文本路径）（5b456e3）

- core_ai 解析管线：受约束 JSON Schema 解析、input_hash 缓存、重试与失败
  分类、FakeParser（离线缺省，dart-define 切真实 adapter）。
- capture 确认卡（count-up 数字滚动 + 热量环 sweep + 置信度三档）与失败
  降级手填（AI 超时/失败原输入保留，输入页永不卡死，§7.4）。
- corrections 修正审计行落库；单边开关（仅记钱/仅记热量）与最近记录 chip。
- ui_kit 呼吸态等动效组件；壳装配 + E2E 验收用例。

## W5-6 · 记账完整化 + 语音 + 健身 + 同步引擎（3022e4d，M1 闸门）

- 分类体系（22 内置分类）、每日目标（热量 + 支出预算）、日简报。
- 语音通道 Fake 链路（端侧 ASR + 云兜底的接缝）；健身手动记录进仪表盘与
  净热量。
- HLC 时钟 + outbox + push/pull 同步引擎实现；冲突测试集四用例；
  LocalLoopbackBackend 缺省装配（§6.1 本地优先）。
- 计划 Tab 真页（待办/健身/存钱三卡）+ 健身手动记录子路由。
- **M1 闸门（12-27）**：文字路径 ≤8s（P50）口径内测数据就绪；核心六转场
  帧预算测试进 CI。

## W7-8 · 同步一期 + 内测起飞（d13c27d）

- Supabase 托管后端（feature_sync / server）：0002_sync_rpc.sql——RLS +
  SECURITY DEFINER RPC、幂等重放（幂等键=outbox.id）、服务端校验清单
  （schema_ver / hlc 严格单调 / baseRevision 乐观锁 / 墓碑拒绝复活）、
  pull 双轨资格与游标单调（§6.7 补投）；设备注册幂等（§5.6⑰）。
- 全写路径 outbox 补课：14 张真值表行快照同事务入队、入队去重收敛、
  TodoDao 四写路径与 seed 行同事务入队（§6.2 写路径纪律）。
- 遥测骨架（§3.9）：TelemetryService 抽象 + 隐私闸门（黑名单键剔除、仅
  标量 props、crash 只记类型）+ FileTelemetryService（本地 JSONL）+
  壳层接线（崩溃钩子/冷启动/解析漏斗/同步耗时）。
- raw_input 上云开关（§3.7 数据主权：默认关=即用即焚，settings 落库 +
  解析链闸门装饰）；IAP 骨架（BillingService + Fake 计费流 + 双轨 SKU 目录）。
- 飞行模式回归与双设备一致脚本全绿（100 entries + 100 entry_lines 双端
  逐行一致 100%）。
- 合规材料启动：软著申请材料清单、算法备案材料、内测发布 checklist
  （docs/ops；周期常达数月，按排期此时启动）。

## W9-10 · v1.0 公测就绪（本次，M2 闸门）

- 商店素材（docs/store/）：ASO 文案（双词「记账 热量」）、截图与动效演示
  视频脚本、隐私政策草稿、Google Play 数据安全表单草稿、上架 checklist
  （Google Play 封闭测试 / 华为 / 小米 / iOS TestFlight 走 Codemagic 云 Mac）。
- 北极星埋点覆盖核对与补齐（§11.1 W9-10「次日留存/录入漏斗/真机帧率」，
  §12 北极星口径）：
  - 次日留存：新增 `first_open`（D0 锚，首次启动日落 settings 本地件）与
    `app_open`（每次启动，props.day_offset 距 D0 偏移）漏斗事件——D1 存在
    app_open 即计入次日留存，本地 JSONL 周报可算；
  - 录入漏斗补齐「打开」起点：新增 `capture_open`（抽屉唤起即记），
    并在确认落库时记 `capture_open_to_confirm_ms` 护栏耗时指标
    （文字路径 ≤8s（P50）/ 拍照 ≤15s 的数据源）；
  - 真机帧率：新增 FrameTelemetry（引擎 FrameTiming 批次聚合 →
    `frame_raster_ms` / `frame_dropped` 指标，丢帧判定 totalSpan>1/60s，
    build ≤8ms / raster ≤16ms 超预算分行计数；main() 非 debug 装配）+
    dev benchmark 测试骨架（apps/mobile/test/benchmark/，锁冷启动直出 /
    抽屉 ≤280ms / 共享轴 ≤280ms 时长预算）；
  - 指标名收敛为 core_domain `TelemetryMetricName` 常量（sync_cycle_ms
    一并收敛）；配套测试：northstar_telemetry_test（留存锚点自愈、帧率
    聚合、事件名防回归）+ e2e 录入漏斗断言扩展。
  - **本机只能埋点：真机帧率/留存/漏斗的实测数字一律「待真机实测」**
    （真机 profile 模式采集，跑法见 benchmark 测试头注）。
- 版本：apps/mobile `version: 1.0.0+1`（公测基线）。
- CHANGELOG.md 建立（本文件）。
- **M2 闸门（01-24）口径：代码与素材就绪，v1.0 可公测；真实上架动作
  （TestFlight / Google Play / 华为 / 小米提审）待开发者账号；北极星数字
  （次日留存 / 录入漏斗 P50 / 真机帧率）待真机实测。**

## W11-12 · 拍照通道（19d439b）

- image_picker 双入口 + 端侧压缩（长边 1280 / JPEG q80）；附件解析后即焚
  （>7 天残留兜底清扫）。
- 双供应商识别管线：百度菜品识别 → Vision LLM fallback；确认卡复用。
- V1 留存钩子之一，photo_capture / photo_burn_setting 测试覆盖。

## W13 · 待办完整版 + 存钱目标（cc86213）

- 待办 RRULE 重复规则 + 提醒调度。
- 存钱目标：365 / 52 周 / 自定义 + 投币打卡，进度=贡献行求和，仪表盘进度卡。

## W14 · 健身计划（b367a6c）

- 模板排期（动作/组数/重量配比/休息秒 + 周排期掩码）、组间计时器（锁屏
  常亮 + 常驻倒计时通知）、组明细联动 burn 进净热量。
- 训练历史页（按日/按计划双维）；五类业务行同事务 outbox（无半程孤儿行）。

## W15 · 多账本 + 预算 + 统计报表（fd9d619）

- 多账本：建账本/重命名/归档软删，kcal 内置账本只读；账单流/分类汇总/
  报表序列 per-账本拆分自洽。
- 预算体系：每日总额 / 每日热量 / 分类每日 / 月度，周期与结转开关，
  budget_snapshot v2 双数组 + 单步结转；仪表盘支出卡余/超支状态色。
- 统计报表：周/月/年三档 + 支出构成堆叠条 + 热量趋势折线 + 钱-热量双轴
  联动选中，跨面板同步，「看当日」下钻回仪表盘。

## W16 · 主题编辑器 + 端侧小票 OCR（11b5ce2，M3 闸门：V1 收官）

- 主题系统：6 内置主题包（墨/纸/霓虹/奶油/森野/曜黑 AMOLED）+ WCAG AA
  护栏 + 主题编辑器（HCT 微调/色相锁定/AA 实时反馈/仪表盘微缩预览）+
  dynamic_color 平台取色 + 全屏 300ms morph。
- 端侧小票 OCR：ReceiptOcrAdapter 抽象 + 字段保守抽取（宁缺不错）+ 衔接
  既有文本解析管线（真实识别待真机验收）。
- M3 留存钩子全部上线（拍照/存钱/健身/主题）；修复 ReceiptDateTime 日偏移
  等集成问题；测试基线：10 包 715 例全绿，analyze 0 issue。

## 联调 · DeepSeek 通道（818e59f）

- DeepSeek 通道打通（deepseek-flash）+ 真实冒烟测试。

## V1 UX 插曲 · 大厂规范重设计（d6650f8 + 本批实现收口）

- 组件约束与动效体系化：新增间距尺度/触碰目标/状态层/展开收起曲线对 token
  （全部取 M3 官方刻度，不破坏既有 MotionConfig 与三层 token 架构）；
  spring_sheet 重写对齐规范；notch bar 壳层测试、cookie FAB 形状组件入库。
- 抽屉统一尺寸纪律：capture_sheet_uniform_size_test + plan_sheet_sizing——
  抽屉高度不随内容缩放、主 CTA 钉底、单一功能入口（§7 UI 口径）。
- 确认卡重构：capture_confirm_stage 阶段组件化 + capture_error_text；移除
  recent_chips（单一入口纪律）。
- AI 服务设置页：用户运行期自设凭据（settings 表本地件、永不同步、默认空=
  离线解析桩）；dart-define 降为首次开发联调回退。
- 首页日历去「固定七天」；菜单页重设计，「升级计划」整块移除 UI（IAP 代码
  保留不露出）。
- 架构收敛：plan_hub/fitness_workout_page/rest_timer/savings_service 等冗余
  层删除，训练流归一 workout_session_controller。
- 文档体系：CLAUDE.md + .claude/docs 11 模块技术文档（README/pitfalls/
  CHANGELOG）；设计侧《大厂设计规范》《UI-规范与重设计》定稿。

## 测试基线（W9-10 收官时点）

flutter analyze 全仓 0 issues；flutter test 逐包全绿：
core_domain 31 / core_db 22 / core_ai 103 / ui_kit 58 / feature_capture 25 /
feature_dashboard 6 / feature_ledger 25 / feature_plan 14 / feature_sync 52 /
apps/mobile 65——合计 401 用例。
