// 录入抽屉统一高度守护测试（本次 UX 插曲新增口径：抽屉高度与内容状态
// 解耦，§9.3#3 弹簧抽屉的延伸约束）。
//
// 用户验收口径：档位（钱+热量/仅记钱/仅记热量）、通道（写/说/拍）、AI 阶段
// （输入/解析中/确认卡/降级）切换时抽屉高度恒不变（UI 不随内容缩放）：
// - 独立 showCaptureSheet：高度恒为 captureSheetHeight（视口 88%、上限 720），
//   档位切换不缩放；该面保留拍照/相册入口（此面唯一拍照入口）；
// - 通道抽屉 showCaptureChannelsSheet：加载帧→AI 输入→仅记钱表单→说→拍→
//   写回，全程同一高度；拍照入口收敛到「拍」通道（写通道无拍照按钮，
//   单一入口纪律）。
//
// 装配与 e2e 同口径：内存真库 + 固定 device_id HlcClock + bootstrap 同款
// 网关/解析器工厂（§10.4）；Windows 宿主缺 sqlite3 运行库时温和跳过。

import 'dart:async';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/capture/capture_channels_sheet.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 e2e 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存真库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：见 e2e_record_to_dashboard_test 同款
/// 注释（fake_async 区 teardown 的 Timer 官方出口）。
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

/// 统一装配：内存库 + 固定 HLC + bootstrap 同款网关/解析器（§10.4）。
Future<ProviderScope> _buildHarness(db.AppDatabase database) async {
  const deviceId = 'ABCDEF123456';
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      hlcClockProvider.overrideWithValue(clock),
      captureGatewayProvider
          .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
      captureParserProvider.overrideWithValue(createCaptureParser()),
    ],
    child: MaterialApp(
      theme: buildTheme(brightness: Brightness.light),
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}

double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(captureSheetSizeKey)).height;

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

void main() {
  testWidgets('独立录入抽屉：装载帧/档位切换抽屉高度不变，拍照入口保留',
      (WidgetTester tester) async {
    // 放大视口 → captureSheetHeight 命中 720 上限（0.88×1800=1584→720）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，抽屉统一高度用例未执行');
      return;
    }
    addTearDown(database.close);
    final harness = await _buildHarness(database);
    await tester.pumpWidget(harness);

    final context = tester.element(find.byType(Scaffold).first);
    final expected = captureSheetHeight(context);
    expect(expected, 640.0, reason: '大视口命中上限档');

    // 抽屉 Future 在关闭时才完成——不能 await（测试体永挂），unawaited 唤起。
    unawaited(showCaptureSheet(context, seed: const CaptureSeed()));
    // 加载帧（form==null）即已是统一高度——打开后不随装载涨高。
    await tester.pump();
    expect(_sheetHeight(tester), expected);

    await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
    // AI 输入区出现后弹簧入场仍在滑入（220ms springSnappy）：收敛后再交互。
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), expected,
        reason: '装载完成（AI 输入区）不涨高');

    // 独立抽屉保留拍照/相册入口（该面唯一拍照入口，§11.2 W11-12）。
    expect(find.byKey(capturePhotoCameraKey), findsOneWidget);
    expect(find.byKey(capturePhotoGalleryKey), findsOneWidget);

    // 档位切换「仅记钱」：表单内容变高，抽屉高度恒不变。
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture_amount_display')), findsOneWidget);
    expect(_sheetHeight(tester), expected, reason: '仅记钱档不缩放抽屉');

    // 键盘避让：外框高度恒定，内容区按 viewInsets.bottom 收缩——钉底
    // 保存 CTA 底边不超过键盘上沿（edge-to-edge 口径，评审项 C1/C6）。
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(_sheetHeight(tester), expected, reason: '键盘弹出外框高度不变');
    final submitBottom = tester.getRect(find.byKey(captureSubmitKey)).bottom;
    expect(submitBottom, lessThanOrEqualTo(1800 - 300),
        reason: '钉底 CTA 让出键盘（视口高 1800、键盘 300）');
  });

  testWidgets('通道抽屉：装载/档位/写说拍切换全程同一高度，拍照入口唯「拍」通道',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，抽屉统一高度用例未执行');
      return;
    }
    addTearDown(database.close);
    final harness = await _buildHarness(database);
    await tester.pumpWidget(harness);

    final context = tester.element(find.byType(Scaffold).first);
    final expected = captureSheetHeight(context);

    unawaited(showCaptureChannelsSheet(context, seed: const CaptureSeed()));
    await tester.pump();
    expect(_sheetHeight(tester), expected, reason: '加载帧即统一高度');

    await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
    // 弹簧入场收敛后再交互（与独立抽屉用例同口径）。
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), expected, reason: '写通道装载完成不涨高');

    // 单一拍照入口：写通道 AI 输入区不再内嵌拍照/相册按钮（§10.4）。
    expect(find.byKey(capturePhotoCameraKey), findsNothing);
    expect(find.byKey(capturePhotoGalleryKey), findsNothing);

    // 通道切换 说 → 拍 → 写：高度恒不变；拍照入口在「拍」通道
    // （注意先验通道再切档——money 档「拍」面板按 §3.3 显示无拍照语义提示）。
    await tester.tap(find.byKey(captureChannelVoiceKey));
    await tester.pump();
    expect(find.text('说一笔'), findsOneWidget);
    expect(_sheetHeight(tester), expected, reason: '说通道不缩放抽屉');

    await tester.tap(find.byKey(captureChannelPhotoKey));
    await tester.pump();
    expect(find.text('拍一笔'), findsOneWidget);
    expect(find.byKey(capturePhotoCameraKey), findsOneWidget,
        reason: '「拍」通道为唯一拍照入口');
    expect(find.byKey(capturePhotoGalleryKey), findsNothing,
        reason: '拍照单一入口：相册选择不重复露出');
    expect(_sheetHeight(tester), expected, reason: '拍通道不缩放抽屉');

    await tester.tap(find.byKey(captureChannelTextKey));
    await tester.pump();
    expect(find.text('记一笔'), findsOneWidget);
    expect(_sheetHeight(tester), expected, reason: '切回写通道不缩放抽屉');

    // 档位切换「仅记钱」：抽屉高度恒不变。
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture_amount_display')), findsOneWidget);
    expect(_sheetHeight(tester), expected, reason: '仅记钱档不缩放抽屉');
  });
}
