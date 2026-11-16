## 0.0.1

* W5-6 计划域首版（§11.1 W5-6）：
  * 健身手动记录（§3.5/§5.5⑦）：内置 MET 表 + 强度档 + 时长/体重 → MET
    估算（±20% 口径标注）；提交同事务落 entries(kind=fitness) +
    entry_lines(type=burn,out) + fitness_sessions，投影联动重算；按日查看
    与删除（软删墓碑）。
  * 待办完整雏形（§3.6/§5.5⑩）：今日待办/收集箱双视图，勾选联动
    day_summary.todo_done（done_at 只前进合并 §6.5），收集箱项加入今日。
  * 存钱目标占位页（W13 全量）：目标 + Σ贡献进度读侧接通（§5.5⑪⑫）。
  * 健身计划占位页（W14 全量）：fitness_plans 读侧接通（§5.5⑧）。
  * 计划域组合页 PlanHubPage（§4.2 计划 Tab 默认实现，级联 + 共享轴转场）。
  * DI 契约：planGatewayProvider（宿主 override，§10.4 壳负责装配）。
