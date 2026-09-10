import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

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
        final sanitized = _sanitizeDeltaList(deltaList);
        final doc = Document.fromJson(List<dynamic>.from(sanitized));
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

  List<dynamic> _sanitizeDeltaList(List deltaList) {
    final result = <dynamic>[];
    for (int i = 0; i < deltaList.length; i++) {
      final op = deltaList[i];
      if (op is Map<String, dynamic>) {
        final insert = op['insert'];
        // 自动识别思维导图纯 JSON 字符串并转为 embed
        if (insert is String && insert.trimLeft().startsWith('{') && insert.contains('"mode":"mindmap"')) {
          result.add({
            'insert': {'mindmap': insert.trim()},
          });
          continue;
        }
        // 自动将旧版 code-block 连续行聚合为代码块嵌入组件
        final attrs = op['attributes'];
        if (attrs is Map && attrs['code-block'] == true) {
          final codeLines = <String>[];
          if (insert is String && insert != '\n') {
            codeLines.add(insert);
          }
          while (i + 1 < deltaList.length) {
            final nextOp = deltaList[i + 1];
            if (nextOp is Map<String, dynamic> &&
                nextOp['attributes'] is Map &&
                nextOp['attributes']['code-block'] == true) {
              final nextIns = nextOp['insert'];
              if (nextIns is String && nextIns != '\n') {
                codeLines.add(nextIns);
              }
              i++;
            } else {
              break;
            }
          }
          final fullCode = codeLines.join('\n');
          result.add({
            'insert': {
              'code_block': jsonEncode({
                'code': fullCode,
                'language': 'plaintext',
              }),
            },
          });
          result.add({'insert': '\n'});
          continue;
        }
      }
      result.add(op);
    }
    return result;
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

  void _insertCodeBlock() {
    if (widget.note == null || _quillCtrl == null) return;
    final index = _quillCtrl!.selection.baseOffset;
    final data = jsonEncode({
      'code': '// 请在此处输入代码\n',
      'language': 'dart',
    });
    _quillCtrl!.document.insert(index, BlockEmbed('code_block', data));
    _quillCtrl!.updateSelection(
      TextSelection.collapsed(offset: index + 1),
      ChangeSource.local,
    );
    _scheduleBodySave();
  }

  Future<void> _handlePaste() async {
    if (widget.note == null || _quillCtrl == null) return;

    // 1. 检测 macOS 系统剪贴板中是否存在位图图片数据
    final tempImagePath = '/tmp/v8_clipboard_paste_${DateTime.now().millisecondsSinceEpoch}.png';
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
          try { await f.delete(); } catch (_) {}

          final index = _quillCtrl!.selection.baseOffset;
          _quillCtrl!.document.insert(index, BlockEmbed.image(savedPath));
          _quillCtrl!.updateSelection(
            TextSelection.collapsed(offset: index + 1),
            ChangeSource.local,
          );
          _scheduleBodySave();
          return;
        }
      }
    } catch (e) {
      debugPrint('Clipboard image check error: $e');
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
            mime: _getMimeType(ext.replaceFirst('.', '')),
          );
          final index = _quillCtrl!.selection.baseOffset;
          _quillCtrl!.document.insert(index, BlockEmbed.image(savedPath));
          _quillCtrl!.updateSelection(
            TextSelection.collapsed(offset: index + 1),
            ChangeSource.local,
          );
          _scheduleBodySave();
          return;
        }
      }

      // 3. 普通文本粘贴
      final index = _quillCtrl!.selection.baseOffset;
      _quillCtrl!.document.insert(index, clipData!.text!);
      _quillCtrl!.updateSelection(
        TextSelection.collapsed(offset: index + clipData.text!.length),
        ChangeSource.local,
      );
      _scheduleBodySave();
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _handlePaste,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _handlePaste,
      },
      child: Theme(
      data: ThemeData.light().copyWith(
        canvasColor: const Color(0xFFFAFAFA),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          surface: Color(0xFFFAFAFA),
          onSurface: Color(0xFF1E293B),
          primary: Color(0xFF2563EB),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFF2563EB),
          selectionColor: Color(0x66BFDBFE), // 半透明选区高亮
          selectionHandleColor: Color(0xFF2563EB),
        ),
      ),
      child: Column(
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
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAFA),
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: QuillSimpleToolbar(
                  controller: _quillCtrl!,
                  config: const QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    toolbarSize: 32,
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showStrikeThrough: true,
                    showHeaderStyle: true,
                    showListCheck: true,        // 开启待办事项 Checkbox
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
                    buttonOptions: QuillSimpleToolbarButtonOptions(
                      base: QuillToolbarBaseButtonOptions(
                        iconSize: 16,
                        iconButtonFactor: 1.15,
                        iconTheme: QuillIconTheme(
                          iconButtonUnselectedData: IconButtonData(
                            color: Color(0xFF475569),
                          ),
                          iconButtonSelectedData: IconButtonData(
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, indent: 8, endIndent: 8, color: Color(0xFFE5E7EB)),
              IconButton(
                icon: const Icon(Icons.code_rounded, size: 18, color: Color(0xFF4B5563)),
                onPressed: _insertCodeBlock,
                tooltip: '插入代码块',
                splashRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              IconButton(
                icon: const Icon(Icons.image_outlined, size: 18, color: Color(0xFF4B5563)),
                onPressed: _insertImage,
                tooltip: '插入图片',
                splashRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    embedBuilders: [
                      NoteImageEmbedBuilder(
                        quillController: _quillCtrl,
                        onSave: _scheduleBodySave,
                      ),
                      NoteCodeBlockEmbedBuilder(
                        quillController: _quillCtrl,
                        onSave: _scheduleBodySave,
                      ),
                      NoteMindMapEmbedBuilder(
                        quillController: _quillCtrl,
                        onSave: _scheduleBodySave,
                      ),
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
    ),
  ),
);
}
}

// =============================================================================
// Enhanced Embed Builders: Image, Code Block, Mind Map
// =============================================================================

/// 1. 高级交互式图片嵌入组件（支持选中边框、拖拽缩放、快捷预设尺寸、右键菜单与 SVG 渲染）
class NoteImageEmbedBuilder extends EmbedBuilder {
  final QuillController? quillController;
  final VoidCallback? onSave;

  const NoteImageEmbedBuilder({
    this.quillController,
    this.onSave,
  });

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return _NoteImageWidget(
      embedContext: embedContext,
      quillController: quillController,
      onSave: onSave,
    );
  }
}

class _NoteImageWidget extends StatefulWidget {
  final EmbedContext embedContext;
  final QuillController? quillController;
  final VoidCallback? onSave;

  const _NoteImageWidget({
    required this.embedContext,
    this.quillController,
    this.onSave,
  });

  @override
  State<_NoteImageWidget> createState() => _NoteImageWidgetState();
}

class _NoteImageWidgetState extends State<_NoteImageWidget> {
  bool _isSelected = false;
  double? _customWidth;

  @override
  Widget build(BuildContext context) {
    final dynamic data = widget.embedContext.node.value.data;
    final imageSource = data is String ? data : '';
    if (imageSource.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSvg = imageSource.toLowerCase().endsWith('.svg');

    Widget imageWidget;
    if (isSvg) {
      final file = File(imageSource);
      if (file.existsSync()) {
        imageWidget = SvgPicture.file(
          file,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      } else {
        imageWidget = _buildErrorPlaceholder(imageSource);
      }
    } else if (imageSource.startsWith('http://') || imageSource.startsWith('https://')) {
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

    return GestureDetector(
      onTap: () => setState(() => _isSelected = !_isSelected),
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition, imageSource),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选中操作浮条（预设比例与快捷功能）
            if (_isSelected)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _presetButton('25%', () => setState(() => _customWidth = 200)),
                    _presetButton('50%', () => setState(() => _customWidth = 380)),
                    _presetButton('75%', () => setState(() => _customWidth = 550)),
                    _presetButton('100%', () => setState(() => _customWidth = 750)),
                    _presetButton('自适应', () => setState(() => _customWidth = null)),
                    const SizedBox(height: 12, child: VerticalDivider(width: 8, color: Colors.white24)),
                    InkWell(
                      onTap: () => _copyImage(imageSource),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('复制', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _cutImage(imageSource),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('剪切', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _deleteImage(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('删除', style: TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),

            // 主图片区域与右侧拖拽手柄
            Stack(
              clipBehavior: Clip.none,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _customWidth ?? 750,
                    maxHeight: 520,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                        width: _isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: imageWidget,
                    ),
                  ),
                ),

                // 右边缘拖拽手柄
                if (_isSelected)
                  Positioned(
                    right: -10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final cur = _customWidth ?? 500;
                            _customWidth = (cur + details.delta.dx).clamp(150.0, 1000.0);
                          });
                        },
                        child: Container(
                          width: 16,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.drag_indicator, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11)),
      ),
    );
  }

  void _copyImage(String source) {
    Clipboard.setData(ClipboardData(text: source));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制图片路径到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  void _cutImage(String source) {
    _copyImage(source);
    _deleteImage();
  }

  void _deleteImage() {
    final offset = widget.embedContext.node.documentOffset;
    widget.quillController?.document.delete(offset, 1);
    widget.onSave?.call();
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPos, String source) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制图片')),
        PopupMenuItem(value: 'cut', child: Text('剪切图片')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'w25', child: Text('比例 25%')),
        PopupMenuItem(value: 'w50', child: Text('比例 50%')),
        PopupMenuItem(value: 'w75', child: Text('比例 75%')),
        PopupMenuItem(value: 'w100', child: Text('比例 100%')),
        PopupMenuItem(value: 'w_auto', child: Text('自适应原始大小')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('删除图片', style: TextStyle(color: AppTheme.error))),
      ],
    );

    if (result == null) return;
    switch (result) {
      case 'copy': _copyImage(source); break;
      case 'cut': _cutImage(source); break;
      case 'w25': setState(() => _customWidth = 200); break;
      case 'w50': setState(() => _customWidth = 380); break;
      case 'w75': setState(() => _customWidth = 550); break;
      case 'w100': setState(() => _customWidth = 750); break;
      case 'w_auto': setState(() => _customWidth = null); break;
      case 'delete': _deleteImage(); break;
    }
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

/// 2. 业界标准代码块嵌入组件（语言选择、语法高亮、自动格式化、行号显示与一键复制）
class NoteCodeBlockEmbedBuilder extends EmbedBuilder {
  final QuillController? quillController;
  final VoidCallback? onSave;

  const NoteCodeBlockEmbedBuilder({
    this.quillController,
    this.onSave,
  });

  @override
  String get key => 'code_block';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return _NoteCodeBlockWidget(
      embedContext: embedContext,
      quillController: quillController,
      onSave: onSave,
    );
  }
}

