import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../../theme/app_theme.dart';
import '../note_database.dart';
import '../note_store.dart';

/// 笔记编辑器组件
class NoteEditor extends StatefulWidget {
  final Note? note;
  final VoidCallback? onSaved;

  const NoteEditor({super.key, this.note, this.onSaved});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleCtrl;
  QuillController? _quillCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _initEditor();
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

    // Auto-save listener
    _quillCtrl!.document.changes.listen((_) => _scheduleAutoSave());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _quillCtrl?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note?.id != widget.note?.id) {
      _quillCtrl?.dispose();
      _titleCtrl.text = widget.note?.title ?? '';
      _initEditor();
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-save
  // ---------------------------------------------------------------------------

  bool _saveScheduled = false;

  void _scheduleAutoSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future.delayed(const Duration(seconds: 1), () {
      _saveScheduled = false;
      _save();
    });
  }

  Future<void> _save() async {
    if (_isSaving || widget.note == null) return;
    _isSaving = true;

    try {
      final deltaJson = jsonEncode(_quillCtrl!.document.toDelta().toJson());
      await NoteStore.instance.updateNote(
        id: widget.note!.id,
        title: _titleCtrl.text.isEmpty ? 'Untitled' : _titleCtrl.text,
        deltaJson: deltaJson,
      );
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      _isSaving = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Image insertion
  // ---------------------------------------------------------------------------

  Future<void> _insertImage() async {
    if (widget.note == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final store = NoteStore.instance;

    try {
      // Save to attachments directory
      final localPath = await store.saveAttachment(
        noteId: widget.note!.id,
        sourceFile: file,
        filename: result.files.first.name,
        mime: _getMimeType(result.files.first.extension),
      );

      // Insert image into editor
      final index = _quillCtrl!.selection.baseOffset;
      _quillCtrl!.document.insert(index, BlockEmbed.image(localPath));
      _quillCtrl!.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        ChangeSource.local,
      );
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
            Text('选择或创建一条笔记', style: AppTheme.fontBody.copyWith(color: AppTheme.textTertiary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Title bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: AppTheme.space8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  style: AppTheme.fontTitle.copyWith(fontSize: 18),
                  decoration: const InputDecoration(
                    hintText: 'Note title...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
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

        // Quill toolbar + image button
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
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
                icon: const Icon(Icons.image_outlined, size: 20),
                onPressed: _insertImage,
                tooltip: 'Insert Image',
              ),
            ],
          ),
        ),

        // Editor
        Expanded(
          child: Container(
            color: AppTheme.bgContent,
            padding: const EdgeInsets.all(AppTheme.space16),
            child: QuillEditor.basic(
              controller: _quillCtrl!,
              config: const QuillEditorConfig(
                padding: EdgeInsets.zero,
                autoFocus: false,
                expands: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
