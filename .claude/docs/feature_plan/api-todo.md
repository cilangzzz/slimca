# api-todo — 待办域 API

> 待办基础（W5-6）+ 完整版（W13 重复/提醒）。持久化复用 core_db `TodoDao`
> （done_at 只前进合并 §6.5），重复实例的**查询时展开**在本域网关完成。

## PlanGateway 待办方法（8 个）

### 写路径（5）

| 方法 | 签名要点 | 语义 |
|------|----------|------|
| `createTodo` | `({required String title, String? date, String? note, int? dueAt, String? repeatRule, String? rruleAnchorDate, int? remindAt}) → Future<Todo>` | `date=null` = 收集箱；`repeatRule` 为 RRULE 文本（编辑器经 `TodoRepeatSpec.toRrule` 构造）；`rruleAnchorDate` 缺省时 TodoDao 取 `date` 作 DTSTART；`remindAt` 为 UTC ms（只落字段，真实通知由壳层调度） |
| `updateTodoDetails` | `({required String id, String? title, String? note, String? repeatRule, int? remindAt, bool clearAnchor = false, String? anchorDate}) → Future<void>` | `repeatRule`/`remindAt` 显式覆盖（null=清空）。锚点：`clearAnchor=true` → 锚点置空（series 终结）；`anchorDate` 非空 → 设锚点；两者都缺省 → 锚点不动（Object 哨兵透传） |
| `setTodoDone` | `(String id, {required bool done}) → Future<void>` | done_at 只前进合并（set 胜，§6.5）；重复实例勾选同样作用于基行（不物化实例行） |
| `deleteTodo` | `(String id) → Future<void>` | 软删墓碑；作用于整条 series 基行（v1 无「仅删当日实例」） |
| `moveTodoToToday` | `(String id, {required String date}) → Future<void>` | 收集箱 → 计划日回填（「一键安排到今天」） |

### 读路径（3）

| 方法 | 返回 | 语义 |
|------|------|------|
| `watchTodosByDate(date)` | `Stream<List<Todo>>` | 原始基行流（未完成在前）；W13 后 UI 主用 `watchTodoDayInstances` |
| `watchInboxTodos()` | `Stream<List<Todo>>` | `date IS NULL` 且未删 |
| `watchTodoDayInstances(date?)` | `Stream<List<TodoDayInstance>>` | **某日实例流**（核心展开逻辑）：`date=null` → 收集箱基行直出不展开；非重复行 `date=当日` 直出；重复行按 anchor 展开 `rruleOccursOn` 命中当日 → 虚拟实例（anchor 缺省回退基行 `date`；锚点日基行与实例合一不重复渲染）。实例完成口径：`done_at` 非空**且落在实例日**（本地日历日） |

## RRULE 工具（rrule.dart，纯函数无 IO）

| 符号 | 语义 |
|------|------|
| `TodoRepeatSpec` | 结构化五档：`none/daily/weekly(weekday)/monthly(monthDay)/everyNDays(intervalDays)`；`toRrule()` 转 RFC5545 文本（none → null）；`fromRrule(text)` 反解，无法识别的子集返回 **null**（不抛错）；`label` 中文摘要（「每周一」「每3天」） |
| `parseRrule(text)` | RFC5545 v1 子集解析：`FREQ`（DAILY/WEEKLY/MONTHLY）、`INTERVAL≥1`、`BYDAY` 单值、`BYMONTHDAY` 1-31；未知键（UNTIL/COUNT 等）忽略，坏值整体返回 null |
| `rruleOccursOn({anchorDay, rule, day})` | 规则是否在 `day` 产生实例；闭区间含锚点日；DAILY 按 `days % interval`、WEEKLY 按 BYDAY + 整周桶、MONTHLY 按 BYMONTHDAY + 月桶；坏日期/早于锚点 → false |
| `remindAtMsFor({day, hour, minute})` | 本地日历日 + 时:分 → 提醒时刻 UTC ms |
| `localTimeOfDay(remindAtMs)` | UTC ms → 本地 `(hour, minute)`（跨时区 travel 后回显随偏移，v1 接受） |
| `formatTimeOfDay({hour, minute})` | `HH:mm` 零填充 |
| `dayDiff(fromDay, toDay)` | 整天数差（DST 安全：按小时差四舍五入） |
| `featureLocalToday()` | 设备本地今日 `yyyy-MM-dd`（域内统一「今日」口径，勿各自取 now） |

## Providers（3 个 reactive 读侧）

| Provider | family key | 返回 |
|----------|-----------|------|
| `todayTodosProvider` | `String`（date） | `Stream<List<Todo>>` 基行流 |
| `inboxTodosProvider` | — | `Stream<List<Todo>>` 收集箱 |
| `todoDayInstancesProvider` | `String?`（date；null=收集箱） | `Stream<List<TodoDayInstance>>` 实例流（UI 主用） |

## 页面与组件

### TodoPage（ConsumerStatefulWidget）

- 双视图 `SegmentedButton`（今日/收集箱）；今日视图读 `todoDayInstancesProvider(_today)`，收集箱读 `todoDayInstancesProvider(null)`；`_today` 页面生命周期内固定（防跨日抖动）。
- 快速输入条：今日视图新增带当日 date、收集箱视图新增 date=null。
- 瓦片操作：勾选 `setTodoDone`、删除 `deleteTodo`（整条 series）、收集箱项「加入今日」`moveTodoToToday`、进阶按钮开 `TodoEditorSheet`（编辑基行 / 新建）。
- 测试锚点：`todoInputKey` `todoAddKey` `todoAdvancedKey` `todoCheckKey(id)` `todoDeleteKey(id)` `todoMoveTodayKey(id)`。

### TodoEditorSheet（showSlimcaSpringSheet 弹簧抽屉）

- 新建：`planDate`（今日视图挂当日、收集箱挂 null）+ 五档重复 + 提醒开关/时刻选择 → `createTodo`。
- 编辑基行：回显 → `updateTodoDetails`；清空重复规则时传 `clearAnchor: true`。
- 收集箱入口隐藏重复档（date=NULL 无展开起点）。
- 测试锚点：`todoEditorTitleKey` `todoEditorNoteKey` `todoEditorSaveKey` `todoRepeatChipKey` `todoWeekdayChipKey` `todoEditorMonthDayKey` `todoEditorIntervalKey` `todoEditorRemindToggleKey` `todoEditorRemindPickKey` `todoEditorRemindClearKey`。

## 数据模型

见 [data-model.md](data-model.md)（`Todo` 基行三字段 `repeat_rule`/`rrule_anchor_date`/`remind_at`；`TodoDayInstance` 虚拟实例）。

## 提醒调度边界

feature 层只落 `remind_at` 字段；真实本地通知由壳层承担（apps/mobile 的 ReminderSyncCoordinator：todos 流 → ReminderPlanner 纯函数 → 调度器差异对账）。改 `remind_at`/RRULE 后无需在本包做任何调度调用。
