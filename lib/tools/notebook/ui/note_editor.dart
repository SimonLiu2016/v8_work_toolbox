import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../theme/app_theme.dart';
import '../note_database.dart';
import '../note_store.dart';

/// 笔记编辑器组件（仿印象笔记交互）
class NoteEditor extends StatefulWidget {
  final Note? note;
  final VoidCallback? onSaved;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentDelete;

  const NoteEditor({
    super.key,
    this.note,
    this.onSaved,
    this.onTogglePin,
    this.onDelete,
    this.onRestore,
    this.onPermanentDelete,
  });

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleCtrl;
  late final FocusNode _editorFocusNode;
  late final ScrollController _editorScrollController;
  QuillController? _quillCtrl;
  bool _isSaving = false;
  Timer? _titleDebounce;
  Timer? _bodyDebounce;

  List<Notebook> _notebooks = [];
  List<Tag> _noteTags = [];
  List<Tag> _allTags = [];

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
    _editorScrollController = ScrollController();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _initEditor();
    _loadMetadata();
    _checkAutoFocus();
  }

  void _checkAutoFocus() {
    if (widget.note == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.note!.title == '无标题笔记' || (_quillCtrl != null && _quillCtrl!.document.isEmpty())) {
        _focusEditor();
      }
    });
  }

  void _focusEditor() {
    if (!mounted) return;
    if (_editorFocusNode.canRequestFocus) {
      _editorFocusNode.requestFocus();
    }
    if (_quillCtrl != null) {
      final len = _quillCtrl!.document.length;
      final targetOffset = len > 0 ? len - 1 : 0;
      _quillCtrl!.updateSelection(
        TextSelection.collapsed(offset: targetOffset),
        ChangeSource.local,
      );
    }
  }

  void _initEditor() {
    if (widget.note != null) {
      try {
        final deltaList = jsonDecode(widget.note!.deltaJson) as List;
        final doc = Document.fromJson(List<dynamic>.from(deltaList));
        _quillCtrl = QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        debugPrint('Failed to parse delta: $e');
        _quillCtrl = QuillController.basic();
      }
    } else {
      _quillCtrl = QuillController.basic();
    }

    // Auto-save listener on content change
    _quillCtrl!.document.changes.listen((_) => _scheduleBodySave());
  }

  Future<void> _loadMetadata() async {
    if (widget.note == null) return;
    try {
      final store = NoteStore.instance;
      final nbs = await store.allNotebooks();
      final nTags = await store.tagsForNote(widget.note!.id);
      final aTags = await store.allTags();
      if (mounted) {
        setState(() {
          _notebooks = nbs;
          _noteTags = nTags;
          _allTags = aTags;
        });
      }
    } catch (e) {
      debugPrint('Error loading metadata: $e');
    }
  }

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _bodyDebounce?.cancel();
    _titleCtrl.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _quillCtrl?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note?.id != widget.note?.id) {
      _titleDebounce?.cancel();
      _bodyDebounce?.cancel();
      _quillCtrl?.dispose();
      _titleCtrl.text = widget.note?.title ?? '';
      _initEditor();
      _loadMetadata();
      _checkAutoFocus();
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-save with debounce
  // ---------------------------------------------------------------------------

  void _onTitleChanged(String _) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 800), _save);
  }

  void _scheduleBodySave() {
    _bodyDebounce?.cancel();
    _bodyDebounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_isSaving || widget.note == null || _quillCtrl == null) return;
    _isSaving = true;
    if (mounted) setState(() {});

    try {
      final deltaJson = jsonEncode(_quillCtrl!.document.toDelta().toJson());
      final currentTitle = _titleCtrl.text.trim();
      await NoteStore.instance.updateNote(
        id: widget.note!.id,
        title: currentTitle.isEmpty ? '无标题笔记' : currentTitle,
        deltaJson: deltaJson,
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
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
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
                children: _allTags.where((t) => !_noteTags.any((nt) => nt.id == t.id)).map((t) {
                  return ActionChip(
                    label: Text(t.name),
                    onPressed: () => Navigator.pop(ctx, t.name),
                  );
                }).toList(),
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
      final currentTagIds = _noteTags.map((t) => t.id).toList();
      if (!currentTagIds.contains(tagId)) {
        currentTagIds.add(tagId);
        await store.setNoteTags(widget.note!.id, currentTagIds);
        await _loadMetadata();
        widget.onSaved?.call();
      }
    }
  }

  Future<void> _removeTag(String tagId) async {
    if (widget.note == null) return;
    final updatedTagIds = _noteTags.map((t) => t.id).where((id) => id != tagId).toList();
    await NoteStore.instance.setNoteTags(widget.note!.id, updatedTagIds);
    await _loadMetadata();
    widget.onSaved?.call();
  }

  // ---------------------------------------------------------------------------
  // Image insertion
  // ---------------------------------------------------------------------------

  Future<void> _insertImage() async {
    if (widget.note == null || _quillCtrl == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final store = NoteStore.instance;

    try {
      final localPath = await store.saveAttachment(
        noteId: widget.note!.id,
        sourceFile: file,
        filename: result.files.first.name,
        mime: _getMimeType(result.files.first.extension),
      );

      final index = _quillCtrl!.selection.baseOffset;
      _quillCtrl!.document.insert(index, BlockEmbed.image(localPath));
      _quillCtrl!.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        ChangeSource.local,
      );
      _scheduleBodySave();
    } catch (e) {
      debugPrint('Image insert error: $e');
    }
  }

  String _getMimeType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      default: return 'application/octet-stream';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.note == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.space16),
            Text('选择或创建一条笔记开始记录', style: AppTheme.fontBody.copyWith(color: AppTheme.textTertiary)),
          ],
        ),
      );
    }

    final currentNotebook = _notebooks.where((nb) => nb.id == widget.note!.notebookId).firstOrNull;

    return Column(
      children: [
        // Trash Warning Banner
        if (widget.note!.isDeleted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: AppTheme.space8),
            color: AppTheme.warningSubtle,
            child: Row(
              children: [
                const Icon(Icons.delete_outline, size: 18, color: AppTheme.warning),
                const SizedBox(width: AppTheme.space8),
                Text('此笔记位于废纸篓中', style: AppTheme.fontBody.copyWith(color: AppTheme.warning)),
                const Spacer(),
                TextButton(
                  onPressed: widget.onRestore,
                  child: const Text('恢复笔记'),
                ),
                const SizedBox(width: AppTheme.space8),
                TextButton(
                  onPressed: widget.onPermanentDelete,
                  child: const Text('彻底粉碎', style: TextStyle(color: AppTheme.error)),
                ),
              ],
            ),
          ),

        // Metadata Header: Notebook selector, tags, pin toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              // Notebook selector
              PopupMenuButton<String?>(
                tooltip: '切换所属笔记本',
                onSelected: (nbId) => _changeNotebook(nbId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currentNotebook?.icon ?? '📓', style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        currentNotebook?.name ?? '默认笔记本',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text('📓 默认笔记本 (未归类)'),
                  ),
                  ..._notebooks.map((nb) => PopupMenuItem<String?>(
                    value: nb.id,
                    child: Text('${nb.icon} ${nb.name}'),
                  )),
                ],
              ),
              const SizedBox(width: AppTheme.space8),

              // Tags wrap
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._noteTags.map((tag) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('#${tag.name}', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                            const SizedBox(width: 2),
                            InkWell(
                              onTap: () => _removeTag(tag.id),
                              child: const Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )),
                      InkWell(
                        onTap: _addTagDialog,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 12, color: AppTheme.accent),
                              Text(' 标签', style: TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Pin toggle
              IconButton(
                icon: Icon(
                  widget.note!.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                  color: widget.note!.isPinned ? AppTheme.accent : const Color(0xFF64748B),
                ),
                onPressed: _togglePin,
                tooltip: widget.note!.isPinned ? '取消置顶' : '置顶笔记',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),

              // Soft Delete
              if (!widget.note!.isDeleted)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
                  onPressed: widget.onDelete,
                  tooltip: '移入废纸篓',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),
        ),

        // Title bar with translucent selection theme
        Theme(
          data: ThemeData.light().copyWith(
            textSelectionTheme: const TextSelectionThemeData(
              cursorColor: Color(0xFF2563EB),
              selectionColor: Color(0x66BFDBFE), // 半透明选区高亮
              selectionHandleColor: Color(0xFF2563EB),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: AppTheme.space8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      hintText: '输入笔记标题...',
                      hintStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _onTitleChanged,
                    onSubmitted: (_) => _save(),
                  ),
                ),
                if (_isSaving)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                  ),
              ],
            ),
          ),
        ),

        // Quill toolbar + checklist + image button
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: QuillSimpleToolbar(
                  controller: _quillCtrl!,
                  config: const QuillSimpleToolbarConfig(
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showStrikeThrough: true,
                    showHeaderStyle: true,
                    showListCheck: true,        // 开启仿印象笔记待办事项 Checkbox
                    showListNumbers: true,
                    showListBullets: true,
                    showCodeBlock: true,
                    showQuote: true,
                    showLink: true,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showSearchButton: false,
                    showAlignmentButtons: false,
                    showDirection: false,
                    showIndent: false,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.image_outlined, size: 20, color: Color(0xFF475569)),
                onPressed: _insertImage,
                tooltip: '插入图片',
              ),
            ],
          ),
        ),

        // Editor with light paper styling & customized typography
        Expanded(
          child: Theme(
            data: ThemeData.light().copyWith(
              textSelectionTheme: const TextSelectionThemeData(
                cursorColor: Color(0xFF2563EB),
                selectionColor: Color(0x66BFDBFE), // 半透明高亮选区，避免遮盖底层文本
                selectionHandleColor: Color(0xFF2563EB),
              ),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _focusEditor,
              child: Container(
                color: const Color(0xFFFFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: QuillEditor.basic(
                  controller: _quillCtrl!,
                  focusNode: _editorFocusNode,
                  scrollController: _editorScrollController,
                  config: QuillEditorConfig(
                    padding: EdgeInsets.zero,
                    autoFocus: false,
                    expands: true,
                    embedBuilders: const [
                      NoteImageEmbedBuilder(),
                    ],
                    unknownEmbedBuilder: const NoteUnknownEmbedBuilder(),
                    customStyles: DefaultStyles.getInstance(context).merge(
                      DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 14,
                            height: 1.6,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(0, 0),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h1: DefaultTextBlockStyle(
                          const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(12, 4),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h2: DefaultTextBlockStyle(
                          const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(10, 4),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h3: DefaultTextBlockStyle(
                          const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(8, 4),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        code: DefaultTextBlockStyle(
                          const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                            height: 1.45,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(8, 8),
                          const VerticalSpacing(0, 0),
                          BoxDecoration(
                            color: const Color(0xFFF1F5F9), // 优雅浅灰代码底色
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                        ),
                        inlineCode: InlineCodeStyle(
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Color(0xFFB45309),
                            backgroundColor: Color(0xFFFEF3C7),
                          ),
                        ),
                        quote: DefaultTextBlockStyle(
                          const TextStyle(
                            color: Color(0xFF475569),
                            fontStyle: FontStyle.italic,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(6, 6),
                          const VerticalSpacing(0, 0),
                          const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFFCBD5E1), width: 4),
                            ),
                          ),
                        ),
                        link: const TextStyle(
                          color: Color(0xFF2563EB),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 自定义 Quill 图片嵌入渲染器（安全支持本地文件与网络图片，防崩溃且自适应宽度）
class NoteImageEmbedBuilder extends EmbedBuilder {
  const NoteImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  ) {
    final dynamic data = embedContext.node.value.data;
    final imageSource = data is String ? data : '';
    if (imageSource.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget imageWidget;
    if (imageSource.startsWith('http://') || imageSource.startsWith('https://')) {
      imageWidget = Image.network(
        imageSource,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(imageSource),
      );
    } else {
      final file = File(imageSource);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(imageSource),
        );
      } else {
        imageWidget = _buildErrorPlaceholder(imageSource);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 750,
          maxHeight: 500,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 20, color: Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '图片附件加载失败 ($fileName)',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义未知 Embed 兜底渲染器，避免抛出 UnimplementedError 导致整页灰屏崩溃
class NoteUnknownEmbedBuilder extends EmbedBuilder {
  const NoteUnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  ) {
    final embedType = embedContext.node.value.type;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_outlined, size: 14, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            '嵌入对象: $embedType',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

