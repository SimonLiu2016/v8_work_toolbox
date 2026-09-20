import 'package:flutter/material.dart';

import '../note_database.dart';
import '../note_store.dart';
import 'ai_suggestion_dialog.dart';
import 'notebook_light_scope.dart';

/// 元数据栏的「AI 整理建议」chip（阶段三，台账化改造）。
///
/// 点击打开 [AiSuggestionDialog]；勾选过的建议才会落库。
class AiTidyChip extends StatefulWidget {
  const AiTidyChip({super.key, required this.note, this.onChanged});

  final Note note;
  final VoidCallback? onChanged;

  @override
  State<AiTidyChip> createState() => _AiTidyChipState();
}

class _AiTidyChipState extends State<AiTidyChip> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final result = await showDialog<({int links, int tags})>(
        context: context,
        builder: (_) => AiSuggestionDialog(
          noteId: widget.note.id,
          noteTitle: widget.note.title,
          onChanged: widget.onChanged,
        ),
      );
      if (result != null && mounted) {
        widget.onChanged?.call();
        final msg = StringBuffer('已应用');
        if (result.tags > 0) msg.write(' ${result.tags} 个标签');
        if (result.links > 0) msg.write(' ${result.links} 条关联');
        if (result.tags == 0 && result.links == 0) msg.write(' 0 项');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MetaChip(
      icon: _busy ? null : Icons.auto_awesome,
      label: '整理',
      onTap: _busy ? null : _open,
      busy: _busy,
      tooltip: 'AI 整理建议：标签与关联',
    );
  }
}

/// 关联笔记列表弹窗（元数据栏关联 chip 的载体）。
///
/// 点击条目跳转到对应笔记，右侧可移除关联。无关联时调用方不渲染 chip。
Future<void> showRelatedNotesDialog(
  BuildContext context, {
  required Note note,
  void Function(String noteId)? onOpenNote,
  VoidCallback? onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => NotebookLightScope(
      child: AlertDialog(
        backgroundColor: NotebookLightScope.surface,
        title: const Text(
          '关联笔记',
          style: TextStyle(fontSize: 15, color: NotebookLightScope.textPrimary),
        ),
        content: _RelatedNotesList(
          note: note,
          onOpenNote: onOpenNote,
          onChanged: onChanged,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '完成',
              style: TextStyle(color: NotebookLightScope.accent),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RelatedNotesList extends StatefulWidget {
  const _RelatedNotesList({
    required this.note,
    this.onOpenNote,
    this.onChanged,
  });

  final Note note;
  final void Function(String noteId)? onOpenNote;
  final VoidCallback? onChanged;

  @override
  State<_RelatedNotesList> createState() => _RelatedNotesListState();
}

class _RelatedNotesListState extends State<_RelatedNotesList> {
  static const _titleColor = NotebookLightScope.textPrimary;
  static const _subColor = NotebookLightScope.textSecondary;

  List<RelatedNote> _related = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await NoteStore.instance.relatedNotes(widget.note.id);
      if (mounted)
        setState(() {
          _related = list;
          _loaded = true;
        });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _removeLink(RelatedNote r) async {
    // 关联是有向的：仅当当前笔记是 source 时 outgoing 才为 true。删除时按实际
    // 存储方向删——若不是 source，则反向删。
    await NoteStore.instance.deleteLink(
      r.outgoing ? widget.note.id : r.noteId,
      r.outgoing ? r.noteId : widget.note.id,
    );
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        width: 420,
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_related.isEmpty) {
      return const SizedBox(
        width: 420,
        child: Text(
          '这条笔记还没有关联。可点「整理」让 AI 推荐相关笔记。',
          style: TextStyle(fontSize: 12, color: _subColor),
        ),
      );
    }

    return SizedBox(
      width: 420,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _related.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) => _row(_related[i]),
        ),
      ),
    );
  }

  Widget _row(RelatedNote r) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        widget.onOpenNote?.call(r.noteId);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 13, color: _subColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: const TextStyle(fontSize: 12, color: _titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (r.reason != null && r.reason!.isNotEmpty)
                    Text(
                      r.reason!,
                      style: const TextStyle(fontSize: 10, color: _subColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 13, color: _subColor),
              tooltip: '移除关联',
              onPressed: () => _removeLink(r),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }
}

/// 元数据栏共用的紧凑 chip。
///
/// 与 `[+ 标签]` 同风格：浅底细边、小字号、强调色文字。
class MetaChip extends StatelessWidget {
  const MetaChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.busy = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: NotebookLightScope.surface,
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.2),
                )
              else if (icon != null)
                Icon(icon, size: 11, color: NotebookLightScope.accent),
              const SizedBox(width: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: NotebookLightScope.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
