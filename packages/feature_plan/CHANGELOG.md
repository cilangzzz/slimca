## 0.0.1

* W14 健身计划（留存钩子，§11.2 W14、§3.5/§5.5⑧⑨）：
  * 模板+排期：计划=名称+动作列表（动作名/组数/目标次数/目标重量 ×10 定点/
    组间休息秒，exercises JSON）+ 按周排期掩码（bit0=周一…bit6=周日）；
    计划日历高亮=周排期条（排期日 kcalOut 高亮 + 今日描边「今」角标）；
    写路径 outbox 同事务入队（§6.2）。
  * 开练流：一键开练建 fitness_sessions（type=template_instance/source=plan/
    start_at 真值，不预生成空会话）；每完成一组落 exercise_sets（完成标记=
    done_at）；完成训练单事务汇总（时长=start_at 起算、kcal 走既有 MET 逻辑）
    + entries(kind=fitness)+entry_lines(type=burn) 联动 + 投影重算（复用
    W5-6 链路）。
  * 组间计时器：大数字倒计时（rest 秒从模板读）；心跳源/完成音震动反馈
    经 provider 注入（测试禁真实计时器，Fake 时钟口径）；锁屏前台化由壳层
    承担。
  * 训练历史页：按日/按计划双维度分组。
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
