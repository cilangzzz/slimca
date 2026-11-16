/// 空库首次打开的默认数据 seed 编排（§5.4、§3.4、§11.1 W2）。
///
/// 由 `AppDatabase.migration` 的 beforeOpen 调用（「空库首次打开 seed」）。
/// 幂等：可重复执行——缺什么补什么、已有业务行不动（详见各 DAO 的 seed
/// 方法注释）。内容：
/// - 默认 money 账本（MVP 恒默认账本，§3.4 单账本 MVP）；
/// - 内置 kcal 账本恰一个（不可删除不可多开，§5.4④）；
/// - 20+ 内置中文分类，expense/income 并存（§3.4 内置分类、§5.4⑤）；
/// - settings：device_id（§5.1 公共列的设备侧落点）与 default_ledger_id
///   （§5.6⑲「默认账本」）。
library;

import '../app_database.dart';
import 'category_dao.dart';
import 'ledger_dao.dart';
import 'local_write_clock.dart';

/// 执行全部默认数据 seed（幂等）。
Future<void> seedDefaultData(AppDatabase db) async {
  // 设备标识先行：后续所有 seed 行的 device_id/hlc 共用同一时钟与标识
  // （§5.1 公共列、§6.3）。
  final clock = LocalWriteClock(db);
  await clock.deviceId();
  await LedgerDao(db, clock: clock).seedDefaults();
  await CategoryDao(db, clock: clock).seedPresets();
}
