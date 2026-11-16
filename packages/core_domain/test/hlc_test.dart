/// HLC 混合逻辑时钟单测（§6.3、§6.7 验收自动化「HLC 单测」行）。
///
/// 覆盖四条 CI 硬闸门用例：进位边界、回拨、跳变、同 ms 并发，
/// 外加定宽性、字典序=时间序、解析往返（§6.3「单测进 CI」行）。
library;

import 'dart:math';

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

const String deviceA = '3F8A12C0B7D4';
const String deviceB = 'A1B2C3D4E5F6';

/// 构造任意合法 HLC 值。
Hlc hlc(int physical, int counter, [String device = deviceA]) =>
    Hlc(physicalMs: physical, counter: counter, deviceId: device);

/// 虚拟时钟驱动：墙钟可手动推进/回拨。
class VirtualClock {
  int nowMs;
  VirtualClock(this.nowMs);
}

HlcClock clockAt(VirtualClock v, {void Function(int)? onRollback}) =>
    HlcClock(deviceId: deviceA, wallClock: () => v.nowMs, onClockRollback: onRollback);

void main() {
  group('Hlc 定宽编码（§6.3 编码表）', () {
    test('编码总长 33 字符，三段定宽补零', () {
      final s = hlc(1700000000000, 42).format();
      expect(s, '1700000000000:000042:$deviceA');
      expect(s.length, 13 + 1 + 6 + 1 + 12);
      final parts = s.split(':');
      expect(parts[0].length, 13);
      expect(parts[1].length, 6);
      expect(parts[2].length, 12);
      // 补零定宽的意义：任何取值下三段宽度恒定——小于 10^12 的物理值
      // （2001-09 之前）毫秒段才真正出现前导零（§6.3 编码表）。
      expect(hlc(42, 7).format(), '0000000000042:000007:$deviceA');
      expect(parts[1], '000042');
    });

    test('文档示例编码复现（§6.3 示例行；宽度以编码表 13 位为准）', () {
      // §6.3 示例串 "0001700000000000:000042:…" 的物理段为 16 位，与同节
      // 编码表「13 位十进制补零」（10^13 ms ≈ 公元 33658 年）自相矛盾，
      // 判定为示例笔误：1700000000000 本身已是 13 位、无需前导零。
      // 实现以编码表为准（任务口径同为「13 位毫秒时间戳」）。
      expect(
        Hlc(physicalMs: 1700000000000, counter: 42, deviceId: '3F8A12C0B7D4')
            .format(),
        '1700000000000:000042:3F8A12C0B7D4',
      );
      // 示例串的 16 位物理段在 13 位定宽规则下必须被拒绝。
      expect(
        () => Hlc.parse('0001700000000000:000042:3F8A12C0B7D4'),
        throwsFormatException,
      );
    });

    test('deviceId 统一规范化为大写，保证编码唯一', () {
      final lower = Hlc(physicalMs: 1, counter: 0, deviceId: 'ab12cd34ef56');
      final upper = Hlc(physicalMs: 1, counter: 0, deviceId: 'AB12CD34EF56');
      expect(lower.deviceId, 'AB12CD34EF56');
      expect(lower, upper);
      expect(lower.format(), upper.format());
    });

    test('nodeIdFromUuidV7 取 UUIDv7 前 12 个 hex 字符（§6.3 device_id 行）', () {
      expect(
        Hlc.nodeIdFromUuidV7('018f3c1a-2b7d-4c0e-ab12cd34ef56-000000'),
        '018F3C1A2B7D',
      );
      expect(
        Hlc.nodeIdFromUuidV7('3f8a12c0b7d4ffff'),
        '3F8A12C0B7D4',
      );
    });

    test('边界值：物理段 13 位上限、计数器 6 位上限可编码', () {
      expect(
        Hlc(physicalMs: Hlc.maxPhysicalMs, counter: Hlc.maxCounter, deviceId: deviceA)
            .format(),
        '9999999999999:999999:$deviceA',
      );
      expect(Hlc.maxPhysicalMs.toString().length, 13);
    });

    test('越界即拒：物理超 13 位 / 计数器超 6 位 / 节点非 12 位 hex', () {
      expect(
        () => Hlc(physicalMs: 10000000000000, counter: 0, deviceId: deviceA),
        throwsArgumentError,
      );
      expect(
        () => Hlc(physicalMs: -1, counter: 0, deviceId: deviceA),
        throwsArgumentError,
      );
      expect(
        () => Hlc(physicalMs: 0, counter: 1000000, deviceId: deviceA),
        throwsArgumentError,
      );
      expect(
        () => Hlc(physicalMs: 0, counter: 0, deviceId: 'ABC'),
        throwsArgumentError,
      );
      expect(
        () => Hlc(physicalMs: 0, counter: 0, deviceId: 'ZZZZZZZZZZZZ'),
        throwsArgumentError,
      );
      expect(
        () => Hlc(physicalMs: 0, counter: 0, deviceId: 'AB12CD34EF5'),
        throwsArgumentError,
      );
    });
  });

  group('字典序 = 时间序（§6.3 定宽编码修复）', () {
    test('计数器补零修复「999 与 1000 字典序颠倒」', () {
      // 裸十进制下 "999" > "1000"；定宽后必须恢复数值序（评审必修项）。
      final a = hlc(1700000000000, 999).format();
      final b = hlc(1700000000000, 1000).format();
      expect(a.compareTo(b), isNegative);
      expect(hlc(1700000000000, 999), lessThan(hlc(1700000000000, 1000)));
    });

    test('物理段补零：1699999999999 < 1700000000000', () {
      expect(
        hlc(1699999999999, 0).format().compareTo(hlc(1700000000000, 0).format()),
        isNegative,
      );
    });

    test('同物理同计数器时，节点标识定序（字典序）', () {
      expect(
        hlc(1000, 0, 'AB12CD34EF56')
            .format()
            .compareTo(hlc(1000, 0, 'AB12CD34EF57').format()),
        isNegative,
      );
      expect(
        hlc(1000, 0, '0B12CD34EF56')
            .format()
            .compareTo(hlc(1000, 0, '3F8A12C0B7D4').format()),
        isNegative,
      );
    });

    test('抽样验证：三元组比较与字符串字典序全局一致', () {
      // 固定种子的伪随机样本——确定性失败可复现。
      // 注意：Random.nextInt 上限为 2^32，物理段用「乘 10^6 的乘法抽样」
      // 覆盖 0 ~ 9999999000000（13 位上限以内，且含前导零小值路径）。
      final rng = Random(42);
      var previous = hlc(0, 0, '000000000000');
      for (var i = 0; i < 2000; i++) {
        final next = hlc(
          rng.nextInt(10000000) * 1000000,
          rng.nextInt(Hlc.maxCounter + 1),
          deviceA,
        );
        final tupleOrder = previous.compareTo(next);
        final stringOrder = previous.format().compareTo(next.format());
        expect(
          tupleOrder.sign,
          stringOrder.sign,
          reason: '三元组序与字典序背离: '
              '${previous.format()} vs ${next.format()}',
        );
        previous = tupleOrder <= 0 ? previous : next;
      }
    });
  });

  group('解析往返（§6.3 parse/format 互转）', () {
    test('format → parse → format 恒等', () {
      // 物理段按编码表 13 位定宽（§6.3 示例串 16 位系文档笔误，见上组）。
      const samples = [
        '1700000000000:000042:3F8A12C0B7D4',
        '0000000000000:000000:000000000000',
        '9999999999999:999999:FFFFFFFFFFFF',
        '1700000000001:000001:AB12CD34EF56',
      ];
      for (final s in samples) {
        expect(Hlc.parse(s).format(), s, reason: '往返应恒等: $s');
      }
    });

    test('parse 保留三元组相等性与比较序', () {
      final a = Hlc.parse('1700000000000:000042:3F8A12C0B7D4');
      final b = hlc(1700000000000, 42, '3f8a12c0b7d4'); // 小写节点应归一
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a < b, isFalse);
      expect(a > b, isFalse);
    });

    test('一切非定宽输入拒绝解析（定宽性是编码的存在意义）', () {
      const bad = [
        '1700000000000:42:3F8A12C0B7D4', // 物理段缺补零
        '01700000000000:42:3F8A12C0B7D4', // 计数器缺补零
        '0001700000000000:000042:3F8A12C0B7D', // 节点 11 位
        '0001700000000000:000042:3F8A12C0B7D45', // 节点 13 位
        '0001700000000000-000042-3F8A12C0B7D4', // 错分隔符
        '0001700000000000:000042', // 缺节点段
        '0001700000000000:000042:3F8A12C0B7D4:extra', // 多余段
        '00017000000000:000042:3F8A12C0B7D4', // 物理段 12 位
        '00017000000000000:000042:3F8A12C0B7D4', // 物理段 14 位
        '0001700000000000:0004:3F8A12C0B7D4', // 计数器 4 位
        '0001700000000000:000042:ZZZZZZZZZZZZ', // 节点非 hex
        '', // 空串
      ];
      for (final s in bad) {
        expect(
          () => Hlc.parse(s),
          throwsFormatException,
          reason: '应拒绝: "$s"',
        );
      }
    });
  });

  group('now 语义（§6.3：物理=max(墙钟,已见)，同 ms counter++）', () {
    test('首次签发取墙钟、counter 从 0 起', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      final first = c.now();
      expect(first.physicalMs, 1700000000000);
      expect(first.counter, 0);
      expect(first.deviceId, deviceA);
    });

    test('同一毫秒连发：counter 单调自增', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      final a = c.now();
      final b = c.now();
      final d = c.now();
      expect(b.counter, a.counter + 1);
      expect(d.counter, b.counter + 1);
      expect(a < b, isTrue);
      expect(b < d, isTrue);
    });

    test('墙钟前进：切到新毫秒、counter 归零', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      c.now();
      v.nowMs = 1700000000001;
      final next = c.now();
      expect(next.physicalMs, 1700000000001);
      expect(next.counter, 0);
    });
  });

  group('recv 语义（§6.3：跳变跟上 / 沿用本地 / 同 ms 并发）', () {
    test('远端更新：跳变跟上，counter=远端+1', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      c.now();
      final merged = c.recv(hlc(1700000009999, 5, deviceB));
      expect(merged.physicalMs, 1700000009999);
      expect(merged.counter, 6);
    });

    test('远端更旧：沿用本地物理并 counter++（本地序不受扰动）', () {
      final v = VirtualClock(1700000000005);
      final c = clockAt(v);
      final local = c.now();
      final merged = c.recv(hlc(1700000000000, 9, deviceB));
      expect(merged.physicalMs, local.physicalMs);
      expect(merged.counter, local.counter + 1);
    });

    test('同 ms 并发（§6.7 四用例之一）：双方 counter 取大 +1', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      c.now(); // 本地 (T, 0)
      final merged = c.recv(hlc(1700000000000, 7, deviceB));
      expect(merged.physicalMs, 1700000000000);
      expect(merged.counter, 8); // max(0, 7) + 1
    });

    test('双端离线各自连发后合并：无回退（§6.7 双端离线新建）', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      c.now();
      c.now();
      c.now(); // 本地 (T, 2)
      final merged = c.recv(hlc(1700000000000, 10, deviceB));
      expect(merged.counter, 11); // max(2, 10) + 1
      final after = c.now();
      expect(after.counter, 12); // 合并后本地继续单调
    });

    test('墙钟远落后于远端时：跟随远端且本地事件不再回退', () {
      final v = VirtualClock(1699999999999);
      final c = clockAt(v);
      c.now();
      final jumped = c.recv(hlc(1700000000000, 2, deviceB));
      expect(jumped.physicalMs, 1700000000000);
      final after = c.now(); // 墙钟仍落后，应沿用已见物理
      expect(after.physicalMs, 1700000000000);
      expect(after.counter, jumped.counter + 1);
    });

    test('recv 自身回显安全：仅单调前进', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      final issued = c.now();
      final echoed = c.recv(issued);
      expect(echoed > issued, isTrue);
      expect(echoed.physicalMs, issued.physicalMs);
    });

    test('recvEncoded：编码形式可直接合并（解析往返复用）', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      final merged = c.recvEncoded('1700000000500:000003:$deviceB');
      expect(merged.physicalMs, 1700000000500);
      expect(merged.counter, 4);
    });
  });

  group('计数器进位（§6.3 counter 行：单 ms 上限 999,999）', () {
    test('合并值达到计数器上限时立即进位：物理 +1、counter 归零', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      c.now(); // 本地 (T, 0)
      // 远端已把本毫秒计数器推到 999,999；合并值必须严格大于远端，
      // 而 max(0,999999)+1 = 1,000,000 超出 6 位定宽 → 进位（§6.3）。
      final merged = c.recv(hlc(1700000000000, Hlc.maxCounter, deviceB));
      expect(merged.physicalMs, 1700000000001);
      expect(merged.counter, 0);
      final after = c.now(); // 墙钟仍在 T：沿用已见物理继续自增
      expect(after.physicalMs, 1700000000001);
      expect(after.counter, 1);
    });

    test('进位边界保持字典序：…999999 < 物理+1:000000（§6.3 进位边界用例）', () {
      final boundary = hlc(1700000000000, Hlc.maxCounter);
      final carried = hlc(1700000000001, 0);
      expect(boundary.format().compareTo(carried.format()), isNegative);
      expect(boundary < carried, isTrue);
    });
  });

  group('时钟回拨（§6.3：物理取 max 不影响全序，>60s 告警）', () {
    test('小幅回拨（≤60s）：不告警，全序不受影响', () {
      final v = VirtualClock(1700000000000);
      var alertMs = 0;
      final c = clockAt(v, onRollback: (lag) => alertMs = lag);
      final a = c.now();
      v.nowMs = a.physicalMs - 59000; // 回拨 59 秒
      final b = c.now();
      expect(b.physicalMs, a.physicalMs); // 沿用已见最大
      expect(b.counter, a.counter + 1);
      expect(b > a, isTrue);
      expect(c.activeRollbackLagMs, isNull);
      expect(alertMs, 0);
    });

    test('大幅回拨（>60s）：触发一次告警，物理仍取 max（§6.3 回拨行）', () {
      final v = VirtualClock(1700000000000);
      final alerts = <int>[];
      final c = clockAt(v, onRollback: alerts.add);
      final a = c.now();
      v.nowMs = a.physicalMs - 61000; // 回拨 61 秒
      final b = c.now();
      expect(b.physicalMs, a.physicalMs);
      expect(alerts.length, 1);
      expect(alerts.single, 61000);
      expect(c.activeRollbackLagMs, 61000);
      // 同一回拨事件内不重复告警（边沿触发）。
      c.now();
      expect(alerts.length, 1);
      // 墙钟追平后复位。
      v.nowMs = a.physicalMs + 1;
      c.now();
      expect(c.activeRollbackLagMs, isNull);
    });

    test('回拨期间字典序与数值序持续一致（§6.7 回拨用例）', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v, onRollback: (_) {});
      final issued = <Hlc>[c.now()];
      v.nowMs = issued.first.physicalMs - 120000; // 大幅回拨
      issued
        ..add(c.now())
        ..add(c.now())
        ..add(c.now());
      for (var i = 1; i < issued.length; i++) {
        expect(issued[i] > issued[i - 1], isTrue);
        expect(
          issued[i - 1].format().compareTo(issued[i].format()),
          isNegative,
        );
      }
    });

    test('远端跳变导致的墙钟落后不算回拨（不误报）', () {
      final v = VirtualClock(1700000000000);
      final alerts = <int>[];
      final c = clockAt(v, onRollback: alerts.add);
      c.now();
      c.recv(hlc(1700000000100, 0, deviceB)); // 跳到未来 100ms
      c.now();
      expect(alerts, isEmpty);
    });
  });

  group('长会话全序不变量', () {
    test('now/recv 交错 1000 次：签发序列严格单调且编码序一致', () {
      final v = VirtualClock(1700000000000);
      final c = clockAt(v);
      final rng = Random(7);
      Hlc? previous;
      for (var i = 0; i < 1000; i++) {
        final next = rng.nextBool()
            ? c.now()
            : c.recv(hlc(
                1700000000000 + rng.nextInt(50),
                rng.nextInt(1000),
                deviceB,
              ));
        if (previous != null) {
          // 注意：recv 的返回值是「合并后本节点使用的下一时间戳」，
          // 相对本地此前签发值也必须严格前进（全序不变量）。
          expect(next > previous, isTrue,
              reason: '非单调: ${previous.format()} -> ${next.format()}');
          expect(previous.format().compareTo(next.format()), isNegative);
        }
        previous = next;
      }
    });
  });

  group('公共约定冒烟（§5.1）', () {
    test('日历日校验与格式化', () {
      expect(isValidCalendarDay('2026-11-16'), isTrue);
      expect(isValidCalendarDay('2026-1-16'), isFalse);
      expect(
        formatCalendarDay(DateTime(2026, 11, 16)),
        '2026-11-16',
      );
      expect(() => validateCalendarDay('20261116'), throwsArgumentError);
    });
  });
}