class _NoteCodeBlockWidget extends StatefulWidget {
  final EmbedContext embedContext;
  final QuillController? quillController;
  final VoidCallback? onSave;

  const _NoteCodeBlockWidget({
    required this.embedContext,
    this.quillController,
    this.onSave,
  });

  @override
  State<_NoteCodeBlockWidget> createState() => _NoteCodeBlockWidgetState();
}

class _NoteCodeBlockWidgetState extends State<_NoteCodeBlockWidget> {
  late String _code;
  late String _language;
  bool _isEditing = false;
  bool _copied = false;
  late TextEditingController _textCtrl;

  static const List<String> _languages = [
    'plaintext', 'dart', 'python', 'javascript', 'typescript',
    'java', 'c', 'cpp', 'go', 'rust', 'html', 'css',
    'sql', 'bash', 'json', 'yaml', 'markdown',
  ];

  @override
  void initState() {
    super.initState();
    _parseData();
    _textCtrl = TextEditingController(text: _code);
  }

  void _parseData() {
    final raw = widget.embedContext.node.value.data;
    if (raw is String) {
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        _code = parsed['code'] as String? ?? '';
        _language = parsed['language'] as String? ?? 'plaintext';
      } catch (_) {
        _code = raw;
        _language = 'plaintext';
      }
    } else if (raw is Map) {
      _code = raw['code']?.toString() ?? '';
      _language = raw['language']?.toString() ?? 'plaintext';
    } else {
      _code = '';
      _language = 'plaintext';
    }
  }

  void _persist() {
    final offset = widget.embedContext.node.documentOffset;
    final payload = jsonEncode({
      'code': _code,
      'language': _language,
    });
    widget.quillController?.document.replace(offset, 1, BlockEmbed('code_block', payload));
    widget.onSave?.call();
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _formatCode() {
    if (_language == 'json') {
      try {
        final parsed = jsonDecode(_code);
        final pretty = const JsonEncoder.withIndent('  ').convert(parsed);
        setState(() {
          _code = pretty;
          _textCtrl.text = pretty;
        });
        _persist();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON 格式化成功'), duration: Duration(seconds: 1)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON 格式错误: $e'), duration: const Duration(seconds: 2)),
        );
      }
    } else {
      final lines = _code.split('\n').map((l) => l.trimRight()).toList();
      setState(() {
        _code = lines.join('\n').trim();
        _textCtrl.text = _code;
      });
      _persist();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清除行尾空白字符'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _deleteBlock() {
    final offset = widget.embedContext.node.documentOffset;
    widget.quillController?.document.delete(offset, 1);
    widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _code.split('\n');
    final lineCount = lines.isEmpty ? 1 : lines.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 代码块顶部工具栏
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                // 语言切换下拉菜单
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _languages.contains(_language) ? _language : 'plaintext',
                    icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF64748B)),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _language = val);
                        _persist();
                      }
                    },
                    items: _languages.map((lang) => DropdownMenuItem(
                      value: lang,
                      child: Text(lang.toUpperCase()),
                    )).toList(),
                  ),
                ),

                const Spacer(),

                // 格式化按钮
                TextButton.icon(
                  onPressed: _formatCode,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14, color: Color(0xFF475569)),
                  label: const Text('格式化', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),

                // 复制按钮
                TextButton.icon(
                  onPressed: _copyCode,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 14,
                    color: _copied ? const Color(0xFF16A34A) : const Color(0xFF475569),
                  ),
                  label: Text(
                    _copied ? '已复制' : '复制',
                    style: TextStyle(
                      fontSize: 12,
                      color: _copied ? const Color(0xFF16A34A) : const Color(0xFF475569),
                    ),
                  ),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),

                // 编辑/完成切换按钮
                IconButton(
                  icon: Icon(_isEditing ? Icons.check_circle_outline : Icons.edit_outlined, size: 16, color: AppTheme.accent),
                  tooltip: _isEditing ? '完成编辑' : '直接编辑代码',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    if (_isEditing) {
                      setState(() {
                        _code = _textCtrl.text;
                        _isEditing = false;
                      });
                      _persist();
                    } else {
                      setState(() {
                        _textCtrl.text = _code;
                        _isEditing = true;
                      });
                    }
                  },
                ),

                // 删除按钮
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: '删除代码块',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _deleteBlock,
                ),
              ],
            ),
          ),

          // 代码区域：编辑模式 vs 高亮展示模式
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _textCtrl,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF0F172A),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: '在此输入或粘贴代码...',
                ),
                autofocus: true,
              ),
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 行号栏
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(7)),
                      border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        lineCount,
                        (index) => Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 语法高亮展示区
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: HighlightView(
                        _code.isEmpty ? '// 暂无代码内容' : _code,
                        language: _language,
                        theme: githubTheme,
                        padding: const EdgeInsets.all(12),
                        textStyle: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 3. 原生思维导图嵌入组件（高清矢量 SVG 无损缩放、平移浏览与结构化大纲双模式展示）
class NoteMindMapEmbedBuilder extends EmbedBuilder {
  final QuillController? quillController;
  final VoidCallback? onSave;

  const NoteMindMapEmbedBuilder({
    this.quillController,
    this.onSave,
  });

  @override
  String get key => 'mindmap';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return _NoteMindMapWidget(
      embedContext: embedContext,
      quillController: quillController,
      onSave: onSave,
    );
  }
}

