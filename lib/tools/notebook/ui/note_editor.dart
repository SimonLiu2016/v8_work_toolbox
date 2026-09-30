import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:appflowy_editor/appflowy_editor.dart';

import '../../../theme/app_theme.dart';
import '../appflowy_codec.dart';
import '../note_database.dart';
import '../note_store.dart';
import 'asset_fields_panel.dart';
import 'related_notes_section.dart';
import 'components/attachment_block_component.dart';
import 'components/note_code_block_component.dart';
import 'components/note_editor_toolbar.dart';
import 'components/note_image_menu.dart';
import 'components/note_mindmap_component.dart';
import 'notebook_light_scope.dart';

class NoteEditor extends StatefulWidget {
  final Note? note;
  final VoidCallback? onSaved;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentDelete;

  /// 点击关联笔记时跳转（阶段三）。
  final void Function(String noteId)? onOpenNote;

  /// 编辑器从数据库重新读到当前笔记时回调（资产/关联写入后的快照刷新）。
  ///
  /// 父层用它替换自己持有的 `note` 快照，使元数据栏的资产 chip 与关联计数反映
  /// 持久化现状，而不是打开编辑器时的旧值。
  final void Function(Note note)? onNoteReloaded;

  const NoteEditor({
    super.key,
    this.note,
    this.onSaved,
    this.onTogglePin,
    this.onDelete,
    this.onRestore,
    this.onPermanentDelete,
    this.onOpenNote,
    this.onNoteReloaded,
  });

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  StreamSubscription? _transactionSub;
  late TextEditingController _titleCtrl;
  Timer? _bodyDebounce;
  bool _isSaving = false;

  /// 追加 Markdown 内容到当前活跃编辑器末尾，并实时更新视图与持久化到数据库。
  Future<bool> appendMarkdown(String markdown) async {
    if (_editorState == null || !mounted) return false;
    try {
      final appendDoc = AppFlowyCodec.parseToDocument('\n\n---\n\n$markdown');
      final transaction = _editorState!.transaction;
      var insertIdx = _editorState!.document.root.children.length;
      for (final node in appendDoc.root.children) {
        transaction.insertNode([insertIdx++], node);
      }
      await _editorState!.apply(transaction);

      // 光标置底并激活焦点（自动触发将新段落滚动进入视野）
      _focusEditorAtEnd();

      // 立即保存至底层存储并通知刷新
      await _save();
      return true;
    } catch (e) {
      debugPrint('NoteEditor.appendMarkdown 出错: $e');
      return false;
    }
  }

  /// 获取当前编辑器的文档模型实例
  Document? get document => _editorState?.document;

  /// 获取当前编辑器的纯文本内容
  String get plainText =>
      _editorState == null ? '' : AppFlowyCodec.documentToPlainText(_editorState!.document);

  List<Notebook> _notebooks = [];
  List<Tag> _allTags = [];
  List<Tag> _noteTags = [];

  /// 当前笔记的关联数，用于元数据栏的「关联 N」chip（0 时不渲染）。
  int _relatedCount = 0;

  late FocusNode _editorFocusNode;
  late final Map<String, BlockComponentBuilder> _blockComponentBuilders;

