/// BaiduDishAdapter 契约测试（W11-12 任务第 1 项：OpenAI 风格无关的 HTTP
/// 客户端，mock transport 契约：成功/限流/超时/坏响应 + token 流程）。
///
/// 全部经 `package:http/testing.dart` 的 MockClient 离线执行——禁止真实
/// 网络调用（任务硬规则）。
library;

import 'dart:convert';

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'photo_test_support.dart';

const String kToken = 'tok-direct-1';

BaiduDishConfig makeConfig({
  String accessToken = kToken,
  String apiKey = '',
  String secretKey = '',
  int maxAttempts = 2,
  Duration timeout = const Duration(seconds: 5),
  int maxDishes = 5,
  double defaultPortionG = 100,
}) =>
    BaiduDishConfig(
      accessToken: accessToken,
      apiKey: apiKey,
      secretKey: secretKey,
      maxAttempts: maxAttempts,
      retryBackoff: Duration.zero,
      timeout: timeout,
      maxDishes: maxDishes,
      defaultPortionG: defaultPortionG,
    );

/// 百度成功响应体（result 按置信度降序）。
String dishBody(List<Map<String, Object?>> result) =>
    jsonEncode(<String, Object?>{'log_id': 1, 'result_num': result.length, 'result': result});

const String kDishOkBody = '''
{"log_id": 88, "result_num": 2, "result": [
  {"name": "鱼香肉丝", "probability": 0.87},
  {"name": "米饭", "probability": 0.42}
]}
''';

