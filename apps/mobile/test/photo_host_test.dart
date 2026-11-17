/// W11-12 拍照通道壳层桥接测试（§11.2 W11-12、§3.3 拍照通道、§5.6㉑
/// attachments、§7.4 双供应商 fallback）。
///
/// 覆盖（宿主注入点实现，feature_capture Fake/契约口径）：
/// - 端侧压缩收口（PickerCompressedCaptureCompressor）：content_hash=
///   sha256(输出字节) 一址两用键（§5.6㉑/§5.6⑭）、mime 归一、空字节抛错
///   （压缩失败语义 → 控制器失败降级，§7.4）；
/// - 附件存储（DriftPhotoAttachmentStore，真 AttachmentsDao + 内存 Drift 库）：
///   登记即 burned（状态机/临时文件删除）、content_hash 去重复用、即焚开关
///   关闭时本机留档副本（photo_archive/，行仍 burned）；
/// - 拍照解析器工厂（缺省离线桩 + mock transport——硬规则：测试禁止真实
///   网络）：无凭据组合语义、百度 token→dish 全链路（MockClient）、Vision
///   受约束 JSON 解码与 schema 失败、双供应商组合装配。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_db/core_db.dart' as db;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimca/ai/photo_parser_factory.dart';
import 'package:slimca/photo/photo_attachment_store.dart';
import 'package:slimca/photo/photo_compressor.dart';
import 'package:slimca/settings/photo_burn_setting.dart';

