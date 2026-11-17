## 0.0.1

* 初始版本：卡片墙（热量环/支出/净热量/存钱进度）、周历切日共享轴、
  day_summary 投影接线（§3.2/§5.6⑬、§10.4）。
* W17 插曲（UI-规范与重设计.md §3/§5——feature_dashboard 范围）：
  - 首页日历重做（§3 定稿）：接入 ui_kit 语义组件 `SlimcaCalendar`（周条
    无限横滑翻周＋垂直手势展开月网格（形变式）＋今日锚定簇），替换原固定
    七天周条；页面头部追加「今天」pill（横滑离开今天后浮现，点击回今日+
    卡片墙滚顶，280ms SharedAxis 回位）与「月历图标」展开入口（§3.2 手势阶梯）；
  - 切日共享轴保留（§9.3#2，280ms token 不变）；「左右滑切日」手势收敛到
    卡片墙区域（与周条「翻周不切日」双语义不打架，§3.2 设计决策）；
  - 月格 Compact 色点数据源：`DashboardRepository.watchRecordedDays()`（§3.3
    day_summary 聚合直出，全投影表 watch；V1 一点=有记录，点数映射随 W17 扩展）；
  - 约束审计修正（§5）：卡片 radius/padding 改引 `sizes.radiusCard`/
    `spacing.inline`（§5#1 合规基线 token 化）、卡间距 `spacing.cardInner`、
    页边/行内间距 token 化（§1.3 落点）；级联入场复核（§9.3#1 80ms 级联合规保留）；
  - `DashboardPage` 新增可选 `today`/`weekStart` 注入（测试与宿主固定口径，
    缺省运行当天/locale 周起始）；日历工具补 `DashboardCalendar.parse`。
