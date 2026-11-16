# Slimca 更新日志（MVP 期 W1→W9-10）

> 单仓分包 Flutter 应用：日期仪表盘 + AI 双解析记账（钱·热量双维）+ 离线优先同步。
> 设计依据：docs/design/产品设计文档.md（§11.1 里程碑路线图）。MVP 期 W1-W10
> 对应两个闸门：M1（12-27，功能项）与 M2（01-24，v1.0 公测就绪）。
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

## 测试基线（W9-10 收官时点）

flutter analyze 全仓 0 issues；flutter test 逐包全绿：
core_domain 31 / core_db 22 / core_ai 103 / ui_kit 58 / feature_capture 25 /
feature_dashboard 6 / feature_ledger 25 / feature_plan 14 / feature_sync 52 /
apps/mobile 65——合计 401 用例。
