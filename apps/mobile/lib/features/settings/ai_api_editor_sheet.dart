/// AI 服务配置编辑面板（§4.3 设置抽屉形态、§5.6⑲ settings 本地件）。
///
/// 用户拍板（2026-11-18）：AI apikey 改为用户自设、默认空——空 key 时解析
/// 走离线确定性桩（HeuristicFakeLlmAdapter），配置后走 OpenAI 兼容端点。
/// 面板承载三字段（API Base / API Key / 模型名）：key 输入框 obscure（凭据
/// 不明文回显）；保存写 settings 表（本地件、永不同步——key 只存本机，§3.7）
/// 并写回 aiApiConfigProvider（captureParserProvider 响应式重装，下一次
/// 解析即用新配置）。
library;

import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../settings/ai_api_setting.dart';

/// AI 服务配置编辑面板测试锚点。
const Key aiApiEditorSheetKey = Key('ai_api_editor_sheet');
const Key aiApiBaseFieldKey = Key('ai_api_base_field');
const Key aiApiKeyFieldKey = Key('ai_api_key_field');
const Key aiApiModelFieldKey = Key('ai_api_model_field');
const Key aiApiSaveButtonKey = Key('ai_api_save_button');

/// 唤起 AI 服务配置编辑面板（弹簧抽屉，§9.3#3）。
Future<void> showAiApiEditorSheet(BuildContext context) {
  return showSlimcaSpringSheet<void>(
    context: context,
    motion: MotionConfig.of(context),
    builder: (_) => const _AiApiEditorSheet(),
  );
}

class _AiApiEditorSheet extends ConsumerStatefulWidget {
  const _AiApiEditorSheet();

  @override
  ConsumerState<_AiApiEditorSheet> createState() => _AiApiEditorSheetState();
}

class _AiApiEditorSheetState extends ConsumerState<_AiApiEditorSheet> {
  late String _base;
  late String _key;
  late String _model;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final (config, _) = ref.read(aiApiConfigProvider);
    _base = config.baseUrl;
    _key = config.apiKey;
    _model = config.model;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final config = AiApiConfig(
      baseUrl: _base.trim(),
      apiKey: _key.trim(),
      model: _model.trim(),
    );
    try {
      final db = ref.read(appDatabaseProvider);
      await saveAiApiConfig(db, config: config);
      // 运行期写回：captureParserProvider 响应式重装（下一次解析生效）。
      ref.read(aiApiConfigProvider.notifier).save((config, true));
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试（本地设置写入）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      key: aiApiEditorSheetKey,
      padding: EdgeInsets.fromLTRB(
        context.spacing.space250,
        context.spacing.space100,
        context.spacing.space250,
        context.spacing.space250,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI 服务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: tokens.onSurface,
            ),
          ),
          SizedBox(height: context.spacing.space100),
          Text(
            '自备 OpenAI 兼容端点与 API Key（默认空 = 离线解析桩；凭据只存'
            '本机 settings，永不上传同步，§3.7）',
            style: TextStyle(
              fontSize: 12,
              color: tokens.onSurfaceMuted,
            ),
          ),
          SizedBox(height: context.spacing.space200),
          CaptureTextField(
            key: aiApiBaseFieldKey,
            initial: _base,
            hint: 'API Base URL（如 https://api.openai.com/v1）',
            onChanged: (v) => _base = v,
          ),
          SizedBox(height: context.spacing.space150),
          CaptureTextField(
            key: aiApiKeyFieldKey,
            initial: _key,
            hint: 'API Key（sk-…；默认空 = 离线解析桩）',
            obscureText: true,
            onChanged: (v) => _key = v,
          ),
          SizedBox(height: context.spacing.space150),
          CaptureTextField(
            key: aiApiModelFieldKey,
            initial: _model,
            hint: '模型名（缺省 gpt-4o-mini）',
            onChanged: (v) => _model = v,
          ),
          SizedBox(height: context.spacing.space250),
          FilledButton(
            key: aiApiSaveButtonKey,
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.primary,
              foregroundColor: tokens.onPrimary,
              minimumSize: Size.fromHeight(context.sizes.rowSingleLine),
              shape: const StadiumBorder(), // §7.1 按钮胶囊
            ),
            child: Text(
              _saving ? '保存中…' : '保存',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
