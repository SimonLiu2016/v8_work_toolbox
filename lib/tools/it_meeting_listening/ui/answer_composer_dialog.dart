/// 回答编排对话框：选一段话作为提问，产出可插入的英文回答。
///
/// 两条路径共用同一个"插入"按钮（产物同形：一段英文 + 可选中文原文）：
///
/// ```
/// ① 让 AI 回答    → 生成英文草稿
/// ② 我写中文      → 译成英文，中文原文并存
/// ```
///
/// **英文始终可编辑**：模型给的是草稿，用户要照着念出去。允许改是必须的，
/// 否则一句用词不合口味就得整段重生成。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/real_meeting_models.dart';
import '../services/answer_generator.dart';

/// 回答编排方式。
enum AnswerMode { ai, chinese }

/// 回答编排对话框。
class AnswerComposerDialog extends StatefulWidget {
  final AnswerGenerator generator;
  final RealMeeting meeting;
  final int questionTurnIndex;
  final String questionSpeaker;
  final String questionText;

  /// 插入回调：返回非 null 表示失败原因。
  final Future<String?> Function(String textEn, String textZh) onInsert;

  const AnswerComposerDialog({
    super.key,
    required this.generator,
    required this.meeting,
    required this.questionTurnIndex,
    required this.questionSpeaker,
    required this.questionText,
    required this.onInsert,
  });

  @override
  State<AnswerComposerDialog> createState() => _AnswerComposerDialogState();
}

class _AnswerComposerDialogState extends State<AnswerComposerDialog> {
  AnswerMode _mode = AnswerMode.ai;
  final _englishCtrl = TextEditingController();
  final _chineseCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _note;
  bool _inserting = false;

  @override
  void dispose() {
    _englishCtrl.dispose();
    _chineseCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      final draft = _mode == AnswerMode.ai
          ? await widget.generator.suggestAnswer(
              meeting: widget.meeting,
              questionTurnIndex: widget.questionTurnIndex,
            )
          : await widget.generator.translateAnswer(
              meeting: widget.meeting,
              questionTurnIndex: widget.questionTurnIndex,
              chinese: _chineseCtrl.text,
            );
      if (!mounted) return;
      setState(() {
        _englishCtrl.text = draft.textEn;
        _note = draft.truncated ? '文稿较长，只送入了问题之前最近的一段上下文' : null;
      });
    } on AnswerGenerationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _insert() async {
    final text = _englishCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '回答为空');
      return;
    }
    setState(() {
      _inserting = true;
      _error = null;
    });
    try {
      final failure = await widget.onInsert(
        text,
        _mode == AnswerMode.chinese ? _chineseCtrl.text.trim() : '',
      );
      if (!mounted) return;
      if (failure != null) {
        setState(() => _error = failure);
      } else {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _inserting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? context.bgCard : AppTheme.lightBgCard;
    final textPrimary = isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    return Dialog(
      backgroundColor: bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('回答这个问题',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${widget.questionSpeaker}: ${widget.questionText}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: textPrimary)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _modeChip('让 AI 回答', AnswerMode.ai, accent, textSecondary),
                  const SizedBox(width: 6),
                  _modeChip('我写中文再译', AnswerMode.chinese, accent, textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              if (_mode == AnswerMode.chinese) ...[
                TextField(
                  controller: _chineseCtrl,
                  maxLines: 3,
                  style: TextStyle(fontSize: 12, color: textPrimary),
                  decoration: const InputDecoration(
                    labelText: '中文回答',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: _busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_mode == AnswerMode.ai ? '生成建议回答' : '译成英文'),
                  ),
                ),
              ),
              if (_note != null) ...[
                const SizedBox(height: 6),
                Text(_note!, style: TextStyle(fontSize: 11, color: textSecondary)),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _englishCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: const InputDecoration(
                    labelText: '英文回答（可修改后插入）',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: TextStyle(fontSize: 11, color: accent)),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _inserting ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _inserting ? null : _insert,
                    icon: const Icon(Icons.add_comment_outlined, size: 16),
                    label: const Text('插入到文稿'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(
      String label, AnswerMode mode, Color accent, Color textSecondary) {
    final selected = _mode == mode;
    return InkWell(
      onTap: _busy ? null : () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: selected ? accent : textSecondary),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: selected ? accent : textSecondary)),
      ),
    );
  }
}
