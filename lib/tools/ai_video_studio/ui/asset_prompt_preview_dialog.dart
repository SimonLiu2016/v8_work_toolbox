import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';

/// 提示词预览与编辑返回结果。
class AssetPromptPreviewResult {
  final String positivePrompt;
  final String negativePrompt;

  const AssetPromptPreviewResult({
    required this.positivePrompt,
    required this.negativePrompt,
  });
}

/// 资产生图提示词组件层级说明。
class PromptComponentLayer {
  final String label;
  final String? content;
  final Color color;

  const PromptComponentLayer({
    required this.label,
    required this.content,
    required this.color,
  });
}

/// 素材生图提示词预览与实时微调弹窗。
///
/// 支持在正式向生图模型发起请求前，查看完整拼接的正向与负向 Prompt，
/// 明确知晓系统隐式注入了哪些组件，并允许一次性微调后提交生成。
class AssetPromptPreviewDialog extends StatefulWidget {
  final String initialPositivePrompt;
  final String initialNegativePrompt;
  final String title;
  final String? assetName;
  final List<PromptComponentLayer> componentLayers;

  const AssetPromptPreviewDialog({
    super.key,
    required this.initialPositivePrompt,
    required this.initialNegativePrompt,
    this.title = '生图提示词预览与微调',
    this.assetName,
    this.componentLayers = const [],
  });

  /// 弹出预览编辑弹窗。
  /// 返回用户最终确认的 [AssetPromptPreviewResult]，若取消则返回 null。
  static Future<AssetPromptPreviewResult?> show(
    BuildContext context, {
    required String initialPositivePrompt,
    required String initialNegativePrompt,
    String title = '生图提示词预览与微调',
    String? assetName,
    List<PromptComponentLayer> componentLayers = const [],
  }) {
    return showDialog<AssetPromptPreviewResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AssetPromptPreviewDialog(
        initialPositivePrompt: initialPositivePrompt,
        initialNegativePrompt: initialNegativePrompt,
        title: title,
        assetName: assetName,
        componentLayers: componentLayers,
      ),
    );
  }

  @override
  State<AssetPromptPreviewDialog> createState() =>
      _AssetPromptPreviewDialogState();
}

class _AssetPromptPreviewDialogState extends State<AssetPromptPreviewDialog> {
  late final TextEditingController _posCtrl;
  late final TextEditingController _negCtrl;
  bool _showComponentDetails = false;

  @override
  void initState() {
    super.initState();
    _posCtrl = TextEditingController(text: widget.initialPositivePrompt);
    _negCtrl = TextEditingController(text: widget.initialNegativePrompt);
    _posCtrl.addListener(_onTextChanged);
    _negCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _posCtrl.removeListener(_onTextChanged);
    _negCtrl.removeListener(_onTextChanged);
    _posCtrl.dispose();
    _negCtrl.dispose();
    super.dispose();
  }

  void _resetToDefault() {
    setState(() {
      _posCtrl.text = widget.initialPositivePrompt;
      _negCtrl.text = widget.initialNegativePrompt;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已还原为系统默认组装的 Prompt'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed
        .split(RegExp(r'[\s,，、；;|\n]+'))
        .where((w) => w.isNotEmpty)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final posWords = _countWords(_posCtrl.text);
    final negWords = _countWords(_negCtrl.text);

    return AlertDialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: context.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.assetName != null && widget.assetName!.isNotEmpty)
                  Text(
                    '当前目标：${widget.assetName}',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 提示词组装层级概览
              if (widget.componentLayers.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _showComponentDetails = !_showComponentDetails),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '提示词组装包含 ${widget.componentLayers.length} 个注入层：',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: widget.componentLayers
                                .map(
                                  (layer) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: layer.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: layer.color.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      layer.label,
                                      style: TextStyle(color: layer.color, fontSize: 11),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        Icon(
                          _showComponentDetails ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: context.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showComponentDetails)
                  Container(
                    margin: const EdgeInsets.only(top: 6, bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.componentLayers
                          .map(
                            (l) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      '${l.label}：',
                                      style: TextStyle(
                                        color: l.color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      l.content?.isNotEmpty == true ? l.content! : '（无）',
                                      style: TextStyle(color: context.textPrimary, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 10),
              ],

              // 正向 Prompt 编辑区
              Row(
                children: [
                  const Text('正向 Prompt (最终调用文本)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Text('($posWords 词 / ${_posCtrl.text.length} 字符)', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    tooltip: '复制正向 Prompt',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _posCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制正向 Prompt'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _posCtrl,
                maxLines: 6,
                style: const TextStyle(fontSize: 12, height: 1.4),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.bgInput,
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: context.borderSubtle)),
                ),
              ),
              const SizedBox(height: 14),

              // 负向 Prompt 编辑区
              Row(
                children: [
                  const Text('负向 Prompt (Negative)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Text('($negWords 词 / ${_negCtrl.text.length} 字符)', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    tooltip: '复制负向 Prompt',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _negCtrl.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制负向 Prompt'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _negCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 12, height: 1.4),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.bgInput,
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: context.borderSubtle)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '提示：在上方直接修改只对本次生图生效。如需永久替换系统前导/透视约束词，请在资产卡底部的「系统提示词组件」中设置持久化覆盖。',
                style: TextStyle(color: context.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _resetToDefault,
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('还原为默认组装'),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(
                    AssetPromptPreviewResult(
                      positivePrompt: _posCtrl.text.trim(),
                      negativePrompt: _negCtrl.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('以此 Prompt 生成'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