/// utf8 响应构造（契约测试用）：http ≥1.5 的 `Response` 不再收 `encoding`
/// 参数、按 content-type 头推断字符集（缺省 latin1——响应体含中文即抛
/// 「Contains invalid characters」）。识别响应必含中文（菜品中文名），统一
/// 带 charset=utf-8 头构造。
http.Response utf8JsonResponse(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻既有测试口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
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

/// fixture 照片落真实临时文件（即焚「文件已删除」断言可验证）。
Future<File> _writeTempPhoto() async {
  final dir = await Directory.systemTemp.createTemp('slimca_photo_host_test');
  final file = File('${dir.path}${Platform.pathSeparator}photo.jpg');
  await file.writeAsBytes(kFakePhotoBytes, flush: true);
  return file;
}

CapturePhotoParseRequest _photoRequest() => CapturePhotoParseRequest(
      bytes: kFakePhotoBytes,
      mime: 'image/jpeg',
      inputHash: sha256.convert(kFakePhotoBytes).toString(),
    );

void main() {
  late db.AppDatabase? databaseRef;

  setUp(() async {
    databaseRef = await _tryOpenMemoryDatabase();
  });

  tearDown(() async {
    await databaseRef?.close();
  });

  group('端侧压缩收口（§3.3/§5.6㉑/§5.6⑭）', () {
    test('content_hash=sha256(输出字节)、mime 归一 image/jpeg', () async {
      const compressor = PickerCompressedCaptureCompressor();
      final compressed = await compressor.compress(CapturePhotoFile(
        bytes: kFakePhotoBytes,
        mime: 'image/png', // 来源 PNG：收口后归一 JPEG（§3.3 q80 口径）
      ));
      expect(compressed.contentHash,
          sha256.convert(kFakePhotoBytes).toString(),
          reason: '一址两用键：attachments 去重 §5.6㉑ + ai_parses 缓存 §5.6⑭');
      expect(compressed.mime, 'image/jpeg');
      expect(compressed.sizeBytes, kFakePhotoBytes.length);
    });

    test('空字节 → 抛错（压缩失败语义 → 控制器失败降级，§7.4）', () async {
      const compressor = PickerCompressedCaptureCompressor();
      await expectLater(
        compressor.compress(CapturePhotoFile(
          bytes: Uint8List(0),
          mime: 'image/jpeg',
        )),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('附件存储 DriftPhotoAttachmentStore（§5.6㉑ 登记即焚 + 去重 + 留档）',
      () {
    test('登记即 burned：行字段映射 + 临时文件删除（§3.3/§11.2 任务 3）',
        () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      final tempFile = await _writeTempPhoto();
      final store = DriftPhotoAttachmentStore(database: database);
      final attachmentId = await store.registerBurned(CaptureAttachmentDraft(
        entryId: 'entry-1',
        contentHash: sha256.convert(kFakePhotoBytes).toString(),
        kind: 'photo',
        mime: 'image/jpeg',
        sizeBytes: kFakePhotoBytes.length,
        localPath: tempFile.path,
      ));

      final row = await database
          .select(database.attachments)
          .getSingle(); // 仅一行
      expect(row.id, attachmentId);
      expect(row.entryId, 'entry-1');
      expect(row.contentHash, sha256.convert(kFakePhotoBytes).toString());
      expect(row.kind, 'photo');
      expect(row.mime, 'image/jpeg');
      expect(row.sizeBytes, kFakePhotoBytes.length);
      expect(row.status, 'burned', reason: '登记即焚（§3.3 状态机 active→burned）');
      expect(row.burnedAt, isNotNull, reason: 'burned 行保留即焚时刻（审计）');
      expect(row.blobRef, isNull, reason: 'blob_ref 恒 NULL=原图不落服务端（§5.6㉑）');
      expect(tempFile.existsSync(), isFalse,
          reason: 'markBurned 先焚本地内容再推状态（§5.6㉑）');
    });

    test('content_hash 去重：同 hash 二次登记复用行、entry_id 补指最新事件',
        () async {
      final database = databaseRef;
      if (database == null) return;

      final store = DriftPhotoAttachmentStore(database: database);
      final hash = sha256.convert(kFakePhotoBytes).toString();
      final firstId = await store.registerBurned(CaptureAttachmentDraft(
        entryId: 'entry-1',
        contentHash: hash,
        kind: 'photo',
        mime: 'image/jpeg',
        sizeBytes: kFakePhotoBytes.length,
      ));
      final secondId = await store.registerBurned(CaptureAttachmentDraft(
        entryId: 'entry-2',
        contentHash: hash,
        kind: 'photo',
        mime: 'image/jpeg',
        sizeBytes: kFakePhotoBytes.length,
      ));

      expect(secondId, firstId, reason: '同图（同压缩字节）幂等复用（§5.6㉑）');
      final rows = await database.select(database.attachments).get();
      expect(rows.length, 1, reason: '不产生重复附件行');
      expect(rows.single.entryId, 'entry-2', reason: 'entry_id 补指最新事件');
    });

    test('即焚开关关闭：登记前本机留档副本，行仍 burned、原临时文件删除',
        () async {
      final database = databaseRef;
      if (database == null) return;

      final tempFile = await _writeTempPhoto();
      final archiveDir =
          await Directory.systemTemp.createTemp('slimca_photo_archive_test');
      addTearDown(() async {
        if (await archiveDir.exists()) {
          await archiveDir.delete(recursive: true);
        }
      });
      final policy = PhotoBurnPolicy()..enabled = false; // 用户选本机留档（§3.7）
      final store = DriftPhotoAttachmentStore(
        database: database,
        burnPolicy: policy,
        archiveDirectory: archiveDir,
      );
      final hash = sha256.convert(kFakePhotoBytes).toString();
      await store.registerBurned(CaptureAttachmentDraft(
        entryId: 'entry-1',
        contentHash: hash,
        kind: 'photo',
        mime: 'image/jpeg',
        sizeBytes: kFakePhotoBytes.length,
        localPath: tempFile.path,
      ));

      final archived =
          File('${archiveDir.path}${Platform.pathSeparator}$hash.jpg');
      expect(archived.existsSync(), isTrue, reason: '焚毁前本机留档一份（§3.7）');
      expect(archived.readAsBytesSync(), kFakePhotoBytes, reason: '留档=原字节');
      expect(tempFile.existsSync(), isFalse, reason: '临时文件仍被即焚删除');
      final row = await database.select(database.attachments).getSingle();
      expect(row.status, 'burned',
          reason: '附件系统语义不变：登记即 burned、blob_ref 恒 NULL、不同步');
    });

    test('即焚开关关闭但目录装配失败（null）：无条件即焚（缺省最严，§6.1）',
        () async {
      final database = databaseRef;
      if (database == null) return;

      final policy = PhotoBurnPolicy()..enabled = false;
      final store = DriftPhotoAttachmentStore(
        database: database,
        burnPolicy: policy,
        archiveDirectory: null, // 装配失败 → 最严档
      );
      final id = await store.registerBurned(CaptureAttachmentDraft(
        entryId: 'entry-1',
        contentHash: sha256.convert(kFakePhotoBytes).toString(),
        kind: 'photo',
        mime: 'image/jpeg',
        sizeBytes: kFakePhotoBytes.length,
      ));
      expect(id, isNotEmpty);
      final row = await database.select(database.attachments).getSingle();
      expect(row.status, 'burned');
    });
  });

  group('拍照解析器工厂（§3.3 双供应商、§7.4 fallback；mock transport）', () {
    test('无凭据：primary=未配置桩 → fallback=离线确定性桩（零网络）', () async {
      final parser = createCapturePhotoParser(
        baiduApiKey: '',
        baiduSecretKey: '',
        visionApiKey: '',
      );
      expect(parser, isA<CapturePhotoParserFallback>());
      final composed = parser as CapturePhotoParserFallback;
      expect(composed.primary, isA<UnconfiguredBaiduCapturePhotoParser>());
      expect(composed.fallback, isA<OfflineStubVisionCapturePhotoParser>());

      final result = await parser.parse(_photoRequest());
      expect(result.provider, 'fake-vision');
      expect(result.title, '红烧肉套餐');
      expect(result.checkUsable(), isNull, reason: '桩产物过 §7.1 校验器');
      expect(result.lines.first.confidence, lessThan(0.5),
          reason: '低置信度红点=强制用户校核（§3.3 信任设计缺省最不信任）');
    });

    test('有凭据：primary=BaiduDishCapturePhotoParser、fallback=VisionLlm'
        'CapturePhotoParser（组合装配口径）', () {
      final composed = createCapturePhotoParser(
        baiduApiKey: 'k',
        baiduSecretKey: 's',
        visionApiKey: 'v',
        visionBaseUrl: 'https://vision.example/v1',
      );
      expect(composed, isA<CapturePhotoParserFallback>());
      final fallback = composed as CapturePhotoParserFallback;
      expect(fallback.primary, isA<BaiduDishCapturePhotoParser>());
      expect(fallback.fallback, isA<VisionLlmCapturePhotoParser>());
    });

    test('百度全链路（token → dish detect）：菜品名→结构化初值（MockClient）',
        () async {
      final requestedUrls = <Uri>[];
      final client = MockClient((request) async {
        requestedUrls.add(request.url);
        if (request.url.path.contains('/oauth/2.0/token')) {
          return utf8JsonResponse(
            jsonEncode(<String, Object?>{'access_token': 'token-1'}),
            200,
          );
        }
        return utf8JsonResponse(
          jsonEncode(<String, Object?>{
            'result': <Object?>[
              <String, Object?>{'name': '红烧肉', 'probability': 0.9},
              <String, Object?>{'name': '米饭', 'probability': 0.8},
            ],
          }),
          200,
        );
      });
      final parser = BaiduDishCapturePhotoParser(
        apiKey: 'k',
        secretKey: 's',
        client: client,
      );

      final result = await parser.parse(_photoRequest());
      expect(requestedUrls.length, 2, reason: 'token + dish 两次请求');
      expect(result.provider, 'baidu');
      expect(result.title, contains('红烧肉'));
      final calorie = result.lines.firstWhere((l) => l.isCalorie);
      expect(calorie.amountKcal, greaterThan(0), reason: '快表粗估热量');
      expect(
        calorie.items.map((i) => i.name),
        containsAll(<String>['红烧肉', '米饭']),
      );
      expect(
        calorie.items.map((i) => i.refSource),
        everyElement('baidu'),
        reason: '§5.2③ ref_source=baidu',
      );
      expect(calorie.confidence, lessThan(0.5), reason: '§7.1 红线保守置信度');
    });

    test('百度 HTTP 失败 → 结构化失败（provider 码；§7.4 交 Vision 兜底）',
        () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/oauth/2.0/token')) {
          return utf8JsonResponse(
            jsonEncode(<String, Object?>{'access_token': 'token-1'}),
            200,
          );
        }
        return utf8JsonResponse('server exploded', 500);
      });
      final parser = BaiduDishCapturePhotoParser(
        apiKey: 'k',
        secretKey: 's',
        client: client,
      );
      await expectLater(
        parser.parse(_photoRequest()),
        throwsA(isA<CaptureStructuredFailure>()),
      );
    });

    test('Vision 解析：chat/completions → 受约束 JSON → CaptureParseResult',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://vision.example/v1/chat/completions');
        expect(request.headers['Authorization'], 'Bearer vision-key');
        return utf8JsonResponse(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content': '识别结果如下：\n```json\n'
                      '{"title":"午餐","parse_notes":null,"confidence":0.6,'
                      '"lines":[{"type":"calorie","amount_kcal":600,'
                      '"confidence":0.55,"category_hint":"餐饮","items":'
                      '[{"name":"牛肉面","portion_g":400,"kcal":450,'
                      '"confidence":0.5}]},{"type":"money","amount_minor":'
                      '2500,"confidence":0.5,"category_hint":"餐饮",'
                      '"currency":"CNY","merchant":"面馆"}]}\n```',
                },
              },
            ],
          }),
          200,
        );
      });
      final parser = VisionLlmCapturePhotoParser(
        baseUrl: 'https://vision.example/v1',
        apiKey: 'vision-key',
        model: 'qwen-vl-plus',
        client: client,
      );

      final result = await parser.parse(_photoRequest());
      expect(result.provider, 'openai-vision');
      expect(result.title, '午餐', reason: '围栏/散文剥离后正确解码');
      expect(result.checkUsable(), isNull, reason: '过 §7.1 校验器');
      final money = result.lines.firstWhere((l) => l.isMoney);
      expect(money.amountMinor, 2500, reason: '分存储（§5.1）');
      expect(money.merchant, '面馆');
      final calorie = result.lines.firstWhere((l) => l.isCalorie);
      expect(calorie.items.single.name, '牛肉面');
    });

    test('Vision 非法输出 → schema 结构化失败（§7.4 坏输出不留痕）', () async {
      final client = MockClient((_) async => utf8JsonResponse(
            jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{'content': '这不是 JSON'},
                },
              ],
            }),
            200,
          ));
      final parser = VisionLlmCapturePhotoParser(
        baseUrl: 'https://vision.example/v1',
        apiKey: 'vision-key',
        model: 'qwen-vl-plus',
        client: client,
      );
      await expectLater(
        parser.parse(_photoRequest()),
        throwsA(isA<CaptureStructuredFailure>()),
      );
    });

    test('双供应商组合：百度失败 → Vision 兜底成功（§7.4 防单点）', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'aip.baidubce.com') {
          return utf8JsonResponse('boom', 500);
        }
        return utf8JsonResponse(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content': '{"title":"兜底识别","confidence":0.5,'
                      '"lines":[{"type":"calorie","amount_kcal":300,'
                      '"confidence":0.4}]}',
                },
              },
            ],
          }),
          200,
        );
      });
      final composed = createCapturePhotoParser(
        baiduApiKey: 'k',
        baiduSecretKey: 's',
        visionApiKey: 'v',
        visionBaseUrl: 'https://vision.example/v1',
        client: client,
      );
      final result = await composed.parse(_photoRequest());
      expect(result.provider, 'openai-vision', reason: '先行位失败 → 兜底接手');
      expect(result.title, '兜底识别');
    });
  });
}
