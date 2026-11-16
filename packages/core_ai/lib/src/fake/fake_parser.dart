/// 确定性脚本化解析器假实现（测试/预览专用——绕过整条管线直接返回
/// 预置结果；feature 层控制器测试用它隔离网络与缓存，任务硬规则：
/// 测试一律注入 Fake/Mock，禁止真实网络调用）。
library;

import '../parse/ai_parser.dart';
import '../parse/parse_models.dart';

class FakeAiParser implements AiParser {
  /// 脚本项：[ParseResult]（返回）或 `Exception`/`Error`（抛出）。
  ///
  /// 脚本耗尽即抛 StateError（脚本与预期调用次数不符应显式暴露）。
  FakeAiParser(List<Object> script)
      : _script = List<Object>.unmodifiable(script);

  final List<Object> _script;
  int _cursor = 0;

  /// 收到的解析输入日志（按调用序；断言上下文/单边模式传递用）。
  final List<ParseInput> inputs = <ParseInput>[];

  @override
  Future<ParseResult> parse(ParseInput input) async {
    inputs.add(input);
    if (_cursor >= _script.length) {
      throw StateError(
        'FakeAiParser 脚本耗尽（第 ${_cursor + 1} 次 parse，脚本共 '
        '${_script.length} 项）',
      );
    }
    final item = _script[_cursor++];
    if (item is ParseResult) {
      return item;
    }
    if (item is Exception || item is Error) {
      throw item;
    }
    throw StateError('FakeAiParser 脚本项必须是 ParseResult 或异常，'
        '实际 ${item.runtimeType}');
  }

  /// 最近一次收到的输入（便捷断言）。
  ParseInput? get lastInput => inputs.isEmpty ? null : inputs.last;
}
