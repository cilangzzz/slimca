# Slimca 设计文档索引

工作名 **Slimca**：日期仪表盘 + AI 解析（热量+花费双产出）+ 分开记账 + 健身 + 计划/存钱目标，本地优先 + 跨设备同步，主题自定义 + 高强度动效。

| 文档 | 内容 |
|---|---|
| [市场调研与竞品分析.md](市场调研与竞品分析.md) | 2026-11-16 五路并行网调综合：阵营地图、8 个最近竞品与差距、市场空白、差异化主张、风险与来源链接。结论：无成熟产品覆盖全部需求，组合空白成立 |
| [产品设计文档.md](产品设计文档.md) | 定稿设计（12 章）：P0/P1/P2 功能、21 表数据模型（facet 拆行）、outbox+HLC 同步与冲突矩阵、AI 解析管线与成本估算、三层设计 token 主题系统、动效 token 与帧预算、技术选型、W1-W24 里程碑 |

## 已定决策

- 技术栈：Flutter 3.32 + Riverpod 3 + go_router + Drift + 托管 Supabase（自研 outbox+HLC，SyncEngine 可换 PowerSync）+ OpenAI 兼容 LLM adapter（§10）
- 单仓分包：`apps/mobile` + `core_db/core_domain/core_ai/ui_kit` + `feature_*` + `server/supabase`（§10.4）
- 里程碑：M1 2026-12-27 / M2 2027-01-24（v1.0 公测）/ M3 2027-03-07（§11）
- 平台：Android 先行（本机无 Mac），iOS 走 Codemagic 云 Mac

## 待拍板（§12.2，各有决策时点）

行级 LWW 取舍、PowerSync 法务结论、AI 供应商组合、定价数字实测复核、存钱是否联动账本流水等 11 项，见产品设计文档 §12.2。