void main() {
  group('请求形状（百度 AIP 协议，§7.1 第 6 步拍照侧联查）', () {
    test('POST dish 端点：access_token query + 表单 base64 图片 + urlencoded 头',
        () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        return utf8Response(kDishOkBody, 200);
      });
      final image = CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      );
      final adapter = BaiduDishAdapter(makeConfig(), client: client);

      await adapter.recognize(image);

      final request = captured.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://aip.baidubce.com/rest/2.0/image-classify/v2/dish'
        '?access_token=$kToken',
      );
      expect(request.headers['Content-Type'], contains('application/x-www-form-urlencoded'));
      // 表单：image=urlencode(base64(字节))，无 data: 前缀。
      final expectedB64 = base64Encode(image.bytes);
      expect(request.body,
          'image=${Uri.encodeQueryComponent(expectedB64)}');
      expect(request.body, isNot(contains('data:')));
    });

    test('成功响应 → DishCandidate（name/probability/缺省份量）', () async {
      final client =
          MockClient((request) async => utf8Response(kDishOkBody, 200));
      final adapter = BaiduDishAdapter(makeConfig(), client: client);

      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));

      expect(dishes, hasLength(2));
      expect(dishes[0].name, '鱼香肉丝');
      expect(dishes[0].confidence, 0.87);
      expect(dishes[0].grams, 100, reason: '百度无份量输出 → 基准份量初值（§3.3 滑杆）');
      expect(dishes[0].categoryHint, isNull, reason: '百度无分类输出');
      expect(dishes[1].name, '米饭');
      expect(dishes[1].confidence, 0.42);
      expect(adapter.providerId, 'baidu_dish');
      expect(adapter.modelId, 'dish_v2');
      expect(adapter.dishRefSource, FoodRefSource.baidu, reason: '§5.2③ 联查来源口径');
    });

    test('result 乱序 → 按置信度降序；maxDishes 截断', () async {
      final client = MockClient((request) async => utf8Response(
            dishBody(<Map<String, Object?>>[
              <String, Object?>{'name': '乙', 'probability': 0.3},
              <String, Object?>{'name': '甲', 'probability': 0.9},
              <String, Object?>{'name': '丙', 'probability': 0.6},
            ]),
            200,
          ));
      final adapter = BaiduDishAdapter(makeConfig(maxDishes: 2), client: client);

      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));

      expect(dishes.map((d) => d.name).toList(), ['甲', '丙']);
    });

    test('name 缺失/空白项跳过；result 缺省 → 空候选（§7.4 兜底分支）', () async {
      final client = MockClient((request) async {
        return utf8Response(
          jsonEncode(<String, Object?>{
            'log_id': 1,
            'result': <Object?>[
              <String, Object?>{'name': '  ', 'probability': 0.9},
              <String, Object?>{'probability': 0.5},
              <String, Object?>{'name': '甲', 'probability': 0.8},
            ],
          }),
          200,
        );
      });
      final adapter = BaiduDishAdapter(makeConfig(), client: client);
      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));
      expect(dishes.map((d) => d.name).toList(), ['甲']);
    });
  });

  group('鉴权（access_token 直注入 / AK+SK OAuth2 换取，§3.3 配置注入）', () {
    test('AK/SK → 先取 token（client_credentials）再识别；token 进程内缓存',
        () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/oauth/2.0/token')) {
          expect(request.url.queryParameters['grant_type'], 'client_credentials');
          expect(request.url.queryParameters['client_id'], 'ak-1');
          expect(request.url.queryParameters['client_secret'], 'sk-1');
          return utf8Response(
            jsonEncode(<String, Object?>{
              'access_token': 'tok-1',
              'expires_in': 3600,
            }),
            200,
          );
        }
        expect(request.url.queryParameters['access_token'], 'tok-1');
        return utf8Response(kDishOkBody, 200);
      });
      final adapter = BaiduDishAdapter(
        makeConfig(accessToken: '', apiKey: 'ak-1', secretKey: 'sk-1'),
        client: client,
        nowMs: () => 1763251200000,
      );

      final image = CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      );
      await adapter.recognize(image);
      await adapter.recognize(image);

      // 第二次识别命中 token 缓存：仅 1 次 oauth + 2 次 dish。
      expect(
        paths.where((p) => p.endsWith('/oauth/2.0/token')).length,
        1,
        reason: 'token 缓存至到期前 60s，未重取',
      );
      expect(paths.where((p) => p.endsWith('/dish')).length, 2);
    });

    test('token 响应缺 access_token → LlmAuthException（AK/SK 无效）', () async {
      final client = MockClient((request) async => utf8Response(
            jsonEncode(<String, Object?>{
              'error': 'invalid_client',
              'error_description': 'unknown client id',
            }),
            200,
          ));
      final adapter = BaiduDishAdapter(
        makeConfig(accessToken: '', apiKey: 'ak-1', secretKey: 'sk-bad'),
        client: client,
      );
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmAuthException>()),
      );
    });

    test('凭据全空 → ArgumentError（装配期 fail-fast）', () {
      expect(
        () => BaiduDishAdapter(
          makeConfig(accessToken: '', apiKey: '', secretKey: ''),
          client: MockClient((request) async => utf8Response('', 200)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('错误分类与重试（§7.1 错误分类；百度业务码 → LlmException 体系）', () {
    test('限流（error_code=18）→ LlmRateLimitException，重试后仍失败',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response(
          jsonEncode(<String, Object?>{
            'error_code': 18,
            'error_msg': 'Open api qps request limit reached',
          }),
          200,
        );
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmRateLimitException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
      expect(calls, 2, reason: '限流可重试（maxAttempts=2 → 2 次调用）');
    });

    test('额度耗尽（error_code=17）→ LlmQuotaException，不重试（§7.4 三级）',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response(
          jsonEncode(<String, Object?>{
            'error_code': 17,
            'error_msg': 'Open api daily request limit reached',
          }),
          200,
        );
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmQuotaException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
      expect(calls, 1, reason: '额度类不重试——重试只会继续失败');
    });

    test('token 失效（error_code=110）→ LlmAuthException，不重试', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response(
          jsonEncode(<String, Object?>{
            'error_code': 110,
            'error_msg': 'Access token expired',
          }),
          200,
        );
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmAuthException>()),
      );
      expect(calls, 1);
    });

    test('图片非法（error_code=216201）→ LlmInvalidRequestException，不重试',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response(
          jsonEncode(<String, Object?>{
            'error_code': 216201,
            'error_msg': 'image format error',
          }),
          200,
        );
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmInvalidRequestException>()),
      );
      expect(calls, 1);
    });

    test('服务端故障（error_code=2）→ LlmServerException，重试后 200 成功',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return utf8Response(
            jsonEncode(<String, Object?>{
              'error_code': 2,
              'error_msg': 'Service temporarily unavailable',
            }),
            200,
          );
        }
        return utf8Response(kDishOkBody, 200);
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));
      expect(calls, 2);
      expect(dishes, hasLength(2), reason: '瞬时故障重试后成功');
    });

    test('超时 → LlmTimeoutException（§7.4 拍照口径，注入短超时）', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return utf8Response(kDishOkBody, 200);
      });
      final adapter = BaiduDishAdapter(
        makeConfig(maxAttempts: 1, timeout: const Duration(milliseconds: 50)),
        client: client,
      );
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmTimeoutException>()),
      );
    });

    test('HTTP 500 → LlmServerException（重试）；401 → LlmAuthException',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response('boom', 500);
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmServerException>()),
      );
      expect(calls, 2);

      final client401 = MockClient((request) async => utf8Response('no', 401));
      final adapter401 =
          BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client401);
      await expectLater(
        adapter401.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmAuthException>()),
      );
    });

    test('传输层错误 → LlmNetworkException（断网 → §7.4 二级降级触发源）',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('connection refused');
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 1), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmNetworkException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
      expect(calls, 1);
    });
  });

  group('坏响应（200 但内容非法 → LlmBadResponseException，不重试）', () {
    test('响应体不是合法 JSON', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return utf8Response('<html>gateway</html>', 200);
      });
      final adapter = BaiduDishAdapter(makeConfig(maxAttempts: 2), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmBadResponseException>()),
      );
      expect(calls, 1, reason: '内容级失败不重试');
    });

    test('响应顶层不是 JSON 对象（数组）', () async {
      final client = MockClient((request) async => utf8Response('[1,2]', 200));
      final adapter = BaiduDishAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('result 非数组 → LlmBadResponseException', () async {
      final client = MockClient((request) async =>
          utf8Response(jsonEncode(<String, Object?>{'result': 'oops'}), 200));
      final adapter = BaiduDishAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.recognize(CompressedImage(
          bytes: makeJpegFixture(width: 8, height: 8),
          mime: 'image/jpeg',
          widthPx: 8,
          heightPx: 8,
        )),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('result_num=0 / result 缺省 → 空候选（不抛异常）', () async {
      final client =
          MockClient((request) async => utf8Response('{"log_id": 9}', 200));
      final adapter = BaiduDishAdapter(makeConfig(), client: client);
      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));
      expect(dishes, isEmpty);
    });
  });
}