  EditorStyle get _editorStyle => EditorStyle.desktop(
    padding: EdgeInsets.symmetric(horizontal: 36, vertical: 20),
    cursorColor: context.accentSolid,
    selectionColor: context.accentSolid.withValues(alpha: 0.2),
    textStyleConfiguration: const TextStyleConfiguration(
      text: TextStyle(fontSize: 15.0, color: Color(0xFF0F172A), height: 1.6),
      bold: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
      italic: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF0F172A)),
    ),
  );

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode(debugLabel: 'NoteEditorCanvasFocus');
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _initBlockBuilders();
    _initEditor();
    _loadMetadata();
  }

  void _initBlockBuilders() {
    // 注意：此处不读 context.*——_initBlockBuilders 由 initState 调用，
    // 而 initState 期间禁止 dependOnInheritedWidget（读 ThemeExtension 会触发）。
    // 表格描边需要强调色的地方改在 build 内解析后传入。
    _blockComponentBuilders = {
      ...standardBlockComponentBuilderMap,
      TableBlockKeys.type: TableBlockComponentBuilder(
        tableStyle: TableStyle(
          borderWidth: 1.0,
          borderColor: Color(0xFFE2E8F0),
        ),
      ),
      TableCellBlockKeys.type: TableCellBlockComponentBuilder(
        colorBuilder: (context, node) {
          final row =
              node.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;
          if (row == 0) {
            return const Color(0xFFF8FAFC);
          }
          return Colors.white;
        },
      ),
      ImageBlockKeys.type: ImageBlockComponentBuilder(
        showMenu: true,
        menuBuilder: (node, state) => buildNoteImageMenu(context, node, state),
      ),
      NoteCodeBlockKeys.type: NoteCodeBlockComponentBuilder(),
      'code': NoteCodeBlockComponentBuilder(),
      AttachmentBlockKeys.type: AttachmentBlockComponentBuilder(),
      MindMapBlockKeys.type: MindMapBlockComponentBuilder(),
    };
  }

  void _initEditor() {
    _transactionSub?.cancel();
    _editorScrollController?.dispose();
    if (widget.note != null) {
      final doc = AppFlowyCodec.parseToDocument(widget.note!.deltaJson);
      _editorState = EditorState(document: doc);
      _editorScrollController = EditorScrollController(
        editorState: _editorState!,
        shrinkWrap: false,
      );
      _transactionSub = _editorState!.transactionStream.listen((_) {
        _scheduleBodySave();
      });
    } else {
      _editorState = null;
      _editorScrollController = null;
    }
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note?.id != widget.note?.id) {
      _titleCtrl.text = widget.note?.title ?? '';
      _initEditor();
      _loadMetadata();
    }
  }

  @override
  void dispose() {
    _transactionSub?.cancel();
    _bodyDebounce?.cancel();
    _editorScrollController?.dispose();
    _editorState?.dispose();
    _editorFocusNode.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _focusEditorAtEnd() {
    if (_editorState == null || !mounted) return;
    _editorFocusNode.requestFocus();
    if (_editorState!.document.root.children.isNotEmpty) {
      final lastNode = _editorState!.document.root.children.last;
      final length = lastNode.delta?.length ?? 0;
      _editorState!.updateSelectionWithReason(
        Selection.single(path: lastNode.path, startOffset: length),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  Future<void> _loadMetadata() async {
    if (widget.note == null) return;
    try {
      final store = NoteStore.instance;
      final nbs = await store.allNotebooks();
      final tags = await store.allTags();
      final noteTags = await store.tagsForNote(widget.note!.id);
      final related = await store.relatedNotes(widget.note!.id);
      if (mounted) {
        setState(() {
          _notebooks = nbs;
          _allTags = tags;
          _noteTags = noteTags;
          _relatedCount = related.length;
        });
      }
    } catch (e) {
      debugPrint('NoteEditor._loadMetadata safe notice: $e');
    }
  }

  /// 弹窗（资产 / 整理 / 关联）写入后刷新元数据栏与外部列表。
  ///
  /// 除元数据外还重新读一次当前笔记本身：资产 chip 的文案（品类 / 到期倒计时）
  /// 与关联计数都来自 `widget.note`，只重读列表的话这些值会停留在打开时的快照，
  /// 表现为「保存后内容丢失」。
  Future<void> _refreshMetadata() async {
    await _loadMetadata();
    final reloaded = await _reloadNote();
    widget.onSaved?.call();
    return reloaded;
  }

  /// 从数据库重新读取当前笔记，并上报给父层替换其快照。
  ///
  /// 父层的 `_refresh` 只在笔记仍处于当前过滤列表内时才更新 `_selectedNote`；
  /// 一旦过滤条件变化（搜索词、标签、笔记本切换）它会改为清空选择，资产 chip
  /// 就再也拿不到新值。这里显式回传，保证写入后 UI 反映数据库现状。
  Future<void> _reloadNote() async {
    final id = widget.note?.id;
    if (id == null) return;
    try {
      final latest = await NoteStore.instance.noteById(id);
      if (latest != null && mounted) {
        widget.onNoteReloaded?.call(latest);
      }
    } catch (e) {
      debugPrint('NoteEditor._reloadNote safe notice: $e');
    }
  }

  Future<void> _openAssetDialog() async {
    final note = widget.note;
    if (note == null) return;
    await showAssetDialog(context, note: note, onChanged: _refreshMetadata);
    // 弹窗可能在父组件重建后仍持有旧 note 引用，取最新一份再刷新。
    await _refreshMetadata();
  }

  Future<void> _openRelatedDialog() async {
    final note = widget.note;
    if (note == null) return;
    await showRelatedNotesDialog(
      context,
      note: note,
      onOpenNote: (id) => widget.onOpenNote?.call(id),
      onChanged: _refreshMetadata,
    );
    await _refreshMetadata();
  }

  void _onTitleChanged(String _) {
    _scheduleBodySave();
  }

  void _scheduleBodySave() {
    _bodyDebounce?.cancel();
    _bodyDebounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_isSaving || widget.note == null || _editorState == null) return;
    _isSaving = true;
    if (mounted) setState(() {});

    try {
      final contentJson = AppFlowyCodec.documentToJson(_editorState!.document);
      final currentTitle = _titleCtrl.text.trim();
      await NoteStore.instance.updateNote(
        id: widget.note!.id,
        title: currentTitle.isEmpty ? '无标题笔记' : currentTitle,
        deltaJson: contentJson,
      );
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Notebook & Tag operations
  // ---------------------------------------------------------------------------

  Future<void> _changeNotebook(String? newNotebookId) async {
    if (widget.note == null) return;
    await NoteStore.instance.updateNote(
      id: widget.note!.id,
      notebookId: newNotebookId,
    );
    await _loadMetadata();
    widget.onSaved?.call();
  }

  Future<void> _togglePin() async {
    if (widget.note == null) return;
    final newPinned = !widget.note!.isPinned;
    await NoteStore.instance.updateNote(
      id: widget.note!.id,
      isPinned: newPinned,
    );
    widget.onTogglePin?.call();
    widget.onSaved?.call();
  }

  Future<void> _addTagDialog() async {
    if (widget.note == null) return;
    final tagCtrl = TextEditingController();

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => NotebookLightScope(
        child: AlertDialog(
          backgroundColor: context.bgCard,
          title: const Text('添加标签', style: AppTheme.fontTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  hintText: '输入新标签名称或选择已有标签',
                  isDense: true,
                ),
                autofocus: true,
              ),
              if (_allTags.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space12),
                const Text('已有标签：', style: AppTheme.fontCaption),
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allTags
                      .where((t) => !_noteTags.any((nt) => nt.id == t.id))
                      .map((t) {
                        return ActionChip(
                          label: Text(t.name),
                          onPressed: () => Navigator.pop(ctx, t.name),
                        );
                      })
                      .toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, tagCtrl.text.trim()),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      final store = NoteStore.instance;
      final match = _allTags.where((t) => t.name == selected).toList();
      String tagId;
      if (match.isNotEmpty) {
        tagId = match.first.id;
      } else {
        tagId = await store.createTag(selected);
      }
      final newTagIds = {..._noteTags.map((t) => t.id), tagId}.toList();
      await store.setNoteTags(widget.note!.id, newTagIds);
      await _loadMetadata();
      widget.onSaved?.call();
    }
  }

  Future<void> _removeTag(String tagId) async {
    if (widget.note == null) return;
    final newTagIds = _noteTags
        .map((t) => t.id)
        .where((id) => id != tagId)
        .toList();
    await NoteStore.instance.setNoteTags(widget.note!.id, newTagIds);
    await _loadMetadata();
    widget.onSaved?.call();
  }

  // ---------------------------------------------------------------------------
  // Paste Interception (macOS bitmap images to attachments)
  // ---------------------------------------------------------------------------

  Future<void> _handlePaste() async {
    if (widget.note == null || _editorState == null) return;

    // 1. 尝试使用 AppleScript 探测 macOS 系统剪贴板是否含位图图像
    final tempImagePath =
        '/tmp/v8_clipboard_paste_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      final res = await Process.run('osascript', [
        '-e',
        'try\n'
            '  set theFile to open for access POSIX file "$tempImagePath" with write permission\n'
            '  set eof theFile to 0\n'
            '  write (the clipboard as «class PNGf») to theFile\n'
            '  close access theFile\n'
            '  return "ok"\n'
            'on error\n'
            '  try\n'
            '    close access POSIX file "$tempImagePath"\n'
            '  end try\n'
            '  return "fail"\n'
            'end try',
      ]);

      if (res.exitCode == 0 && res.stdout.toString().trim() == 'ok') {
        final f = File(tempImagePath);
        if (await f.exists() && await f.length() > 0) {
          final savedPath = await NoteStore.instance.saveAttachment(
            noteId: widget.note!.id,
            sourceFile: f,
            filename: 'paste_${DateTime.now().millisecondsSinceEpoch}.png',
            mime: 'image/png',
          );
          try {
            await f.delete();
          } catch (_) {}

          _insertImageAtCursor(savedPath);
          return;
        }
      }
    } catch (e) {
      debugPrint('Clipboard bitmap image check error: $e');
    }

    // 2. 检测剪贴板文本是否为本地已有图片路径
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipData?.text?.trim();
    if (text != null && text.isNotEmpty) {
      final f = File(text);
      if (await f.exists()) {
        final ext = p.extension(text).toLowerCase();
        if ({'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'}.contains(ext)) {
          final savedPath = await NoteStore.instance.saveAttachment(
            noteId: widget.note!.id,
            sourceFile: f,
            filename: p.basename(text),
            mime: 'image/${ext.replaceFirst('.', '')}',
          );
          _insertImageAtCursor(savedPath);
          return;
        }
      }
    }
  }

  void _insertImageAtCursor(String path) {
    if (_editorState == null) return;
    final selection = _editorState!.selection;
    final targetPath = selection != null
        ? [selection.end.path[0] + 1]
        : [_editorState!.document.root.children.length];

    final node = imageNode(url: path);
    final transaction = _editorState!.transaction..insertNode(targetPath, node);
    _editorState!.apply(transaction);
    _scheduleBodySave();
  }

  Future<String> _saveAttachment(File file, String filename) async {
    return await NoteStore.instance.saveAttachment(
      noteId: widget.note!.id,
      sourceFile: file,
      filename: filename,
    );
  }

  /// 添加附件：保存到笔记附件目录并返回引用信息供工具栏插入附件块。
  ///
  /// 只回传附件 ID 与展示元数据——文件路径由附件块渲染时查表解析，
  /// 确保引用的是应用副本而非用户选择的原始文件。
  Future<List<AttachmentRef>> _addAttachments(List<File> files) async {
    final refs = <AttachmentRef>[];
    for (final file in files) {
      try {
        final attId = await NoteStore.instance.addAttachment(
          noteId: widget.note!.id,
          sourceFile: file,
        );
        final stat = await file.stat();
        refs.add(
          AttachmentRef(
            attachmentId: attId,
            filename: p.basename(file.path),
            sizeBytes: stat.size,
          ),
        );
      } catch (e) {
        debugPrint('添加附件失败 ${file.path}: $e');
      }
    }
    _scheduleBodySave();
    return refs;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.note == null || _editorState == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 64,
              color: context.textTertiary,
            ),
            SizedBox(height: AppTheme.space16),
            Text(
              '选择或创建一条笔记开始记录',
              style: AppTheme.fontBody.copyWith(color: context.textTertiary),
            ),
          ],
        ),
      );
    }

    final currentNotebook = _notebooks
        .where((nb) => nb.id == widget.note!.notebookId)
        .firstOrNull;

    return NotebookLightScope(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _handlePaste,
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _handlePaste,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 废纸篓警告横幅
            if (widget.note!.isDeleted)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.space16,
                  vertical: AppTheme.space8,
                ),
                color: context.warningText.withValues(alpha: 0x1F / 255),
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: context.warningText,
                    ),
                    SizedBox(width: AppTheme.space8),
                    Text(
                      '此笔记位于废纸篓中',
                      style: AppTheme.fontBody.copyWith(
                        color: context.warningText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onRestore,
                      child: const Text('恢复笔记'),
                    ),
                    SizedBox(width: AppTheme.space8),
                    TextButton(
                      onPressed: widget.onPermanentDelete,
                      child: Text(
                        '彻底粉碎',
                        style: TextStyle(color: context.errorText),
                      ),
                    ),
                  ],
                ),
              ),

            // 元数据栏：笔记本选择器、标签列表、置顶切换
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: 6,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  // 笔记本下拉选择
                  PopupMenuButton<String?>(
                    tooltip: '切换所属笔记本',
                    onSelected: (nbId) => _changeNotebook(nbId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentNotebook?.icon ?? '📓',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            currentNotebook?.name ?? '默认笔记本',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('📓 默认笔记本 (未归类)'),
                      ),
                      ..._notebooks.map(
                        (nb) => PopupMenuItem<String?>(
                          value: nb.id,
                          child: Text('${nb.icon} ${nb.name}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppTheme.space8),

                  // 标签列表
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._noteTags.map(
                            (tag) => Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '#${tag.name}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  InkWell(
                                    onTap: () => _removeTag(tag.id),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _addTagDialog,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    size: 12,
                                    color: context.accentText,
                                  ),
                                  Text(
                                    ' 标签',
                                    style: TextStyle(
                                      color: context.accentText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 资产 / 凭证入口：有数据显示品类或到期倒计时
                          AssetChipButton(
                            note: widget.note!,
                            onTap: _openAssetDialog,
                          ),

                          // AI 整理建议入口
                          AiTidyChip(
                            note: widget.note!,
                            onChanged: _refreshMetadata,
                          ),

                          // 关联笔记入口：无关联时不渲染
                          if (_relatedCount > 0)
                            MetaChip(
                              icon: Icons.hub_outlined,
                              label: '关联 $_relatedCount',
                              tooltip: '查看 / 移除关联笔记',
                              onTap: _openRelatedDialog,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // 置顶按钮
                  IconButton(
                    icon: Icon(
                      widget.note!.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 18,
                      color: widget.note!.isPinned
                          ? context.accentSolid
                          : context.textTertiary,
                    ),
                    tooltip: widget.note!.isPinned ? '取消置顶' : '置顶笔记',
                    onPressed: _togglePin,
                  ),
                ],
              ),
            ),

            // 笔记标题输入框
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space24,
                AppTheme.space12,
                AppTheme.space24,
                AppTheme.space4,
              ),
              color: Colors.white,
              child: TextField(
                controller: _titleCtrl,
                onChanged: _onTitleChanged,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  height: 1.3,
                ),
                decoration: const InputDecoration(
                  hintText: '笔记标题...',
                  hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.normal,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            // 编辑器格式工具栏（紧邻画布，属性入口已收拢进元数据栏）
            NoteEditorToolbar(
              editorState: _editorState!,
              onSaveAttachment: _saveAttachment,
              onAddAttachments: _addAttachments,
            ),

            // AppFlowyEditor 编辑器画布（由 AppFlowy 原生接管视口与滚动）
            Expanded(
              child: Container(
                color: Colors.white,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _focusEditorAtEnd,
                  child: AppFlowyEditor(
                    editorState: _editorState!,
                    editorScrollController: _editorScrollController,
                    editorStyle: _editorStyle,
                    blockComponentBuilders: _blockComponentBuilders,
                    focusNode: _editorFocusNode,
                    footer: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _focusEditorAtEnd,
                      child: const SizedBox(
                        width: double.infinity,
                        height: 280,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
