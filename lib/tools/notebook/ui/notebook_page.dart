import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../evernote_import_service.dart';
import '../export_service.dart';
import '../markdown_converter.dart';
import '../note_database.dart';
import '../note_store.dart';
import 'note_editor.dart';

/// 笔记本工具主页面（仿印象笔记三栏布局）
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
  bool _isTrashSelected = false;
  String _searchQuery = '';
  bool _isLoading = true;

  // 批量操作多选状态
  bool _isBatchMode = false;
  final Set<String> _selectedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.init();
    await _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      _notebooks = await _store.allNotebooks();
      _tags = await _store.allTags();

      if (_isTrashSelected) {
        _notes = await _store.deletedNotes();
      } else if (_searchQuery.isNotEmpty) {
        _notes = await _store.searchNotes(_searchQuery);
      } else if (_selectedTagId != null) {
        _notes = await _store.notesForTag(_selectedTagId!);
      } else {
        _notes = await _store.notesForNotebook(_selectedNotebookId);
      }

      // If selected note is no longer in list, deselect or sync instance
      if (_selectedNote != null) {
        final currentId = _selectedNote!.id;
        final updated = await _store.noteById(currentId);
        if (updated != null && _notes.any((n) => n.id == currentId)) {
          _selectedNote = updated;
        } else {
          _selectedNote = null;
        }
      }

      // 移除已被删除的已选 ID
      _selectedNoteIds.removeWhere((id) => !_notes.any((n) => n.id == id));
    } catch (e) {
      debugPrint('Refresh error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Batch selection actions
  // ---------------------------------------------------------------------------

  void _toggleBatchMode() {
    setState(() {
      _isBatchMode = !_isBatchMode;
      _selectedNoteIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedNoteIds.length == _notes.length) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds.clear();
        _selectedNoteIds.addAll(_notes.map((n) => n.id));
      }
    });
  }

  void _toggleSelectNote(String id) {
    setState(() {
      if (_selectedNoteIds.contains(id)) {
        _selectedNoteIds.remove(id);
      } else {
        _selectedNoteIds.add(id);
      }
    });
  }

  Future<void> _batchDeleteSelected() async {
    if (_selectedNoteIds.isEmpty) return;
    final count = _selectedNoteIds.length;
    if (_isTrashSelected) {
      final confirm = await _showConfirmDialog(
        '彻底粉碎笔记',
        '确定彻底粉碎所选的 $count 篇笔记及其附件吗？此操作不可逆！',
      );
      if (confirm != true) return;
      await _store.batchPermanentlyDeleteNotes(_selectedNoteIds.toList());
    } else {
      final confirm = await _showConfirmDialog(
        '批量移入废纸篓',
        '确定将所选的 $count 篇笔记移入废纸篓吗？',
      );
      if (confirm != true) return;
      await _store.batchSoftDeleteNotes(_selectedNoteIds.toList());
    }

    if (_selectedNote != null && _selectedNoteIds.contains(_selectedNote!.id)) {
      _selectedNote = null;
    }
    _selectedNoteIds.clear();
    _isBatchMode = false;
    await _refresh(silent: true);
  }

  Future<void> _batchRestoreSelected() async {
    if (_selectedNoteIds.isEmpty) return;
    final count = _selectedNoteIds.length;
    final confirm = await _showConfirmDialog(
      '批量恢复笔记',
      '确定将所选的 $count 篇笔记恢复回笔记本吗？',
    );
    if (confirm != true) return;
    await _store.batchRestoreNotes(_selectedNoteIds.toList());
    _selectedNoteIds.clear();
    _isBatchMode = false;
    await _refresh(silent: true);
  }

  // ---------------------------------------------------------------------------
  // Notebook actions
  // ---------------------------------------------------------------------------

  Future<void> _createNotebook() async {
    final name = await _showInputDialog('新建笔记本', '请输入笔记本名称');
    if (name == null || name.trim().isEmpty) return;
    await _store.createNotebook(name.trim());
    await _refresh(silent: true);
  }

  Future<void> _renameNotebook(Notebook nb) async {
    final name = await _showInputDialog('重命名笔记本', '笔记本名称', initialValue: nb.name);
    if (name == null || name.trim().isEmpty) return;
    await _store.renameNotebook(nb.id, name.trim());
    await _refresh(silent: true);
  }

  Future<void> _deleteNotebook(String id) async {
    final confirm = await _showConfirmDialog(
      '删除笔记本',
      '确定删除此笔记本吗？该笔记本内的笔记不会丢失，将被移至默认笔记本。',
    );
    if (confirm != true) return;
    await _store.deleteNotebook(id);
    if (_selectedNotebookId == id) _selectedNotebookId = null;
    await _refresh(silent: true);
  }

  // ---------------------------------------------------------------------------
  // Note actions
  // ---------------------------------------------------------------------------

  Future<void> _createNote() async {
    _isTrashSelected = false;
    _isBatchMode = false;
    _selectedNoteIds.clear();
    final id = await _store.createNote(
      title: '无标题笔记',
      deltaJson: '[{"insert":"\\n"}]',
      notebookId: _selectedNotebookId,
    );
    await _refresh(silent: true);
    final note = await _store.noteById(id);
    if (note != null) {
      setState(() => _selectedNote = note);
    }
  }

  Future<void> _deleteNote(String id) async {
    await _store.softDeleteNote(id);
    if (_selectedNote?.id == id) _selectedNote = null;
    await _refresh(silent: true);
  }

  Future<void> _restoreNote(String id) async {
    await _store.restoreNote(id);
    await _refresh(silent: true);
    final note = await _store.noteById(id);
    if (note != null) setState(() => _selectedNote = note);
  }

  Future<void> _permanentlyDeleteNote(String id) async {
    final confirm = await _showConfirmDialog(
      '彻底删除',
      '确定彻底粉碎该笔记及其附件吗？此操作无法撤销。',
    );
    if (confirm != true) return;
    await _store.permanentlyDeleteNote(id);
    if (_selectedNote?.id == id) _selectedNote = null;
    await _refresh(silent: true);
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _importMarkdown() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    int successCount = 0;
    for (final picked in result.files) {
      if (picked.path == null) continue;
      final file = File(picked.path!);
      final content = await file.readAsString();
      final title = picked.name.replaceAll(RegExp(r'\.(md|markdown|txt)$'), '');
      final deltaJson = MarkdownConverter.markdownToDelta(content);

      await _store.createNote(
        title: title,
        deltaJson: deltaJson,
        notebookId: _selectedNotebookId,
      );
      successCount++;
    }

    await _refresh(silent: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $successCount 篇 Markdown 笔记')),
      );
    }
  }

  Future<void> _showEvernoteImportDialog() async {
    // 异步探测本机客户端状态
    final localInfo = await EvernoteImportService.instance.detectLocalEvernote();

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('导入印象笔记', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请选择导入方式：',
              style: AppTheme.fontBody,
            ),
            const SizedBox(height: AppTheme.space16),
            if (localInfo.detected) ...[
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusSmall),
                tileColor: AppTheme.accent.withValues(alpha: 0.12),
                leading: const Icon(Icons.flash_on, color: AppTheme.accent),
                title: Text(
                  '从本机客户端一键全量迁移 (${localInfo.noteCount} 篇 · ${localInfo.notebookCount} 个笔记本)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent),
                ),
                subtitle: const Text('免密直读本机缓存，秒级还原全部笔记本分类、未加密正文与附件'),
                onTap: () => Navigator.pop(ctx, 'local_client'),
              ),
              const SizedBox(height: AppTheme.space8),
            ],
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusSmall),
              tileColor: AppTheme.bgInput,
              leading: const Icon(Icons.file_open_outlined, color: AppTheme.textPrimary),
              title: const Text('从本地 .notes / .enex 备份文件导入'),
              subtitle: const Text('自动提取文件名作为所属笔记本，并智能匹配本机明文正文'),
              onTap: () => Navigator.pop(ctx, 'notes_file'),
            ),
            const SizedBox(height: AppTheme.space8),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusSmall),
              tileColor: AppTheme.bgInput,
              leading: const Icon(Icons.cloud_sync_outlined, color: AppTheme.info),
              title: const Text('通过印象笔记 API 在线拉取'),
              subtitle: const Text('使用钥匙串授权 Token 远程获取笔记正文'),
              onTap: () => Navigator.pop(ctx, 'api'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (choice == 'local_client') {
      await _importFromLocalClient();
    } else if (choice == 'notes_file') {
      await _importFromNotesFile();
    } else if (choice == 'api') {
      await _importFromEvernoteApi();
    }
  }

  Future<void> _importFromLocalClient() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ImportProgressDialog(),
    );

    try {
      final importResult = await EvernoteImportService.instance.importFromLocalClient(
        onProgress: (current, total, title) {
          debugPrint('[Import Local] $current/$total: $title');
        },
      );

      if (mounted) {
        Navigator.pop(context);
        await _refresh();
        _showImportResult(importResult);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本机迁移失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _importFromEvernoteApi() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ImportProgressDialog(),
    );

    try {
      final importResult = await EvernoteImportService.instance.importFromApi(
        onProgress: (current, total, title) {
          debugPrint('[Import API] $current/$total: $title');
        },
      );

      if (mounted) {
        Navigator.pop(context);
        await _refresh();
        _showImportResult(importResult);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _importFromNotesFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['notes', 'enex'],
      dialogTitle: '选择印象笔记备份文件 (.notes / .enex)',
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ImportProgressDialog(),
    );

    try {
      final importResult = await EvernoteImportService.instance.importFromNotesFile(
        filePath: result.files.first.path!,
        onProgress: (current, total, title) {
          debugPrint('[Import .notes] $current/$total: $title');
        },
      );

      if (mounted) {
        Navigator.pop(context);
        await _refresh(silent: true);
        _showImportResult(importResult);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析导入失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  void _showImportResult(ImportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('印象笔记导入完成', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总笔记数: ${result.total} 篇'),
            const SizedBox(height: 4),
            Text('成功导入: ${result.imported} 篇', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)),
            if (result.failed > 0) ...[
              const SizedBox(height: 4),
              Text('导入失败: ${result.failed} 篇', style: const TextStyle(color: AppTheme.error)),
            ],
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space8),
              const Text('错误摘要:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 120,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.errors.take(20).map((e) => Text(
                      '• $e',
                      style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportNote(ExportFormat format) async {
    if (_selectedNote == null) return;

    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
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
          SnackBar(content: Text('已成功导出: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dialog helpers
  // ---------------------------------------------------------------------------

  Future<String?> _showInputDialog(String title, String hint, {String? initialValue}) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint, isDense: true),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: Text(message, style: AppTheme.fontBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build Layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: Row(
        children: [
          // Left: Notebook tree + tags + 常驻导入 (深色导航列)
          _buildLeftPanel(),

          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Center: Note list (经典浅灰列表列)
          _buildCenterPanel(),

          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Right: Editor (纯白纸质编辑器列)
          Expanded(child: _buildRightPanel()),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: 220,
      color: AppTheme.bgSidebar,
      child: Column(
        children: [
          // macOS 沉浸式无边框窗口顶部预留拖拽与标头
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 20, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                Text('笔记本', style: AppTheme.fontTitle.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // All notes & Trash
          ListTile(
            dense: true,
            leading: const Icon(Icons.all_inbox_rounded, size: 18),
            title: const Text('全部笔记'),
            selected: !_isTrashSelected && _selectedNotebookId == null && _selectedTagId == null,
            onTap: () {
              setState(() {
                _isTrashSelected = false;
                _selectedNotebookId = null;
                _selectedTagId = null;
                _isBatchMode = false;
                _selectedNoteIds.clear();
              });
              _refresh(silent: true);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_outline, size: 18, color: AppTheme.warning),
            title: const Text('废纸篓'),
            selected: _isTrashSelected,
            onTap: () {
              setState(() {
                _isTrashSelected = true;
                _selectedNotebookId = null;
                _selectedTagId = null;
                _isBatchMode = false;
                _selectedNoteIds.clear();
              });
              _refresh(silent: true);
            },
          ),

          const Divider(height: 1, color: AppTheme.borderSubtle),

          // Notebooks section header
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 4),
            child: Row(
              children: [
                Text(
                  '笔记本',
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  onPressed: _createNotebook,
                  tooltip: '新建笔记本',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),

          // Notebooks list
          Expanded(
            flex: 3,
            child: ListView.builder(
              itemCount: _notebooks.length,
              itemBuilder: (ctx, i) {
                final nb = _notebooks[i];
                final isSelected = !_isTrashSelected && _selectedNotebookId == nb.id;
                return ListTile(
                  dense: true,
                  leading: Text(nb.icon, style: const TextStyle(fontSize: 16)),
                  title: Text(nb.name, style: AppTheme.fontBody, overflow: TextOverflow.ellipsis),
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      _isTrashSelected = false;
                      _selectedNotebookId = nb.id;
                      _selectedTagId = null;
                      _isBatchMode = false;
                      _selectedNoteIds.clear();
                    });
                    _refresh(silent: true);
                  },
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 14, color: AppTheme.textTertiary),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'rename') {
                        _renameNotebook(nb);
                      } else if (v == 'delete') {
                        _deleteNotebook(nb.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'rename', child: Text('重命名')),
                      const PopupMenuItem(value: 'delete', child: Text('删除笔记本', style: TextStyle(color: AppTheme.error))),
                    ],
                  ),
                );
              },
            ),
          ),

          // Tags section
          if (_tags.isNotEmpty) ...[
            const Divider(height: 1, color: AppTheme.borderSubtle),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('标签', style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary, fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: _tags.length,
                itemBuilder: (ctx, i) {
                  final tag = _tags[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.label_outline, size: 16),
                    title: Text('#${tag.name}', style: AppTheme.fontBody, overflow: TextOverflow.ellipsis),
                    selected: !_isTrashSelected && _selectedTagId == tag.id,
                    onTap: () {
                      setState(() {
                        _isTrashSelected = false;
                        _selectedTagId = tag.id;
                        _selectedNotebookId = null;
                        _isBatchMode = false;
                        _selectedNoteIds.clear();
                      });
                      _refresh(silent: true);
                    },
                  );
                },
              ),
            ),
          ],

          const Divider(height: 1, color: AppTheme.borderSubtle),

          // 常驻导入入口
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: const Text('导入印象笔记', style: TextStyle(fontSize: 12)),
                    onPressed: _showEvernoteImportDialog,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppTheme.borderSubtle),
                    ),
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('导入 Markdown', style: TextStyle(fontSize: 12)),
                    onPressed: _importMarkdown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel() {
    return Container(
      width: 320,
      color: const Color(0xFFF5F6F8),
      child: Column(
        children: [
          // Search & New Note & Batch Toggle
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      hintText: _isTrashSelected ? '搜索废纸篓...' : '搜索笔记...',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF64748B)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      _searchQuery = v;
                      _refresh(silent: true);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _isBatchMode ? Icons.checklist_rtl_rounded : Icons.checklist_rounded,
                    size: 20,
                    color: _isBatchMode ? AppTheme.accent : const Color(0xFF64748B),
                  ),
                  onPressed: _toggleBatchMode,
                  tooltip: _isBatchMode ? '退出批量选择' : '批量选择',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                if (!_isTrashSelected) ...[
                  IconButton(
                    icon: const Icon(Icons.add_circle, size: 22, color: AppTheme.accent),
                    onPressed: _createNote,
                    tooltip: '新建笔记',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ],
            ),
          ),

          // Count banner / Batch Toolbar
          if (!_isBatchMode)
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Text(
                _isTrashSelected ? '废纸篓：${_notes.length} 项' : '共 ${_notes.length} 篇笔记',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            )
          else
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                border: Border(bottom: BorderSide(color: Color(0xFFBFDBFE))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Checkbox(
                      value: _notes.isNotEmpty && _selectedNoteIds.length == _notes.length,
                      onChanged: (_) => _toggleSelectAll(),
                      activeColor: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '全选 (${_selectedNoteIds.length}/${_notes.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                  const Spacer(),
                  if (_isTrashSelected)
                    TextButton.icon(
                      icon: const Icon(Icons.restore_from_trash, size: 15),
                      label: const Text('恢复', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _selectedNoteIds.isNotEmpty ? _batchRestoreSelected : null,
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: Text(_isTrashSelected ? '粉碎' : '删除', style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _selectedNoteIds.isNotEmpty ? _batchDeleteSelected : null,
                  ),
                ],
              ),
            ),

          // Notes List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.note_alt_outlined,
                              size: 40,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isTrashSelected ? '废纸篓是空的' : '暂无笔记，点击上方 + 新建',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _notes.length,
                        itemBuilder: (ctx, i) {
                          final note = _notes[i];
                          final isSelected = !_isBatchMode && _selectedNote?.id == note.id;
                          final isChecked = _selectedNoteIds.contains(note.id);
                          return InkWell(
                            onTap: () {
                              if (_isBatchMode) {
                                _toggleSelectNote(note.id);
                              } else {
                                setState(() => _selectedNote = note);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isChecked
                                    ? const Color(0xFFEFF6FF)
                                    : (isSelected ? const Color(0xFFE8F0FE) : const Color(0xFFFFFFFF)),
                                border: Border(
                                  bottom: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
                                  left: BorderSide(
                                    color: isSelected
                                        ? AppTheme.accent
                                        : (isChecked ? const Color(0xFF3B82F6) : Colors.transparent),
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isBatchMode)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8, top: 2),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: Checkbox(
                                          value: isChecked,
                                          onChanged: (_) => _toggleSelectNote(note.id),
                                          activeColor: AppTheme.accent,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (note.isPinned)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 4),
                                                child: Icon(Icons.push_pin, size: 12, color: AppTheme.accent),
                                              ),
                                            Expanded(
                                              child: Text(
                                                note.title.isEmpty ? '无标题笔记' : note.title,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF0F172A),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _noteSummary(note),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                            height: 1.35,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatDate(note.updatedAt),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
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

  Widget _buildRightPanel() {
    return Container(
      color: const Color(0xFFFFFFFF),
      child: Column(
        children: [
          // Top Export Bar
          if (_selectedNote != null)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedNote!.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text('导出：', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  _buildExportButton('MD', ExportFormat.markdown),
                  _buildExportButton('HTML', ExportFormat.html),
                  _buildExportButton('PDF', ExportFormat.pdf),
                  _buildExportButton('TXT', ExportFormat.plainText),
                ],
              ),
            ),

          // Note Editor
          Expanded(
            child: NoteEditor(
              key: ValueKey(_selectedNote?.id ?? 'empty'),
              note: _selectedNote,
              onSaved: () => _refresh(silent: true),
              onTogglePin: () => _refresh(silent: true),
              onDelete: () => _deleteNote(_selectedNote!.id),
              onRestore: () => _restoreNote(_selectedNote!.id),
              onPermanentDelete: () => _permanentlyDeleteNote(_selectedNote!.id),
            ),
          ),
        ],
      ),
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
      return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (dt.year == now.year) {
      return '${dt.month}月${dt.day}日';
    }
    return '${dt.year}-${dt.month}-${dt.day}';
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
        if (buffer.length >= 100) break;
      }
      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.isEmpty ? '空白笔记' : (text.length > 100 ? '${text.substring(0, 100)}...' : text);
    } catch (_) {
      return '';
    }
  }
}

/// 导入进度弹窗
class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: AppTheme.space16),
          const Text('正在导入印象笔记数据...', style: AppTheme.fontTitle),
          const SizedBox(height: AppTheme.space8),
          Text(
            '正在解析笔记、笔记本层级、标签及附件...\n过程视笔记数量可能需要数十秒，请勿关闭应用。',
            style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
