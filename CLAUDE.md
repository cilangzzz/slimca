# Slimca

## 概述

统一日期仪表盘 + AI 解析一件事同时产出「热量与花费」双账 + 分开记账/统计 + 健身 + 待办/健身计划/存钱目标 + 跨设备同步 + 主题自定义的 Flutter App，Android 先行（个人项目，GitHub: cilangzzz/slimca）。V1 已收官（W1-W16），V2 期（W17-W24）未启动。

## 构建

- Flutter 3.32+ / Dart 3.8+，pub workspace（根 pubspec.yaml 聚合 10 包，无 melos）
- 静态检查：仓库根 `flutter analyze`（基线 0 issue）；测试：**逐包**执行 `flutter test`（根目录跑 `flutter test` 只报 "Test directory 'test' not found"，10 包约 784 例全绿；capture_photo_test 为已知 flaky，见坑点 13）
- 出包必须在 `apps/mobile` 目录执行 `flutter build apk`（根目录不产 APK）
- Android 构建链已配腾讯 Gradle 镜像 + 阿里云 Maven 镜像（apps/mobile/android）

## 测试环境

- 缺省离线可跑：同步走 LocalLoopback 内存后端，AI 走 fake/降级路径
- AI 文本凭据运行期由用户在设置页「AI 服务」自设（settings 表本地件、永不同步；默认空=离线解析桩）；`SLIMCA_AI_*` dart-define 仅在用户从未保存过配置时作为开发联调回退
- 真实联调凭据全走 `--dart-define`（禁止入仓库）：
  - 同步：`SLIMCA_SUPABASE_URL` / `SLIMCA_SUPABASE_ANON_KEY`
  - AI 文本：`SLIMCA_AI_BASE` / `SLIMCA_AI_KEY` / `SLIMCA_AI_MODEL`（OpenAI 兼容；已联调 DeepSeek，通道 id=deepseek-flash）
  - 视觉：`SLIMCA_VISION_BASE_URL` / `SLIMCA_VISION_API_KEY` / `SLIMCA_VISION_MODEL`
  - 百度 OCR：`SLIMCA_BAIDU_API_KEY` / `SLIMCA_BAIDU_SECRET_KEY`

## 项目结构

```
apps/mobile          组装壳：路由/DI/通知/计费/主题/语音/telemetry/workout 粘合（Android 产物）
packages/
  core_domain        纯 Dart 模型与值对象（最底层，零依赖）
  core_db            Drift 端侧数据库（21 表 facet 拆行 + 13 DAO + outbox 写入）
  core_ai            AI 解析引擎（LLM adapter/双解析/小票 OCR/缓存/降级）
  ui_kit             设计系统（tokens/components/transitions/动效帧预算）
  feature_sync       自研同步引擎（outbox+HLC+Supabase RPC transport）
  feature_dashboard  日期仪表盘
  feature_ledger     记账与统计
  feature_plan       待办/健身计划/存钱目标
  feature_capture    拍照→AI 解析→双账录入（V1 核心动线）
server/supabase      云端 schema：migrations + sync RPC（托管 Supabase）
docs/                产品/运营/商店文档（design|ops|store，非代码文档）
.claude/docs/        模块级技术文档（按需加载，见文末索引）
```

## 模块索引

| 模块 | 层级 | 描述 | 文档 |
|------|------|------|------|
| core_domain | 基础层 | 模型/值对象/常量，零依赖 | [.claude/docs/core_domain/](.claude/docs/core_domain/README.md) |
| ui_kit | 基础层 | 设计 token/组件/转场（约束体系） | [.claude/docs/ui_kit/](.claude/docs/ui_kit/README.md) |
| core_db | 数据层 | Drift 表+DAO+outbox 写入 | [.claude/docs/core_db/](.claude/docs/core_db/README.md) |
| server-supabase | 数据层 | 云端表结构+sync RPC | [.claude/docs/server-supabase/](.claude/docs/server-supabase/README.md) |
| core_ai | 基础层·共享服务 | AI 双解析+OCR+降级缓存 | [.claude/docs/core_ai/](.claude/docs/core_ai/README.md) |
| feature_sync | 基础层·共享服务 | outbox+HLC 同步引擎 | [.claude/docs/feature_sync/](.claude/docs/feature_sync/README.md) |
| feature_dashboard | 业务层 | 日期仪表盘 | [.claude/docs/feature_dashboard/](.claude/docs/feature_dashboard/README.md) |
| feature_ledger | 业务层 | 记账与统计 | [.claude/docs/feature_ledger/](.claude/docs/feature_ledger/README.md) |
| feature_plan | 业务层 | 待办/健身计划/存钱目标 | [.claude/docs/feature_plan/](.claude/docs/feature_plan/README.md) |
| feature_capture | 业务层 | 拍照→解析→双账录入动线 | [.claude/docs/feature_capture/](.claude/docs/feature_capture/README.md) |
| apps-mobile | 业务层·组装壳 | 路由/DI/通知/计费/主题/语音/telemetry | [.claude/docs/apps-mobile/](.claude/docs/apps-mobile/README.md) |

## 核心架构

