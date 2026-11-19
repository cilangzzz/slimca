// 帧预算 benchmark 骨架（§9.4 性能预算硬指标、§11.1 W9-10「北极星实测·
// 真机帧率」）。
//
// 本文件是 CI 可跑的**确定性时长预算骨架**（fake clock 驱动，跨宿主稳定），
// 锁三条 UI 层预算：
//   1. 冷启动首帧直出——首帧即完整壳+零值空态，无加载态（§2.3 步 0 /
//      §9.4 冷启动 ≤1.2s 的 UI 等价口径：本测试锁「无 spinner 骨架」，
//      秒数本身待真机）；
//   2. 录入抽屉打开→可输入 ≤280ms（§9.4 / §2.3 步 2）；
//   3. 切日共享轴转场 ≤280ms+两帧容差（§9.3#2 / §2.3 步 7——隔离测转场
//      原语；真页切日还有卡片级联重播，§9.3#1 预算另计）。
//
// **真机帧率数字待真机实测（M2 闸门=代码与素材就绪）**：丢帧率 <1%（G99
// 级）、raster ≤16ms / build ≤8ms（§9.4）需真机 profile 模式采集——运行时
// FrameTelemetry（lib/telemetry/frame_telemetry.dart，main() 非 debug 装配）
// 会把聚合值落进 telemetry_events.jsonl（frame_raster_ms / frame_dropped，
// 周报口径），或接 DevTools 看帧级明细：
//
//   flutter run --profile                 # 真机 profile 采集
//   # <操作核心六转场：冷启动级联/切日/抽屉弹簧/count-up/Hero/morph>
//   # 导出 telemetry_events.jsonl 汇总周报（§3.9），真机数据归档
//   flutter run --profile --trace-skia    # 需要帧级火焰图时
//
// 桌面/模拟器帧率不构成验收数字（§9.4 口径：G99 级中端安卓）。
//
// 测试装配与 e2e 同口径：内存真库（Drift NativeDatabase.memory，真实
// schema/seed 链路）+ 固定 device_id HlcClock override；宿主缺 sqlite3
// 运行库时温和跳过（与 e2e 同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/app/theme.dart';
import 'package:slimca/main.dart';
import 'package:ui_kit/ui_kit.dart';

/// 单步 pump 步长（fake clock；16ms≈60Hz 一帧，§9.4 帧预算口径）。
const Duration _frameStep = Duration(milliseconds: 16);

/// §9.4 抽屉打开→可输入预算。
const int _drawerBudgetMs = 280;

/// §9.3#2 切日共享轴时长 token（MotionConfig.sharedAxis = dur.l 280ms）。
const int _sharedAxisBudgetMs = 280;

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 e2e 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存真库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
Future<db.AppDatabase?> _tryOpenMemoryDatabase() async {
  final database = db.AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    if (_isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 冷启动装配（e2e 同款 override 口径；返回库句柄交由测试 teardown）。
Future<void> _pumpApp(
  WidgetTester tester,
  db.AppDatabase database,
) async {
  // 放大视口：卡片墙/抽屉一屏放下，免滚动命中（e2e 同口径）。
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  const deviceId = 'ABCDEF123456';
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        hlcClockProvider.overrideWithValue(clock),
        captureGatewayProvider
            .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
        captureParserProvider.overrideWithValue(createCaptureParser()),
        planGatewayProvider.overrideWithValue(
          createPlanGateway(db: database, clock: clock),
        ),
      ],
      child: const SlimcaApp(),
    ),
  );
}

void main() {
  testWidgets('帧预算：冷启动首帧直出完整壳，无加载态（§2.3 步 0 / §9.4）',
      (WidgetTester tester) async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，帧预算冷启动用例未执行');
      return;
    }
    addTearDown(database.close);

    // pumpWidget 只跑一帧——此刻就应出现完整壳与零值空态（无 spinner，
    // 加载分支共用 DashboardDay.zero，§2.3 步 0「无加载态空屏」）。
    await _pumpApp(tester, database);
    expect(find.text('Slimca'), findsNothing,
        reason: '首帧即完整壳（首页 AppBar 无产品名标题，用户拍板移除）');
    expect(find.text('记一件事，钱和卡路里一起入账'), findsOneWidget,
        reason: '首帧即零值空态（无加载骨架）');
  });

  testWidgets('帧预算：录入抽屉打开→可输入 ≤280ms（§9.4 / §2.3 步 2）',
      (WidgetTester tester) async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，帧预算抽屉用例未执行');
      return;
    }
    addTearDown(database.close);

    await _pumpApp(tester, database);
    await tester.pump(_frameStep); // 冷启动级联播完的基线帧

    // 唤起抽屉，逐帧推进直到 AI 输入区可输入；累计 fake 时钟 ≤280ms。
    await tester.tap(find.byType(FloatingActionButton));
    var elapsedMs = 0;
    var inputVisible = false;
    while (elapsedMs <= _drawerBudgetMs) {
      await tester.pump(_frameStep);
      elapsedMs += _frameStep.inMilliseconds;
      inputVisible =
          find.byKey(const Key('capture_ai_input')).evaluate().isNotEmpty;
      if (inputVisible) break;
    }
    expect(inputVisible, isTrue,
        reason: '§9.4 抽屉打开→可输入 ≤${_drawerBudgetMs}ms'
            '（实测 ${elapsedMs}ms；真机数字待真机实测）');
  });

  testWidgets('帧预算：切日共享轴转场 ≤280ms+两帧容差（§9.3#2 / §2.3 步 7）',
      (WidgetTester tester) async {
    // 隔离测量转场原语（SlimcaSharedAxisSwitcher + MotionConfig token）：
    // 真页切日会随墙重建重播卡片级联（§9.3#1 级联预算另计，W2 口径），
    // 混测会污染共享轴读数——本用例只锁转场 token 本身的时长预算。
    Widget wall({required Key key}) => Container(
          key: key,
          width: 300,
          height: 120,
          color: Colors.white12,
        );
    Future<void> pumpWith(Key key) => tester.pumpWidget(
          MaterialApp(
            theme: slimcaLightTheme(),
            home: Scaffold(
              body: SlimcaSharedAxisSwitcher(child: wall(key: key)),
            ),
          ),
        );

    await pumpWith(const ValueKey(0));
    await pumpWith(const ValueKey(1)); // 换 key 触发共享轴切换
    await tester.pump(); // 转场首帧（t=0，控制器启动）
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: '共享轴转场应已启动（child 未换则在此失败，不属时长预算）');

    // 逐帧推进直到无排帧（转场完成）；容差=16ms 泵进离散化+一帧。
    var elapsedMs = 0;
    while (tester.binding.hasScheduledFrame) {
      await tester.pump(_frameStep);
      elapsedMs += _frameStep.inMilliseconds;
      if (elapsedMs > _sharedAxisBudgetMs + 3 * _frameStep.inMilliseconds) {
        break;
      }
    }
    expect(elapsedMs, lessThanOrEqualTo(_sharedAxisBudgetMs + 32),
        reason: '§9.3#2 切日共享轴 ≤${_sharedAxisBudgetMs}ms'
            '（16ms 泵进离散化+两帧容差；实测 ${elapsedMs}ms）');
  });
}
