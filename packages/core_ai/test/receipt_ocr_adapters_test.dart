/// 端侧 OCR 适配器与通道桥测试（§11.2 W16 任务第 1 项：FakeAdapter（fixture）
/// + MlKit/Vision 适配器骨架 + 平台通道注入；任务硬规则：禁止真实平台通道
/// ——MethodChannel 走 TestDefaultBinaryMessenger mock，其余走脚本化 Fake）。
library;

import 'dart:io' show Platform;

import 'package:core_ai/core_ai.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'receipt_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeReceiptOcrAdapter（fixture，W16 任务口径）', () {
    test('fixed：恒返回缺省 fixture 草稿；原图输入被记录（即用即焚断言基底）',
        () async {
      final adapter = FakeReceiptOcrAdapter.fixed();
      final input = ReceiptImageInput(
        bytes: makeReceiptJpegFixture(),
        mime: 'image/png',
      );
      final draft = await adapter.recognize(input);

      expect(identical(draft, kDefaultReceiptDraft), isTrue);
      expect(adapter.providerId, 'fake_receipt_ocr');
      expect(adapter.lastImage, same(input));
      expect(adapter.images, hasLength(1));
    });

    test('scripted：草稿与 LlmException 按序弹出；耗尽抛 StateError', () async {
      final adapter = FakeReceiptOcrAdapter.scripted(<Object>[
        const ReceiptDraft(merchant: '小卖部', totalMinor: 500),
        const LlmTimeoutException('端侧 OCR 超时（测试）'),
      ]);
      final input =
          ReceiptImageInput(bytes: Uint8List(0), mime: 'image/jpeg');

      final first = await adapter.recognize(input);
      expect(first.merchant, '小卖部');
      await expectLater(
        adapter.recognize(input),
        throwsA(isA<LlmTimeoutException>()),
      );
      await expectLater(
        adapter.recognize(input),
        throwsStateError,
        reason: '脚本耗尽显式暴露（与预期调用次数不符）',
      );
    });

    test('fromTextLines：fixture 文本行经共享抽取器（字段理解真实路径）',
        () async {
      final adapter = FakeReceiptOcrAdapter.fromTextLines(kFixtureReceiptLines);
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
      );
      expect(draft.merchant, '全家便利店');
      expect(draft.totalMinor, 1250);
      expect(draft.lineItems, hasLength(2));
    });
  });

  group('MlKit/Vision 平台通道适配器骨架（ReceiptOcrChannel 注入）', () {
    test('MLKit：通道协议（method/args）+ textLines 结果经端侧字段抽取', () async {
      final channel = FakeReceiptOcrChannel.scripted(<Object>[
        <String, Object?>{'textLines': kFixtureReceiptLines},
      ]);
      final adapter = MlKitReceiptOcrAdapter(channel: channel);
      expect(adapter.providerId, 'mlkit');
      expect(adapter.modelId, 'mlkit-text-recognition-v2');

      final bytes = makeReceiptJpegFixture();
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: bytes, mime: 'image/jpeg'),
      );

      expect(draft.merchant, '全家便利店');
      expect(draft.totalMinor, 1250);
      // 通道协议（receipt_ocr_adapter.dart 契约）。
      final (method, args) = channel.calls.single;
      expect(method, kMethodRecognizeReceipt);
      expect(args['mime'], 'image/jpeg');
      expect(args['imageBytes'], same(bytes), reason: '字节原样注入通道（即用即焚）');
    });

    test('Vision：同协议；providerId/modelId 平台区分', () async {
      final channel = FakeReceiptOcrChannel.scripted(<Object>[
        <String, Object?>{'textLines': kFixtureReceiptLines},
      ]);
      final adapter = VisionReceiptOcrAdapter(channel: channel);
      expect(adapter.providerId, 'vision');
      expect(adapter.modelId, 'vision-recognize-text-v2');
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
      );
      expect(draft.totalMinor, 1250);
      expect(channel.calls.single.$1, kMethodRecognizeReceipt);
    });

    test('整段 text 兼容载荷（协议容错：按换行切分）', () async {
      final adapter = MlKitReceiptOcrAdapter(
        channel: FakeReceiptOcrChannel.scripted(<Object>[
          <String, Object?>{'text': '全家便利店\n实收 12.50'},
        ]),
      );
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
      );
      expect(draft.merchant, '全家便利店');
      expect(draft.totalMinor, 1250);
      expect(draft.warnings.join('；'), contains('小票时间未识别'));
    });

    test('空 textLines → 空草稿返回（空结果=正常业务分支，§7.4 手填由管线判）',
        () async {
      final adapter = MlKitReceiptOcrAdapter(
        channel: FakeReceiptOcrChannel.scripted(<Object>[
          <String, Object?>{'textLines': <String>[]},
        ]),
      );
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
      );
      expect(draft.hasText, isFalse);
    });

    test('协议违约（非 Map 结果）→ LlmBadResponseException（§7.1 分类）',
        () async {
      final adapter = MlKitReceiptOcrAdapter(
        channel: FakeReceiptOcrChannel.scripted(<Object>[42]),
      );
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('通道异常原样上抛（分类在通道桥完成，§7.1）', () async {
      final adapter = MlKitReceiptOcrAdapter(
        channel: FakeReceiptOcrChannel.scripted(<Object>[
          const LlmInvalidRequestException('通道桥已分类（测试）'),
        ]),
      );
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmInvalidRequestException>()),
      );
    });

    test('超时裁定：通道永不完成 → LlmTimeoutException（骨架口径可注入覆写）',
        () async {
      final adapter = MlKitReceiptOcrAdapter(
        channel: FakeReceiptOcrChannel.hang(),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmTimeoutException>()),
      );
    });

    test('空字节 → LlmInvalidRequestException（请求非法，通道零调用）', () async {
      final channel = FakeReceiptOcrChannel.scripted(<Object>[]);
      final adapter = MlKitReceiptOcrAdapter(channel: channel);
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: Uint8List(0), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmInvalidRequestException>()),
      );
      expect(channel.calls, isEmpty);
    });
  });

  group('MethodChannelReceiptOcrChannel（flutter/services 桥；mock handler）', () {
    const testChannel = MethodChannel('slimca/receipt_ocr_test');

    test('成功路径：invokeMethod 结果透传；args 按 StandardMethodCodec 编解码',
        () async {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(testChannel, (call) async {
        expect(call.method, kMethodRecognizeReceipt);
        expect(call.arguments['mime'], 'image/jpeg');
        expect(call.arguments['imageBytes'], isA<Uint8List>());
        return <String, Object?>{'textLines': kFixtureReceiptLines};
      });
      final adapter = MlKitReceiptOcrAdapter(
        channel: MethodChannelReceiptOcrChannel(channel: testChannel),
      );
      final draft = await adapter.recognize(
        ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
      );
      expect(draft.merchant, '全家便利店');
      expect(draft.totalMinor, 1250);
    });

    test('PlatformException（端侧引擎异常）→ LlmBadResponseException', () async {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(testChannel, (call) async {
        throw PlatformException(code: 'ocr_native', message: '引擎崩溃（测试）');
      });
      final adapter = MlKitReceiptOcrAdapter(
        channel: MethodChannelReceiptOcrChannel(channel: testChannel),
      );
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('native 未接线（MissingPluginException）→ LlmInvalidRequestException'
        '（remaining：真机验收前的用户路径=一级降级手填）', () async {
      // 未设置 handler（native handler 缺位的真实形态）。
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(testChannel, null);
      final adapter = MlKitReceiptOcrAdapter(
        channel: MethodChannelReceiptOcrChannel(channel: testChannel),
      );
      await expectLater(
        adapter.recognize(
          ReceiptImageInput(bytes: makeReceiptJpegFixture(), mime: 'image/jpeg'),
        ),
        throwsA(isA<LlmInvalidRequestException>()),
      );
    });
  });

  group('dart-define 装配工厂（receipt_factory.dart）', () {
    test('显式注入优先：createReceiptParser 透传 ocrAdapter/aiParser', () {
      final ocr = FakeReceiptOcrAdapter.fixed();
      final ai = FakeAiParser(<Object>[]);
      final parser = createReceiptParser(ocrAdapter: ocr, aiParser: ai);
      expect(identical(parser.ocrAdapter, ocr), isTrue);
      expect(identical(parser.aiParser, ai), isTrue);
    });

    test('缺省装配（桌面/测试宿主）→ Fake 离线桩 + 默认 mock 文本管线', () {
      if (Platform.isAndroid || Platform.isIOS) {
        // 真机/模拟器上按平台选择 MLKit/Vision（§1.3 Android 优先）。
        expect(
          defaultReceiptOcrAdapter(),
          anyOf(isA<MlKitReceiptOcrAdapter>(), isA<VisionReceiptOcrAdapter>()),
        );
      } else {
        final ocr = defaultReceiptOcrAdapter();
        expect(ocr, isA<FakeReceiptOcrAdapter>());
      }
      final parser = createReceiptParser();
      expect(parser.aiParser, isA<LlmAiParser>());
    });
  });
}