```
UI (feature_* 页面/Provider, Riverpod 3)
  ├─ 读: Drift DAO Stream (core_db) —— 实时投影
  └─ 写: 业务 DAO → local_write_clock → sync_outbox_writer (core_db)
                                        ↓
      SyncEngine (feature_sync: outbox+HLC) ⇄ Supabase RPC (server/supabase)
AI 动线: feature_capture → core_ai (parse/llm/photo/receipt) → OpenAI 兼容端点 / 百度 OCR
        解析结果 → ledger entry + food_items 双账落库，统一走 outbox 同步
```

## 模块依赖关系

- core_domain：零依赖，被全部 8 个 Dart 包依赖
- core_db → core_domain；core_ai → core_domain + core_db
- ui_kit：零依赖（纯设计系统）；feature_sync → core_domain + core_db（+ supabase）
- feature_dashboard / ledger / plan → core_domain + core_db + ui_kit
- feature_capture → 上述 + core_ai
- apps/mobile → 全部 9 包（唯一组装点）

## 环境配置

无独立配置模块：dart-define 键 + 包内默认值 + Gradle 镜像 → 详见 [_config.md](.claude/docs/_config.md)

## 重要坑点

1. 出包必须 `cd apps/mobile`，在仓库根执行 flutter build 不产 APK
2. **RPC 命名错位（真实缺陷）**：客户端调 `push_batch`/`pull_changes`，服务端函数是 `sync_push_batch`/`sync_pull_changes`——真实联调必 PGRST202（fakes 按客户端命名镜像所以测试全绿）；修复方案见 .claude/docs/server-supabase/pitfalls.md 第 1 条
3. Supabase 缺省 LocalLoopback：无凭据时静默走本地回环，别误判"同步在真跑"（排查先看 describeSyncBackend 状态）
4. 业务行+outbox 必须同事务：`SyncOutboxWriter.enqueueRow` 在业务写之后调用（读回行终态构 payload），漏调=静默丢同步；pull 落库侧严禁调用（回声循环）
5. 改一张同步真值表要联动 5 处：Drift 表类+build_runner、SyncOutboxWriter._infos、feature_sync kSyncTables、Supabase migration、sync_table_registry 列白名单（payload 未知键被服务端静默忽略）
6. AI 通道 id ≠ 展示名（deepseek-flash vs DeepSeek-V4.1-Flash-1017）；key 只走 env/dart-define 不入仓库
7. HLC 定宽 13:6:12 是「字典序=时间全序」的唯一保证：手拼非定宽 hlc 会让 DB TEXT 比较错序（999>1000）
8. confirmed 后 money 行 amount 不可变（强制点在 core_db upsert 抛异常）：唯一合法路径是 supersede 新增 correction 行
9. 主键必须 generateUuidV7：attachments/ai_parses 的 7 天时效从 id 内嵌时间戳判定，非 UUIDv7 会被 purgeExpired 跳过
10. dynamic_color 必须精确 pin 1.8.1：1.9.0 release 构建必挂（debug 正常，极易误判为环境问题）
11. MotionLevel=off 全库纪律：每条动画路径必须显式 off 分支（100ms fadeOff），否则 off 档测试 pumpAndSettle 永挂
12. 动效 token 绑定帧预算：改 ui_kit tokens/transitions 需跑 telemetry（apps/mobile/lib/telemetry）验证
13. capture_photo_test 已知 flaky：pump+runAsync 轮询桥热机负载偶发超帧预算（CI 复现再修）
14. IAP/升级计划代码保留但 UI 不露出（菜单页重设计后整块移除）

## 模块变更日志

每个模块的 `.claude/docs/{模块}/CHANGELOG.md` 记录近期提交、变更文件、风险评级（LOW/MEDIUM/HIGH）与回滚指南；排查跨模块 bug 优先阅读——基础模块（core_db/ui_kit/core_ai）的变更会影响所有业务模块。

## 文档索引

| 模块 | 内容 | 状态 |
|------|------|------|
| [core_domain](.claude/docs/core_domain/README.md) | README + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [ui_kit](.claude/docs/ui_kit/README.md) | README + api-components/transitions + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [core_db](.claude/docs/core_db/README.md) | README + api-dao + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [server-supabase](.claude/docs/server-supabase/README.md) | README + api-rpc + data-model + pitfalls + CHANGELOG | ✅ |
| [core_ai](.claude/docs/core_ai/README.md) | README + api-parse/receipt/llm + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [feature_sync](.claude/docs/feature_sync/README.md) | README + api-sync + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [feature_dashboard](.claude/docs/feature_dashboard/README.md) | README + api-pages + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [feature_ledger](.claude/docs/feature_ledger/README.md) | README + api-admin/bill-view/report + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [feature_plan](.claude/docs/feature_plan/README.md) | README + api-todo/fitness/savings + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [feature_capture](.claude/docs/feature_capture/README.md) | README + api-capture + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [apps-mobile](.claude/docs/apps-mobile/README.md) | README + api-routes/services + data-model + code-patterns + pitfalls + CHANGELOG | ✅ |
| [_config.md](.claude/docs/_config.md) | 全局配置（dart-define/构建镜像/CI） | ✅ |

> 既有产品设计文档见 docs/design/README.md；排查跨模块 bug 优先读各模块 CHANGELOG.md。
