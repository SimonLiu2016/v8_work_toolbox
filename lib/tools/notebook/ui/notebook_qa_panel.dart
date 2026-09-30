import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/markdown_view.dart';
import '../appflowy_codec.dart';
import '../note_database.dart';
import '../note_store.dart';
import '../notebook_kb_service.dart';
import 'notebook_light_scope.dart';

/// 笔记本 AI 问答面板（阶段二 + 阶段五定向笔记上下文绑定）。
///
/// 功能：
/// 1. 顶部上下文胶囊栏（Scope Capsule Bar）：默认绑定当前正在编辑的笔记，支持解绑切回全库检索或主动指定；
/// 2. 输入框 `@` 提及（@Mention Autocomplete）：输入 `@` 触发悬浮建议，插入特定笔记引用；
/// 3. 全文上下文注入与工具调用：针对选定笔记提取全文注入 Prompt，保留联网与笔记检索能力；
/// 4. 问答结果沉淀：支持一键「保存为新笔记」、「追加到当前笔记」与「复制回答」。
class NotebookQaPanel extends StatefulWidget {
  const NotebookQaPanel({
    super.key,
    required this.onOpenNote,
    this.activeNote,
    this.onNoteCreated,
    this.onAppendToActiveNote,
  });

  /// 点击引用或新创建笔记时定位到对应笔记。
  final void Function(String noteId) onOpenNote;

  /// 当前编辑器打开的活动笔记。
  final Note? activeNote;

  /// 笔记创建或更新成功时的回调（刷新笔记列表）。
  final VoidCallback? onNoteCreated;

  /// 追加内容到当前活动笔记的回调（若提供，则优先调用）。
  final Future<bool> Function(String markdown)? onAppendToActiveNote;

  @override
  State<NotebookQaPanel> createState() => _NotebookQaPanelState();
}

class _NotebookQaPanelState extends State<NotebookQaPanel> {
  static const _titleColor = NotebookLightScope.textPrimary;
  static const _subColor = NotebookLightScope.textSecondary;
  static const _borderColor = NotebookLightScope.border;
  static const _accent = NotebookLightScope.accent;

  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();
  bool _busy = false;

  /// 当前胶囊栏绑定的目标笔记。
  Note? _scopedNote;

  /// 记录上一次父级传入的笔记 ID，用于判断是否切换了新笔记。
  String? _lastActiveNoteId;

  /// 用户是否显式点击了 `✕` 关闭针对当前笔记的绑定。
  bool _userClearedScope = false;

  /// 通过 `@` 提及附加的目标笔记列表。
  final List<Note> _mentionedNotes = [];

  /// `@` 自动补全相关状态
  bool _showMentionSuggestions = false;
  int _mentionStartIndex = -1;
  List<Note> _mentionCandidates = [];
  int _mentionSelectedIndex = 0;

  /// 问答历史，最新在后。
  final List<_QaTurn> _turns = [];

  @override
  void initState() {
    super.initState();
    _scopedNote = widget.activeNote;
    _lastActiveNoteId = widget.activeNote?.id;
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant NotebookQaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeNote?.id != _lastActiveNoteId) {
      _lastActiveNoteId = widget.activeNote?.id;
      if (widget.activeNote != null) {
        // 用户切换打开了不同的笔记，自动绑定新笔记
        setState(() {
          _scopedNote = widget.activeNote;
          _userClearedScope = false;
        });
      } else if (!_userClearedScope) {
        setState(() {
          _scopedNote = null;
        });
      }
    } else if (widget.activeNote != null && _scopedNote?.id == widget.activeNote!.id) {
      _scopedNote = widget.activeNote;
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.baseOffset <= 0) {
      if (_showMentionSuggestions) {
        setState(() => _showMentionSuggestions = false);
      }
      return;
    }

    final cursor = sel.baseOffset;
    final textBefore = text.substring(0, cursor);
    final lastAt = textBefore.lastIndexOf('@');

    if (lastAt >= 0) {
      final query = textBefore.substring(lastAt + 1);
      if (!query.contains(' ') && !query.contains('\n') && query.length <= 15) {
        _mentionStartIndex = lastAt;
        _fetchMentionCandidates(query);
        return;
      }
    }

