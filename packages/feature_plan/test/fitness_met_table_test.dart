/// 内置 MET 表与消耗估算单元测试（§3.5、§5.5⑦）。
///
/// 纯 Dart 测试：无 IO、无平台通道（§11.1 测试约束），验证
/// `kcal = MET × 体重kg × 时长h` 与表完整性。
library;

import 'package:feature_plan/feature_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// 主断言样例（§11.1 W5-6 验收口径）：30 分钟慢跑、中强度、70kg。
FitnessActivity get _jogging => findFitnessActivity('jogging')!;

void main() {
  group('estimateKcalBurn（§3.5 kcal = MET × 体重kg × 时长h）', () {
    test('30 分钟慢跑·中强度·70kg = 245 kcal（7.0 × 70 × 0.5）', () {
      final kcal = estimateKcalBurn(
        activity: _jogging,
        intensity: FitnessIntensity.mid,
        durationS: 1800,
        weightKg: 70,
      );
      expect(kcal, 245);
    });

    test('结果为整数 kcal（§5.1 kcal 一律 INTEGER）且随体重线性放大', () {
      final at60 = estimateKcalBurn(
          activity: _jogging,
          intensity: FitnessIntensity.mid,
          durationS: 3600,
          weightKg: 60);
      final at80 = estimateKcalBurn(
          activity: _jogging,
          intensity: FitnessIntensity.mid,
          durationS: 3600,
          weightKg: 80);
      expect(at80 * 3, at60 * 4); // 同 MET 同时长：比值 = 体重比 80/60
    });

    test('MET 随强度档单调递增（全部活动 × 三档）', () {
      for (final activity in kFitnessActivities) {
        final low = activity.metFor(FitnessIntensity.low);
        final mid = activity.metFor(FitnessIntensity.mid);
        final high = activity.metFor(FitnessIntensity.high);
        expect(low < mid && mid < high, isTrue,
            reason: '${activity.id} 的 MET 档位应低<中<高（§3.5 强度档）');
      }
    });

    test('非法输入抛 ArgumentError（非正时长/体重）', () {
      expect(
        () => estimateKcalBurn(
            activity: _jogging,
            intensity: FitnessIntensity.mid,
            durationS: 0,
            weightKg: 70),
        throwsArgumentError,
      );
      expect(
        () => estimateKcalBurn(
            activity: _jogging,
            intensity: FitnessIntensity.mid,
            durationS: 1800,
            weightKg: 0),
        throwsArgumentError,
      );
    });
  });

  group('内置 MET 表完整性（§3.5 类型选择、§5.5⑦ type 枚举）', () {
    test('覆盖 strength/cardio/hiit/other 四大类且 id 唯一', () {
      final wires = kFitnessActivities.map((a) => a.type.wire).toSet();
      expect(wires, {'strength', 'cardio', 'hiit', 'other'});
      final ids = kFitnessActivities.map((a) => a.id).toSet();
      expect(ids.length, kFitnessActivities.length, reason: 'id 必须唯一');
    });

    test('fromWire 回放：合法 wire 命中、未知值抛错（§6.3 读侧校验口径）', () {
      expect(FitnessType.fromWire('cardio'), FitnessType.cardio);
      expect(FitnessIntensity.fromWire('mid'), FitnessIntensity.mid);
      expect(() => FitnessType.fromWire('unknown'),
          throwsArgumentError);
      expect(() => FitnessIntensity.fromWire('unknown'),
          throwsArgumentError);
    });

    test('未命中 id 返回 null（payload 回放防御）', () {
      expect(findFitnessActivity('not_exists'), isNull);
    });
  });
}
