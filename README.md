# Slimca

**记一件事，钱和卡路里一起入账。**

Slimca 是一款本地优先的个人生活记录 App：一次输入同时产出热量与金额（AI 双解析 + 修正闭环），一切记录围绕「日期仪表盘」组织——今天的钱、热量、运动、待办、计划进度一屏汇总。技术栈：Flutter 3.32 + Dart 3.8 + Riverpod 3 + go_router + Drift + 托管 Supabase（outbox+HLC 同步）。

## 目录结构（单仓分包，§10.4）

```
f:/projects/slimca
├─ apps/mobile/                 # 壳+路由+DI（ProviderScope + MaterialApp.router）
├─ packages/core_db/            # Drift schema+DAO+day_summary 投影
├─ packages/core_domain/        # 实体+仓库接口+HLC+SyncEngine 抽象
├─ packages/core_ai/            # LLM adapter+JSON Schema+校准联查
├─ packages/ui_kit/             # 语义 token+组件+MotionConfig+转场库
├─ packages/feature_dashboard/  # 日期仪表盘
├─ packages/feature_capture/    # 录入+AI 确认卡
├─ packages/feature_ledger/     # 记账+统计
├─ packages/feature_plan/       # 待办/健身/存钱
├─ packages/feature_sync/       # 同步引擎实现
├─ server/supabase/             # 迁移 SQL+RPC+RLS（后续创建）
└─ docs/design/                 # 设计文档
```

仓库采用 pub workspace：根 `pubspec.yaml` 声明 workspace，各包 `resolution: workspace`，依赖统一解析。

## 常用命令

```bash
# 依赖解析（workspace 根执行一次即可）
flutter pub get

# 静态检查（全部包）
flutter analyze

# 单元/组件测试
flutter test

# 运行 App（Android 优先，§1.3）
cd apps/mobile && flutter run
```

注意：Android 构建链依赖 Temurin JDK 17（W1 环境第 0 项，§10.3）；golden 快照回归仅在 Linux CI 基线生成，规避 Windows 字体渲染差异（§8.3/§9.6）。

## 文档

- [产品设计文档](docs/design/产品设计文档.md) — 定稿设计（12 章）：P0/P1/P2 功能清单、21 表数据模型（facet 拆行）、outbox+HLC 同步设计、AI 解析管线、主题与动效系统、W1-W24 里程碑
- [市场调研与竞品分析](docs/design/市场调研与竞品分析.md) — 2026-11 五路并行网调：竞品地图、市场空白、差异化主张
- [文档索引](docs/design/README.md) — 已定决策与待拍板项一览

里程碑：M1 2026-12-27（文字路径 ≤8s、核心六转场帧预算达标）/ M2 2027-01-24（v1.0 公测）/ M3 2027-03-07（留存钩子上线，§11）。
