import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/clipboard_service.dart';
import '../services/password_generator.dart';

/// 密码生成器抽屉（spec：Password generator）
class GeneratorPanel extends StatefulWidget {
  const GeneratorPanel({super.key, this.onUse});

  /// 「填入当前条目」回调（编辑器内使用时提供）
  final ValueChanged<String>? onUse;

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  final PasswordGenerator _gen = PasswordGenerator();

  bool _passphraseMode = false;
  int _length = 20;
  bool _lower = true;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  bool _excludeAmbiguous = false;
  int _wordCount = 5;
  String _separator = '-';
  bool _appendDigit = false;

  String _result = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    try {
      final value = _passphraseMode
          ? _gen.generatePassphrase(
              wordCount: _wordCount,
              separator: _separator,
              appendDigit: _appendDigit,
            )
          : _gen.generate(
              length: _length,
              useLowercase: _lower,
              useUppercase: _upper,
              useDigits: _digits,
              useSymbols: _symbols,
              excludeAmbiguous: _excludeAmbiguous,
            );
      setState(() {
        _result = value;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _result = '';
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('密码生成器',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('随机')),
                  ButtonSegment(value: true, label: Text('词组')),
                ],
                selected: {_passphraseMode},
                onSelectionChanged: (s) {
                  setState(() => _passphraseMode = s.first);
                  _regenerate();
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                      const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bgInput,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _error != null
                ? Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 12))
                : SelectableText(
                    _result,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontFamily: 'monospace',
                      letterSpacing: 1,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          if (!_passphraseMode) ...[
            Row(
              children: [
                const Text('长度',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 8,
                    max: 128,
                    divisions: 120,
                    label: '$_length',
                    onChanged: (v) {
                      setState(() => _length = v.round());
                      _regenerate();
                    },
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_length',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                _toggle('小写', _lower, (v) => _lower = v),
                _toggle('大写', _upper, (v) => _upper = v),
                _toggle('数字', _digits, (v) => _digits = v),
                _toggle('符号', _symbols, (v) => _symbols = v),
                _toggle('排除易混淆 Il1O0o', _excludeAmbiguous,
                    (v) => _excludeAmbiguous = v),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const Text('词数',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _wordCount.toDouble(),
                    min: 2,
                    max: 12,
                    divisions: 10,
                    label: '$_wordCount',
                    onChanged: (v) {
                      setState(() => _wordCount = v.round());
                      _regenerate();
                    },
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_wordCount',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final sep in ['-', '.', '_', ' '])
                  ChoiceChip(
                    label: Text(sep == ' ' ? '空格' : sep),
                    selected: _separator == sep,
                    onSelected: (_) {
                      setState(() => _separator = sep);
                      _regenerate();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                _toggle('数字后缀', _appendDigit, (v) => _appendDigit = v),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent),
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新生成',
                    style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.borderStrong),
                ),
                onPressed: _result.isEmpty
                    ? null
                    : () async {
                        await ClipboardHygieneService.instance
                            .copySecret(_result);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label:
                    const Text('复制', style: TextStyle(fontSize: 13)),
              ),
              if (widget.onUse != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.borderStrong),
                  ),
                  onPressed: _result.isEmpty
                      ? null
                      : () {
                          widget.onUse!(_result);
                          Navigator.of(context).pop();
                        },
                  child: const Text('填入条目',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: value,
      selectedColor: AppTheme.accentSubtle,
      checkmarkColor: AppTheme.accent,
      visualDensity: VisualDensity.compact,
      onSelected: (v) {
        onChanged(v);
        _regenerate();
      },
    );
  }
}
