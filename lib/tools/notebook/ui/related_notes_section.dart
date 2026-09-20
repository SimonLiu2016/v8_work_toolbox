import 'package:flutter/material.dart';

import '../note_database.dart';
import '../note_store.dart';
import 'ai_suggestion_dialog.dart';

/// 笔记详情中的「关联与整理」区（阶段三）。
///
/// - 展示已建立的关联笔记（标题 + 理由），点击跳转
/// - 提供「AI 整理建议」入口，打开确认弹窗
/// - 无关联时不显示占位（design：不留空区）
class RelatedNotesSection extends StatefulWidget {
  const RelatedNotesSection({
    super.key,
    required this.note,
    required this.onOpenNote,
    required this.onChanged,
  });

  final Note note;
  final void Function(String noteId) onOpenNote;

  /// 关联或标签变更后通知外部刷新。
  final VoidCallback onChanged;

  @override
  State<RelatedNotesSection> createState() => _RelatedNotesSectionState();
}

class _RelatedNotesSectionState extends State<RelatedNotesSection> {
  static const _titleColor = Color(0xFF0F172A);
  static const _subColor = Color(0xFF64748B);
  static const _borderColor = Color(0xFFE5E7EB);
  static const _accent = Color(0xFF3B82F6);

  List<RelatedNote> _related = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RelatedNotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) _load();
  }

  Future<void> _load() async {
    try {
      final list = await NoteStore.instance.relatedNotes(widget.note.id);
      if (mounted) setState(() { _related = list; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _removeLink(RelatedNote r) async {
    // 关联是有向的：仅当当前笔记是 source 时，releatedNotes 里的 outgoing 才为
    // true。删除时按实际存储方向删——若不是 source，则反向删。
    await NoteStore.instance.deleteLink(
      r.outgoing ? widget.note.id : r.noteId,
      r.outgoing ? r.noteId : widget.note.id,
    );
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    // 无关联时不显示该区域（不留占位）。整理入口由 [AiTidyButton] 单独提供，
    // 使「无关联」时仍能触发 AI 整理。
    if (!_loaded || _related.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 13, color: _accent),
              const SizedBox(width: 6),
              Text('关联笔记 (${_related.length})',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _titleColor)),
            ],
          ),
          const SizedBox(height: 4),
          ..._related.map((r) => _row(r)),
        ],
      ),
    );
  }

  Widget _row(RelatedNote r) {
    return InkWell(
      onTap: () => widget.onOpenNote(r.noteId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 12, color: _subColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: const TextStyle(fontSize: 12, color: _titleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (r.reason != null && r.reason!.isNotEmpty)
                    Text(r.reason!,
                        style: const TextStyle(fontSize: 10, color: _subColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 12, color: _subColor),
              tooltip: '移除关联',
              onPressed: () => _removeLink(r),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// 独立的「AI 整理建议」按钮，供无关联时仍能触发整理。
///
/// 与 [RelatedNotesSection] 分开，使入口在笔记无关联（区域隐藏）时依然可达。
class AiTidyButton extends StatefulWidget {
  const AiTidyButton({
    super.key,
    required this.note,
    required this.onChanged,
  });

  final Note note;
  final VoidCallback onChanged;

  @override
  State<AiTidyButton> createState() => _AiTidyButtonState();
}

class _AiTidyButtonState extends State<AiTidyButton> {
  static const _accent = Color(0xFF3B82F6);
  static const _subColor = Color(0xFF64748B);

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
        widget.onChanged();
        final msg = StringBuffer('已应用');
        if (result.tags > 0) msg.write(' ${result.tags} 个标签');
        if (result.links > 0) msg.write(' ${result.links} 条关联');
        if (result.tags == 0 && result.links == 0) msg.write(' 0 项');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: _busy
          ? const SizedBox(
              width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.2))
          : const Icon(Icons.auto_awesome, size: 12, color: _accent),
      label: const Text('AI 整理建议',
          style: TextStyle(fontSize: 11, color: _accent)),
      onPressed: _busy ? null : _open,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: _subColor,
      ),
    );
  }
}
