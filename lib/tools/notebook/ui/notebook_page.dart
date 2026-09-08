import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../theme/app_theme.dart';
import '../export_service.dart';
import '../markdown_converter.dart';
import '../note_database.dart';
import '../note_store.dart';
import 'note_editor.dart';

/// 笔记本工具主页面（三栏布局）
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  final NoteStore _store = NoteStore.instance;

  List<Notebook> _notebooks = [];
  List<Tag> _tags = [];
  List<Note> _notes = [];
  Note? _selectedNote;
  String? _selectedNotebookId;
  String? _selectedTagId;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.init();
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      _notebooks = await _store.allNotebooks();
      _tags = await _store.allTags();

      if (_searchQuery.isNotEmpty) {
        _notes = await _store.searchNotes(_searchQuery);
      } else if (_selectedTagId != null) {
        _notes = await _store.notesForTag(_selectedTagId!);
      } else {
        _notes = await _store.notesForNotebook(_selectedNotebookId);
      }

      // If selected note is no longer in list, deselect
      if (_selectedNote != null) {
        final stillExists = _notes.any((n) => n.id == _selectedNote!.id);
        if (!stillExists) _selectedNote = null;
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Notebook actions
  // ---------------------------------------------------------------------------

  Future<void> _createNotebook() async {
    final name = await _showInputDialog('New Notebook', 'Notebook name');
    if (name == null || name.isEmpty) return;
    await _store.createNotebook(name);
    await _refresh();
  }

  Future<void> _deleteNotebook(String id) async {
    final confirm = await _showConfirmDialog('Delete Notebook', 'All notes in this notebook will be moved to the default.');
    if (confirm != true) return;
    await _store.deleteNotebook(id);
    if (_selectedNotebookId == id) _selectedNotebookId = null;
    await _refresh();
  }

  // ---------------------------------------------------------------------------
  // Note actions
  // ---------------------------------------------------------------------------

  Future<void> _createNote() async {
    final id = await _store.createNote(
      title: 'Untitled',
      deltaJson: '[{"insert":"\\n"}]',
      notebookId: _selectedNotebookId,
    );
    await _refresh();
    final note = await _store.noteById(id);
    if (note != null) {
      setState(() => _selectedNote = note);
    }
  }

  Future<void> _deleteNote(String id) async {
    await _store.softDeleteNote(id);
    if (_selectedNote?.id == id) _selectedNote = null;
    await _refresh();
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _importMarkdown() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();
    final title = result.files.first.name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
    final deltaJson = MarkdownConverter.markdownToDelta(content);

    await _store.createNote(
      title: title,
      deltaJson: deltaJson,
      notebookId: _selectedNotebookId,
    );
    await _refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported: $title')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportNote(ExportFormat format) async {
    if (_selectedNote == null) return;

    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Export to...',
    );
    if (outputDir == null) return;

    try {
      final file = await ExportService.instance.exportToFile(
        note: _selectedNote!,
        format: format,
        outputDir: outputDir,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  Future<String?> _showInputDialog(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: Text(message, style: AppTheme.fontBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Row(
        children: [
          // Left: Notebook tree + tags
          _buildLeftPanel(),

          // Divider
          const VerticalDivider(width: 1, color: AppTheme.borderSubtle),

          // Center: Note list
          _buildCenterPanel(),

          // Divider
          const VerticalDivider(width: 1, color: AppTheme.borderSubtle),

          // Right: Editor
          Expanded(child: _buildRightPanel()),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return SizedBox(
      width: 200,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(Icons.note_alt_outlined, size: 18, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                Text('Notebooks', style: AppTheme.fontTitle),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: _createNotebook,
                  tooltip: 'New Notebook',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),

          // All notes
          ListTile(
            dense: true,
            leading: const Icon(Icons.all_inbox_rounded, size: 18),
            title: const Text('All Notes'),
            selected: _selectedNotebookId == null && _selectedTagId == null,
            onTap: () {
              setState(() {
                _selectedNotebookId = null;
                _selectedTagId = null;
              });
              _refresh();
            },
          ),

          // Notebooks
          Expanded(
            child: ListView.builder(
              itemCount: _notebooks.length,
              itemBuilder: (ctx, i) {
                final nb = _notebooks[i];
                return ListTile(
                  dense: true,
                  leading: Text(nb.icon, style: const TextStyle(fontSize: 16)),
                  title: Text(nb.name, style: AppTheme.fontBody, overflow: TextOverflow.ellipsis),
                  selected: _selectedNotebookId == nb.id,
                  onTap: () {
                    setState(() {
                      _selectedNotebookId = nb.id;
                      _selectedTagId = null;
                    });
                    _refresh();
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 14, color: AppTheme.textTertiary),
                    onPressed: () => _deleteNotebook(nb.id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                );
              },
            ),
          ),

          // Tags section
          if (_tags.isNotEmpty) ...[
            const Divider(height: 1, color: AppTheme.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space8),
              child: Text('Tags', style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary)),
            ),
            SizedBox(
              height: 120,
              child: ListView.builder(
                itemCount: _tags.length,
                itemBuilder: (ctx, i) {
                  final tag = _tags[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.label_outline, size: 16),
                    title: Text(tag.name, style: AppTheme.fontBody, overflow: TextOverflow.ellipsis),
                    selected: _selectedTagId == tag.id,
                    onTap: () {
                      setState(() {
                        _selectedTagId = tag.id;
                        _selectedNotebookId = null;
                      });
                      _refresh();
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenterPanel() {
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(AppTheme.space8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: AppTheme.borderRadiusSmall,
                        borderSide: const BorderSide(color: AppTheme.borderSubtle),
                      ),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _refresh();
                    },
                  ),
                ),
                const SizedBox(width: AppTheme.space8),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 20, color: AppTheme.accent),
                  onPressed: _createNote,
                  tooltip: 'New Note',
                ),
              ],
            ),
          ),

          // Note count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space4),
            alignment: Alignment.centerLeft,
            child: Text(
              '${_notes.length} notes',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
            ),
          ),

          // Note list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? Center(
                        child: Text('No notes', style: AppTheme.fontBody.copyWith(color: AppTheme.textTertiary)),
                      )
                    : ListView.builder(
                        itemCount: _notes.length,
                        itemBuilder: (ctx, i) {
                          final note = _notes[i];
                          final isSelected = _selectedNote?.id == note.id;
                          return InkWell(
                            onTap: () => setState(() => _selectedNote = note),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.space12,
                                vertical: AppTheme.space8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.bgSelected : null,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? AppTheme.accent : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (note.isPinned)
                                        const Icon(Icons.push_pin, size: 12, color: AppTheme.accent),
                                      Expanded(
                                        child: Text(
                                          note.title.isEmpty ? 'Untitled' : note.title,
                                          style: AppTheme.fontBody.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _noteSummary(note),
                                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(note.updatedAt),
                                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary, fontSize: 10),
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

  Widget _buildRightPanel() {
    return Column(
      children: [
        // Export bar (visible when a note is selected)
        if (_selectedNote != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  _selectedNote!.title,
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                _buildExportButton('MD', ExportFormat.markdown),
                _buildExportButton('HTML', ExportFormat.html),
                _buildExportButton('PDF', ExportFormat.pdf),
                _buildExportButton('TXT', ExportFormat.plainText),
                const SizedBox(width: AppTheme.space8),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  onPressed: _importMarkdown,
                  tooltip: 'Import Markdown',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.textTertiary),
                  onPressed: () => _deleteNote(_selectedNote!.id),
                  tooltip: 'Delete Note',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),

        // Editor
        Expanded(
          child: NoteEditor(
            note: _selectedNote,
            onSaved: _refresh,
          ),
        ),
      ],
    );
  }

  Widget _buildExportButton(String label, ExportFormat format) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: () => _exportNote(format),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: AppTheme.fontCaption.copyWith(color: AppTheme.accent)),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (dt.year == now.year) {
      return '${dt.month}/${dt.day}';
    }
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  String _noteSummary(Note note) {
    try {
      final ops = jsonDecode(note.deltaJson) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in ops) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
        if (buffer.length >= 120) break;
      }
      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.length > 120 ? '${text.substring(0, 120)}...' : text;
    } catch (_) {
      return '';
    }
  }
}
