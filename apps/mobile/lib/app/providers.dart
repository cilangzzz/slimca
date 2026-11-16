/// 应用级依赖注入（§10.4 apps/mobile：路由 + DI + 主题装配）。
///
/// W2 Riverpod 接线（§11 W2）：`Provider<AppDatabase>` 单例 + HlcClock 单例 +
/// 各 repository providers——页面/用例只经 provider 取依赖，且依赖抽象
/// （core_domain 仓库接口）而非 Drift 实现（§10.4 分层纪律）。
///
/// 装配方式：`bootstrap()`（lib/app/bootstrap.dart）在 runApp 前 await 完成
/// 异步初始化（开库、device_id、内置账本种子），以 override 注入单例；
/// 运行期读取全部同步、零等待（§2.3 全程零等待空屏）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_parser.dart';
import '../ai/ai_parser_factory.dart';
import '../data/ai_parse_cache.dart';
import '../data/drift_repositories.dart';

/// 应用主库单例（§10.1 数据层选型 Drift）。
///
/// 生产路径：缺省执行器 = core_db `driftDatabase('slimca')`（按平台落
/// path_provider 目录，§5.1）；测试路径：override 为
/// `AppDatabase(NativeDatabase.memory())` 内存库。
final appDatabaseProvider = Provider<db.AppDatabase>((ref) {
  final database = db.AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// HLC 混合逻辑时钟单例（§6.3：物理段取 max、同 ms 计数器自增、
/// 定宽编码字典序=全序、回拨不影响全序）。
///
/// 必须由 bootstrap() override 后使用：device_id 需异步读 settings 表
/// （§5.6⑲）才能构造时钟，而 Provider 构造是同步的——启动期一次性装配。
/// 读取方（写路径用例、删键按钮）一律 ref.read 即取即用，每次发号单调
/// （§6.3 全序纪律）。
final hlcClockProvider = Provider<HlcClock>((ref) {
  throw StateError(
    'hlcClockProvider 未装配：必须由 bootstrap() override 后使用'
    '（device_id 依赖异步读 settings，见 lib/app/bootstrap.dart）',
  );
});

/// 事件主干仓库 provider（§5.2① entries；接口定义 core_domain/repository.dart）。
final entryRepositoryProvider = Provider<EntryRepository>((ref) {
  return DriftEntryRepository(ref.watch(appDatabaseProvider));
});

/// 产出行（facet 行）仓库 provider（§5.2②/§5.3 entry_lines）。
final entryLineRepositoryProvider = Provider<EntryLineRepository>((ref) {
  return DriftEntryLineRepository(ref.watch(appDatabaseProvider));
});

// ── W3-4 AI 解析装配（§11.1 W3-4 主线、§7.1 管线、§10.4 壳负责装配）──

/// AI 解析器 provider——**默认 FakeParser mock**（§11.1 W3-4）。
///
/// 中文注记（任务要求）：真实 adapter 待 API key 配置后经
/// `--dart-define=SLIMCA_AI_BASE` / `--dart-define=SLIMCA_AI_KEY` /
/// `--dart-define=SLIMCA_AI_MODEL` 切换；读取逻辑已写在
/// lib/ai/ai_parser_factory.dart（key 缺省 → mock；key 就位 →
/// OpenAiCompatAdapter，base/model 缺省回落 §7.5 默认值），**默认 mock**。
/// 测试一律 override 为注入的 Fake/Mock 解析器，禁止真实网络调用。
final aiParserProvider = Provider<AiParser>((ref) => createAiParser());

/// ai_parses 缓存 DAO provider（§5.6⑭：input_hash=sha256(规范化输入) 7 天
/// 缓存键；注入 AI 录入网关，任务项 3「input_hash 缓存注入」）。
final aiParseCacheProvider = Provider<AiParseCache>((ref) {
  return AiParseCache(ref.watch(appDatabaseProvider));
});