    if (_showMentionSuggestions) {
      setState(() => _showMentionSuggestions = false);
    }
  }

  Future<void> _fetchMentionCandidates(String query) async {
    try {
      final all = await NoteStore.instance.allNotes();
      if (!mounted) return;
      final filtered = all.where((n) {
        if (query.isEmpty) return true;
        return n.title.toLowerCase().contains(query.toLowerCase());
      }).take(6).toList();

      setState(() {
        _mentionCandidates = filtered;
        _mentionSelectedIndex = 0;
        _showMentionSuggestions = filtered.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _showMentionSuggestions = false);
      }
    }
  }

  void _selectMentionCandidate(Note candidate) {
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    if (_mentionStartIndex >= 0 && _mentionStartIndex <= text.length) {
      final beforeAt = text.substring(0, _mentionStartIndex);
      final afterCursor = cursor <= text.length ? text.substring(cursor) : '';
      final noteTitle = candidate.title.trim().isEmpty ? '无标题' : candidate.title.trim();
      final mentionTag = '「@$noteTitle」 ';
      final newText = '$beforeAt$mentionTag$afterCursor';
      _ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: beforeAt.length + mentionTag.length),
      );
    }
    if (!_mentionedNotes.any((n) => n.id == candidate.id)) {
      _mentionedNotes.add(candidate);
    }
    setState(() {
      _showMentionSuggestions = false;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_showMentionSuggestions || _mentionCandidates.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _mentionSelectedIndex =
              (_mentionSelectedIndex + 1) % _mentionCandidates.length;
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _mentionSelectedIndex =
              (_mentionSelectedIndex - 1 + _mentionCandidates.length) %
                  _mentionCandidates.length;
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        _selectMentionCandidate(_mentionCandidates[_mentionSelectedIndex]);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _showMentionSuggestions = false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || _busy) return;
    _ctrl.clear();

    final targetList = <Note>[];
    if (_scopedNote != null) {
      targetList.add(_scopedNote!);
    }
    for (final m in _mentionedNotes) {
      if (!targetList.any((n) => n.id == m.id)) {
        targetList.add(m);
      }
    }

    setState(() {
      _busy = true;
      _showMentionSuggestions = false;
      _turns.add(_QaTurn(
        question: q,
        pending: true,
        targetNotes: targetList.isNotEmpty ? List.of(targetList) : null,
      ));
    });
    _scrollToEnd();

    KbAnswer answer;
    try {
      answer = await NotebookKbService.instance.ask(
        q,
        targetNotes: targetList.isNotEmpty ? targetList : null,
      );
    } catch (e) {
      answer = KbAnswer.failure('出错了：$e');
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _mentionedNotes.clear();
      _turns.last = _QaTurn(
        question: q,
        answer: answer,
        targetNotes: targetList.isNotEmpty ? List.of(targetList) : null,
      );
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotebookLightScope(
      child: Container(
        color: NotebookLightScope.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _scopeBar(),
            Expanded(
              child: _turns.isEmpty
                  ? _emptyHint()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _buildTurn(_turns[i]),
                    ),
            ),
            if (_showMentionSuggestions && _mentionCandidates.isNotEmpty)
              _buildMentionSuggestions(),
            const Divider(height: 1, color: _borderColor),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 15, color: _accent),
          const SizedBox(width: 6),
          const Text(
            '问我的笔记',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
          const Spacer(),
          if (_turns.isNotEmpty)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 15,
                  color: _subColor,
                ),
                tooltip: '清空对话',
                onPressed: () => setState(_turns.clear),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }

  /// 顶部上下文胶囊栏
  Widget _scopeBar() {
    final hasScope = _scopedNote != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: _borderColor),
          bottom: BorderSide(color: _borderColor),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded, size: 12, color: _subColor),
          const SizedBox(width: 4),
          const Text(
            '范围:',
            style: TextStyle(fontSize: 11, color: _subColor, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (hasScope)
                    Container(
                      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.description_outlined, size: 12, color: _accent),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              _scopedNote!.title.trim().isEmpty ? '无标题笔记' : _scopedNote!.title,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _accent,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _scopedNote = null;
                                _userClearedScope = true;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: const Padding(
                              padding: EdgeInsets.all(2.0),
                              child: Icon(Icons.close_rounded, size: 12, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.public_rounded, size: 12, color: _subColor),
                          SizedBox(width: 4),
                          Text(
                            '全库检索',
                            style: TextStyle(fontSize: 11, color: _subColor),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _showNotePicker,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add_rounded, size: 12, color: _subColor),
                          SizedBox(width: 2),
                          Text(
                            '指定笔记',
                            style: TextStyle(fontSize: 10, color: _subColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出笔记选择器对话框
  Future<void> _showNotePicker() async {
    final notes = await NoteStore.instance.allNotes();
    if (!mounted) return;

    final picked = await showDialog<Note>(
      context: context,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final filtered = notes.where((n) {
              if (filter.isEmpty) return true;
              return n.title.toLowerCase().contains(filter.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('指定问答分析的目标笔记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              content: SizedBox(
                width: 320,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 16),
                        hintText: '搜索笔记标题…',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDlgState(() => filter = val.trim());
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('无匹配笔记', style: TextStyle(fontSize: 12, color: _subColor)),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final n = filtered[i];
                                final isCur = n.id == _scopedNote?.id;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.description_outlined, size: 16, color: _subColor),
                                  title: Text(
                                    n.title.trim().isEmpty ? '无标题笔记' : n.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isCur ? FontWeight.w600 : FontWeight.normal,
                                      color: isCur ? _accent : _titleColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: isCur
                                      ? const Icon(Icons.check, size: 16, color: _accent)
                                      : null,
                                  onTap: () => Navigator.of(ctx).pop(n),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _scopedNote = picked;
        _userClearedScope = false;
      });
    }
  }

  Widget _emptyHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.forum_outlined, size: 40, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          const Text(
            '问点关于你笔记的事',
            style: TextStyle(fontSize: 13, color: _subColor),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _scopedNote != null
                  ? '已选定「${_scopedNote!.title}」，可要求总结、理流程或检视逻辑'
                  : '输入 @ 提及特定笔记，或直接提问「豆浆机坏了怎么办」',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _subColor.withAlpha(180)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurn(_QaTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 用户问题
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    turn.question,
                    style: const TextStyle(fontSize: 12, color: _titleColor),
                  ),
                  if (turn.targetNotes != null && turn.targetNotes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: turn.targetNotes!.map((n) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '📄 ${n.title.trim().isEmpty ? "未命名" : n.title}',
                            style: const TextStyle(fontSize: 9, color: Color(0xFF1D4ED8)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 回答
          if (turn.pending)
            Row(
              children: const [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                SizedBox(width: 8),
                Text(
                  '正在深度分析笔记内容…',
                  style: TextStyle(fontSize: 12, color: _subColor),
                ),
              ],
            )
          else if (turn.answer != null) ...[
            if (turn.answer!.error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  turn.answer!.text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              )
            else if (turn.answer!.noMatch)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      turn.answer!.text,
                      style: const TextStyle(fontSize: 12, color: _subColor),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.travel_explore, size: 13),
                      label: const Text(
                        '改用联网检索',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: _busy ? null : () => _askWeb(turn.question),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              )
            else
              AppMarkdownView(
                data: turn.answer!.text,
                baseStyle: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _titleColor,
                ),
                codeBlockColor: NotebookLightScope.codeSurface,
              ),
            if (turn.answer!.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: turn.answer!.citations
                    .map((c) => _citationChip(c))
                    .toList(),
              ),
            ],
            // 动作按钮条
            _turnActions(turn),
          ],
        ],
      ),
    );
  }

  /// 问答卡片底部操作区
  Widget _turnActions(_QaTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 4,
        children: [
          _actionBtn(
            icon: Icons.note_add_outlined,
            label: '保存为新笔记',
            onTap: () => _saveAnswerAsNewNote(turn),
          ),
          _actionBtn(
            icon: Icons.post_add_outlined,
            label: '追加到正文',
            disabled: widget.activeNote == null && _scopedNote == null,
            onTap: () => _appendAnswerToNote(turn),
          ),
          _actionBtn(
            icon: Icons.copy_rounded,
            label: '复制',
            onTap: () => _copyAnswer(turn),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: disabled ? const Color(0xFFE2E8F0) : _borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: disabled ? const Color(0xFFCBD5E1) : _subColor,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: disabled ? const Color(0xFFCBD5E1) : _titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一键保存回答为新富文本笔记
  Future<void> _saveAnswerAsNewNote(_QaTurn turn) async {
    final answerText = turn.answer?.text;
    if (answerText == null || answerText.trim().isEmpty) return;

    String defaultTitle = turn.question.replaceAll(RegExp(r'[\n\r]+'), ' ').trim();
    if (defaultTitle.startsWith('（联网）')) {
      defaultTitle = defaultTitle.replaceFirst('（联网）', '').trim();
    }
    if (defaultTitle.length > 25) {
      defaultTitle = '${defaultTitle.substring(0, 25)}…';
    }
    if (defaultTitle.isEmpty) {
      defaultTitle = 'AI 整理笔记';
    } else {
      defaultTitle = '整理：$defaultTitle';
    }

    final titleController = TextEditingController(text: defaultTitle);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为新笔记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入新笔记的标题：', style: TextStyle(fontSize: 12, color: _subColor)),
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final finalTitle =
        titleController.text.trim().isEmpty ? defaultTitle : titleController.text.trim();

    try {
      final doc = AppFlowyCodec.parseToDocument(answerText);
      final deltaJson = AppFlowyCodec.documentToJson(doc);
      final newId = await NoteStore.instance.createNote(
        title: finalTitle,
        deltaJson: deltaJson,
        notebookId: widget.activeNote?.notebookId ?? _scopedNote?.notebookId,
      );

      widget.onNoteCreated?.call();
      widget.onOpenNote(newId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存为新笔记「$finalTitle」并打开'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存笔记失败：$e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 一键追加回答到当前笔记正文
  Future<void> _appendAnswerToNote(_QaTurn turn) async {
    final answerText = turn.answer?.text;
    if (answerText == null || answerText.trim().isEmpty) return;

    final target = _scopedNote ?? widget.activeNote;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有打开或绑定的笔记可追加')),
      );
      return;
    }

    // 若追加的目标恰好是当前正在编辑的笔记，优先走实时 live editor 事务追加
    if (widget.activeNote != null &&
        target.id == widget.activeNote!.id &&
        widget.onAppendToActiveNote != null) {
      final ok = await widget.onAppendToActiveNote!(answerText);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功追加到「${target.title}」')),
        );
        return;
      }
    }

    try {
      final existingDoc = AppFlowyCodec.parseToDocument(target.deltaJson);
      final appendDoc = AppFlowyCodec.parseToDocument('\n\n---\n\n$answerText');
      for (final node in appendDoc.root.children) {
        existingDoc.root.insert(node);
      }
      final newDeltaJson = AppFlowyCodec.documentToJson(existingDoc);
      await NoteStore.instance.updateNote(
        id: target.id,
        deltaJson: newDeltaJson,
      );
      widget.onNoteCreated?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功追加到「${target.title}」')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('追加内容失败：$e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  /// 复制回答到剪贴板
  void _copyAnswer(_QaTurn turn) {
    final text = turn.answer?.text;
    if (text == null || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('回答已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _citationChip(KbCitation c) {
    return InkWell(
      onTap: () => widget.onOpenNote(c.noteId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 11, color: _subColor),
            const SizedBox(width: 4),
            Text(c.title, style: const TextStyle(fontSize: 11, color: _accent)),
          ],
        ),
      ),
    );
  }

  Future<void> _askWeb(String question) async {
    setState(() {
      _busy = true;
      _turns.add(_QaTurn(question: '（联网）$question', pending: true));
    });
    _scrollToEnd();
    try {
      final res = await NotebookKbService.instance.askWeb(question);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _turns.last = _QaTurn(question: '（联网）$question', answer: res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _turns.last = _QaTurn(
          question: '（联网）$question',
          answer: KbAnswer.failure('联网检索失败：$e'),
        );
      });
    }
    _scrollToEnd();
  }

  /// `@` 提及联想候选列表
  Widget _buildMentionSuggestions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0F000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: const Color(0xFFEFF6FF),
            child: Row(
              children: const [
                Icon(Icons.alternate_email, size: 12, color: _accent),
                SizedBox(width: 4),
                Text(
                  '提及引用笔记（↑↓选择，Enter确定）',
                  style: TextStyle(
                    fontSize: 11,
                    color: _accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _mentionCandidates.length,
              itemBuilder: (ctx, i) {
                final item = _mentionCandidates[i];
                final isSel = i == _mentionSelectedIndex;
                return InkWell(
                  onTap: () => _selectMentionCandidate(item),
                  child: Container(
                    color: isSel ? const Color(0xFFF1F5F9) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined, size: 14, color: _subColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.title.trim().isEmpty ? '无标题笔记' : item.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                              color: isSel ? _accent : _titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_busy,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!_showMentionSuggestions) {
                      _submit();
                    }
                  },
                  style: const TextStyle(fontSize: 13, color: _titleColor),
                  decoration: const InputDecoration(
                    hintText: '输入问题，输入 @ 提及特定笔记…',
                    hintStyle: TextStyle(fontSize: 12, color: _subColor),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 18),
            color: _accent,
            tooltip: '发送',
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _QaTurn {
  final String question;
  final KbAnswer? answer;
  final bool pending;
  final List<Note>? targetNotes;

  _QaTurn({
    required this.question,
    this.answer,
    this.pending = false,
    this.targetNotes,
  });
}