class _NoteMindMapWidget extends StatefulWidget {
  final EmbedContext embedContext;
  final QuillController? quillController;
  final VoidCallback? onSave;

  const _NoteMindMapWidget({
    required this.embedContext,
    this.quillController,
    this.onSave,
  });

  @override
  State<_NoteMindMapWidget> createState() => _NoteMindMapWidgetState();
}

class _NoteMindMapWidgetState extends State<_NoteMindMapWidget> {
  String _title = '思维导图';
  String? _svgPath;
  Map<String, dynamic>? _tree;
  bool _showOutline = false;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  void _parseData() {
    final raw = widget.embedContext.node.value.data;
    if (raw is Map) {
      _title = raw['title']?.toString() ?? '思维导图';
      _svgPath = raw['svg_path']?.toString();
      _tree = raw['tree'] is Map ? (raw['tree'] as Map).cast<String, dynamic>() : null;
    } else if (raw is String) {
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        _title = parsed['title'] as String? ?? parsed['name'] as String? ?? '思维导图';
        _svgPath = parsed['svg_path'] as String?;
        if (parsed.containsKey('tree') && parsed['tree'] is Map) {
          _tree = (parsed['tree'] as Map).cast<String, dynamic>();
        } else if (parsed.containsKey('mode') && parsed['mode'] == 'mindmap') {
          _tree = parsed;
        }
      } catch (_) {
        _title = '思维导图';
      }
    }
  }

  void _zoomIn() {
    _transformCtrl.value = _transformCtrl.value * Matrix4.diagonal3Values(1.25, 1.25, 1.0);
  }

  void _zoomOut() {
    _transformCtrl.value = _transformCtrl.value * Matrix4.diagonal3Values(0.8, 0.8, 1.0);
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
  }

  Future<void> _exportSvg() async {
    if (_svgPath == null) return;
    final file = File(_svgPath!);
    if (!file.existsSync()) return;

    final output = await FilePicker.platform.saveFile(
      dialogTitle: '导出思维导图 SVG 矢量文件',
      fileName: '$_title.svg',
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );
    if (output != null) {
      await file.copy(output);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功导出 SVG 至: $output')),
        );
      }
    }
  }

  void _deleteBlock() {
    final offset = widget.embedContext.node.documentOffset;
    widget.quillController?.document.delete(offset, 1);
    widget.onSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasSvg = _svgPath != null && File(_svgPath!).existsSync();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部标头与控制栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_rounded, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Text('思维导图', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
                ),

                const Spacer(),

                // 视图模式切换：矢量导图 vs 结构大纲
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      _tabButton('🗺️ 导图', !_showOutline, () => setState(() => _showOutline = false)),
                      _tabButton('📋 大纲', _showOutline, () => setState(() => _showOutline = true)),
                    ],
                  ),
                ),

                if (!_showOutline && hasSvg) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.zoom_in_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '放大',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _zoomIn,
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '缩小',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _zoomOut,
                  ),
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '重置比例',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _resetZoom,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '导出矢量 SVG',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _exportSvg,
                  ),
                ],

                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                  tooltip: '删除导图',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _deleteBlock,
                ),
              ],
            ),
          ),

          // 主体展示：高清无损矢量导图 或 结构化大纲
          if (!_showOutline && hasSvg)
            Container(
              height: 480,
              color: Colors.white,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 0.1,
                  maxScale: 6.0,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: Center(
                    child: SvgPicture.file(
                      File(_svgPath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 420,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: _tree != null
                  ? SingleChildScrollView(child: _buildTreeNode(_tree!, 0))
                  : Center(
                      child: Text(
                        hasSvg ? '切换到大纲模式' : '导图矢量附件尚未同步，暂无大纲结构数据',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: active ? const [BoxShadow(color: Colors.black12, blurRadius: 2)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? const Color(0xFF1E293B) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeNode(Map<String, dynamic> node, int level) {
    final rawName = node['name']?.toString() ?? '';
    final rawHtml = node['html']?.toString() ?? '';
    final name = rawName.isNotEmpty ? rawName : rawHtml.replaceAll(RegExp(r'<[^>]+>'), '');
    final children = (node['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return Padding(
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                level == 0 ? Icons.folder_open_rounded : Icons.subdirectory_arrow_right_rounded,
                size: 16,
                color: level == 0 ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: level == 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: level == 0 ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  name.isEmpty ? '节点' : name,
                  style: TextStyle(
                    fontSize: level == 0 ? 14 : 12,
                    fontWeight: level == 0 ? FontWeight.bold : FontWeight.w500,
                    color: level == 0 ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          for (final ch in children) _buildTreeNode(ch, level + 1),
        ],
      ),
    );
  }
}

/// 4. 自定义未知 Embed 兜底渲染器
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

