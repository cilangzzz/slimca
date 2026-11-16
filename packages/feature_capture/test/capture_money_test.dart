/// 金额文本工具的单元测试（§3.4「金额整数分存储」、§5.1）。
///
/// 核心断言：元文本 ↔ 分互转全程字符串/整数运算，无浮点参与。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:feature_capture/feature_capture.dart';

void main() {
  group('CaptureMoney.toMinorUnits（元文本 → 分，§5.1）', () {
    test('常规金额', () {
      expect(CaptureMoney.toMinorUnits('18.50'), 1850);
      expect(CaptureMoney.toMinorUnits('18.5'), 1850);
      expect(CaptureMoney.toMinorUnits('18'), 1800);
      expect(CaptureMoney.toMinorUnits('0'), 0);
      expect(CaptureMoney.toMinorUnits('0.05'), 5);
      expect(CaptureMoney.toMinorUnits('999999999'), 99999999900);
      expect(CaptureMoney.toMinorUnits('999999999.99'), 99999999999);
    });

    test('非法/空输入返回 null', () {
      expect(CaptureMoney.toMinorUnits(''), isNull);
      expect(CaptureMoney.toMinorUnits('.'), isNull);
      expect(CaptureMoney.toMinorUnits('18.123'), isNull);
      expect(CaptureMoney.toMinorUnits('1234567890'), isNull); // 超 9 位整数
      expect(CaptureMoney.toMinorUnits('12a'), isNull);
      expect(CaptureMoney.toMinorUnits('-5'), isNull);
      expect(CaptureMoney.toMinorUnits('1..2'), isNull);
    });

    test('浮点精度对照：字符串分转换无 0.1+0.2 类误差', () {
      // double 19.99 * 100 = 1998.9999…，字符串转换恒等于 1999。
      expect(CaptureMoney.toMinorUnits('19.99'), 1999);
      expect(CaptureMoney.toMinorUnits('0.29'), 29);
      expect(CaptureMoney.toMinorUnits('145.71'), 14571);
    });
  });

  group('CaptureMoney.fromMinorUnits（分 → 元文本，编辑回填）', () {
    test('常规', () {
      expect(CaptureMoney.fromMinorUnits(1850), '18.50');
      expect(CaptureMoney.fromMinorUnits(5), '0.05');
      expect(CaptureMoney.fromMinorUnits(1800), '18.00');
      expect(CaptureMoney.fromMinorUnits(99999999999), '999999999.99');
    });

    test('roundtrip：fromMinorUnits → toMinorUnits 恒等', () {
      for (final minor in <int>[1, 5, 50, 1850, 999999, 1234567]) {
        expect(CaptureMoney.toMinorUnits(CaptureMoney.fromMinorUnits(minor)),
            minor);
      }
    });
  });

  group('CaptureMoney 键盘步进（§3.3 数字键盘）', () {
    test('appendDigit：前导 0 替换与整数段上限', () {
      expect(CaptureMoney.appendDigit('', '5'), '5');
      expect(CaptureMoney.appendDigit('0', '5'), '5');
      expect(CaptureMoney.appendDigit('5', '5'), '55');
      expect(CaptureMoney.appendDigit('18', '5'), '185');
      // 9 位整数封顶
      expect(CaptureMoney.appendDigit('999999999', '9'), '999999999');
      // 小数段最多 2 位
      expect(CaptureMoney.appendDigit('18.5', '0'), '18.50');
      expect(CaptureMoney.appendDigit('18.50', '5'), '18.50');
    });

    test('appendDot：空输入 → "0."；重复小数点无效', () {
      expect(CaptureMoney.appendDot(''), '0.');
      expect(CaptureMoney.appendDot('18'), '18.');
      expect(CaptureMoney.appendDot('18.'), '18.');
      expect(CaptureMoney.appendDot('18.50'), '18.50');
    });

    test('backspace：含小数点的退格与空输入', () {
      expect(CaptureMoney.backspace('18.50'), '18.5');
      expect(CaptureMoney.backspace('18.5'), '18.');
      expect(CaptureMoney.backspace('18.'), '18');
      expect(CaptureMoney.backspace('18'), '1');
      expect(CaptureMoney.backspace('1'), '');
      expect(CaptureMoney.backspace(''), '');
    });

    test('键盘组合流：1 8 . 5 0 → "18.50" → 分 1850（§5.1）', () {
      var text = '';
      text = CaptureMoney.appendDigit(text, '1');
      text = CaptureMoney.appendDigit(text, '8');
      text = CaptureMoney.appendDot(text);
      text = CaptureMoney.appendDigit(text, '5');
      text = CaptureMoney.appendDigit(text, '0');
      expect(text, '18.50');
      expect(CaptureMoney.toMinorUnits(text), 1850);
    });

    test('displayText：空输入占位 0.00', () {
      expect(CaptureMoney.displayText(''), '0.00');
      expect(CaptureMoney.displayText('18.50'), '18.50');
    });
  });
}
