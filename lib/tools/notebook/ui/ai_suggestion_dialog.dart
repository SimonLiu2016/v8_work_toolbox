import 'package:flutter/material.dart';

import '../note_store.dart';
import '../notebook_kb_service.dart';

/// AI 整理建议的确认弹窗（阶段三）。
///
/// **AI 无直接写库权限**：本组件只收集用户勾选，落库由调用方在返回后执行
/// （design D7）。拒绝的建议被丢弃，不静默存储。
class AiSuggestionDialog extends StatefulWidget {
  const AiSuggestionDialog({
    super.key,
    required this.noteId,
    required this.noteTitle,
    this.onChanged,
  });

  final String noteId;
  final String noteTitle;
  final VoidCallback? onChanged;

  @override
  State<AiSuggestionDialog> createState() => _AiSuggestionDialogState();
}

class _AiSuggestionDialogState extends State<AiSuggestionDialog> {
  static const _titleColor = Color(0xFF0F172A);
  static const _subColor = Color(0xFF64748B);
  static const _borderColor = Color(0xFFE5E7EB);
  static const _accent = Color(0xFF3B82F6);

  bool _loadingTags = true;
  bool _loadingLinks = true;
  bool _applying = false;

  List<String> _tagSuggestions = const [];
  final Set<String> _acceptedTags = {};

  List<LinkSuggestion> _linkSuggestions = const [];
  final Set<String> _acceptedLinks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 两个请求并行，各自独立落地，避免一个慢拖住另一个的展示。
    NotebookKbService.instance.suggestTags(widget.noteId).then((tags) {
      if (mounted) setState(() { _tagSuggestions = tags; _loadingTags = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loadingTags = false);
    });

    NotebookKbService.instance.suggestLinks(widget.noteId).then((links) {
      if (mounted) setState(() { _linkSuggestions = links; _loadingLinks = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loadingLinks = false);
    });
  }

  /// 仅把用户勾选的项落库。返回 (新增标签数, 新增关联数)。
  Future<void> _apply() async {
    setState(() => _applying = true);
    var tagCount = 0;
    var linkCount = 0;
    try {
      // 标签：接受的全部写入（已存在的标签复用 id）
      if (_acceptedTags.isNotEmpty) {
        final all = await NoteStore.instance.allTags();
        final byName = {for (final t in all) t.name: t.id};
        final existingOwn = await NoteStore.instance.db.tagsForNote(widget.noteId);
        final tagIds = existingOwn.map((t) => t.id).toList();

        for (final name in _acceptedTags) {
          var id = byName[name];
          if (id == null) {
            id = await NoteStore.instance.createTag(name);
            byName[name] = id;
          }
          if (!tagIds.contains(id)) {
            tagIds.add(id);
            tagCount++;
          }
        }
        await NoteStore.instance.setNoteTags(widget.noteId, tagIds);
      }

      // 关联：接受的全部建边（createLink 忽略重复与自关联）
      for (final id in _acceptedLinks) {
        final s = _linkSuggestions.firstWhere((l) => l.noteId == id);
        await NoteStore.instance.createLink(widget.noteId, id, reason: s.reason);
        linkCount++;
      }

      widget.onChanged?.call();
      if (mounted) {
        Navigator.pop(context, (tags: tagCount, links: linkCount));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('应用建议失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nothingToShow = !_loadingTags &&
        !_loadingLinks &&
        _tagSuggestions.isEmpty &&
        _linkSuggestions.isEmpty;

    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('AI 整理建议',
          style: const TextStyle(fontSize: 15, color: _titleColor)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('针对「${widget.noteTitle}」的建议。勾选后才会写入，未勾选的会被丢弃。',
                  style: const TextStyle(fontSize: 11, color: _subColor)),
              const SizedBox(height: 14),

              // 标签建议
              _sectionHeader('建议标签', _loadingTags),
              if (_loadingTags)
                const _LoadingLine()
              else if (_tagSuggestions.isEmpty)
                const _EmptyLine('无新标签建议')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tagSuggestions.map((t) {
                    final on = _acceptedTags.contains(t);
                    return FilterChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      selected: on,
                      onSelected: (v) => setState(() {
                        v ? _acceptedTags.add(t) : _acceptedTags.remove(t);
                      }),
                      selectedColor: const Color(0xFFDBEAFE),
                      checkmarkColor: _accent,
                      side: BorderSide(color: on ? _accent : _borderColor),
                      labelStyle: TextStyle(color: on ? _accent : _titleColor),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 18),

              // 关联建议
              _sectionHeader('建议关联', _loadingLinks),
              if (_loadingLinks)
                const _LoadingLine()
              else if (_linkSuggestions.isEmpty)
                const _EmptyLine('无相关笔记')
              else
                ..._linkSuggestions.map((l) {
                  final on = _acceptedLinks.contains(l.noteId);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: on,
                    activeColor: _accent,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() {
                      v == true
                          ? _acceptedLinks.add(l.noteId)
                          : _acceptedLinks.remove(l.noteId);
                    }),
                    title: Text(l.title,
                        style: const TextStyle(fontSize: 13, color: _titleColor)),
                    subtitle: l.reason == null
                        ? null
                        : Text(l.reason!,
                            style: const TextStyle(fontSize: 11, color: _subColor)),
                  );
                }),

              if (nothingToShow)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('这条笔记暂时没有可整理的建议。',
                      style: TextStyle(fontSize: 12, color: _subColor)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: _subColor)),
        ),
        ElevatedButton(
          onPressed: (_applying || (_acceptedTags.isEmpty && _acceptedLinks.isEmpty))
              ? null
              : _apply,
          style: ElevatedButton.styleFrom(backgroundColor: _accent),
          child: _applying
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
              : Text(
                  '应用所选 (${_acceptedTags.length + _acceptedLinks.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String label, bool loading) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _titleColor)),
          if (loading) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.2)),
          ],
        ],
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('正在生成建议…',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      );
}
