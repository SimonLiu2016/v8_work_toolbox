import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../appflowy_codec.dart';
import '../docx_to_markdown.dart';
import '../evernote_import_service.dart';
import '../export_service.dart';
import '../markdown_converter.dart';
import '../note_database.dart';
import '../note_store.dart';
import '../pdf_image_extractor.dart';
import '../pdf_to_markdown.dart';
import '../xlsx_to_markdown.dart';
import 'note_editor.dart';
import 'knowledge_graph_view.dart';
import 'notebook_qa_panel.dart';
import '../../../services/note_capture_service.dart';

/// 笔记本工具主页面（仿印象笔记三栏布局）
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

/// 窗口焦点桥接：让 `main.dart` 里的窗口焦点监听能触达本页面刷新。
///
/// 主窗口重新获得焦点时刷新中间列，感知子窗口中的编辑（设计决策 3）。
/// 使用回调注册表而非全局事件总线，作用域限于本页面。
class NotebookFocusBridge {
  NotebookFocusBridge._();

  static final NotebookFocusBridge instance = NotebookFocusBridge._();

  final Set<VoidCallback> _listeners = {};

  void register(VoidCallback callback) {
    _listeners.add(callback);
  }

  void unregister(VoidCallback callback) {
    _listeners.remove(callback);
  }

  /// 窗口获得焦点时调用。
  void notifyWindowFocused() {
    for (final callback in _listeners.toList()) {
      try {
        callback();
      } catch (e) {
        debugPrint('NotebookFocusBridge listener error: $e');
      }
    }
  }
}

/// 待落库的图片：占位标记 + 字节 + MIME。
///
/// 为什么需要它：图片必须等 `createNote` 拿到 noteId 之后才能
/// `addAttachment`，而 markdown 在此之前就要生成。故先以占位标记传递，
/// 落库后再替换为附件节点。
class _PendingImage {
  _PendingImage({
    required this.key,
    required this.placeholder,
    required this.bytes,
    required this.mime,
  });

  /// 稳定键（docx 用文件名，pdf 用页+尺寸+长度）。
  final String key;

  /// markdown 中的占位文本。
  final String placeholder;

  final Uint8List bytes;
  final String mime;
}

/// 解析结果：markdown + 图片 + 无法提取的图片计数。
class _ExtractedDoc {
  _ExtractedDoc({
    required this.markdown,
    this.images = const [],
    this.unrecoverable = 0,
  });

  final String markdown;
  final List<_PendingImage> images;
  final int unrecoverable;
}

class _NotebookPageState extends State<NotebookPage> {
  final NoteStore _store = NoteStore.instance;

  Map<String, List<Notebook>> _stacks = {};
  List<Notebook> _unstackedNotebooks = [];
  final Set<String> _collapsedStacks = {};
  String? _selectedStack;
  List<Tag> _tags = [];
  List<Note> _notes = [];
  Note? _selectedNote;
  String? _selectedNotebookId;
  String? _selectedTagId;
  bool _isTrashSelected = false;
  String _searchQuery = '';
  bool _isLoading = true;

  /// AI 问答面板开关（阶段二）。开启时在最右侧增加一列。
  bool _showQa = false;

  /// 知识星图开关（阶段四）。与问答面板互斥，避免右侧过挤。
  bool _showGraph = false;

  // 批量操作多选状态
  bool _isBatchMode = false;
  final Set<String> _selectedNoteIds = {};

  final TextEditingController _searchController = TextEditingController();

  /// 活动笔记编辑器 GlobalKey，用于实时事务级内容追加
  final GlobalKey<NoteEditorState> _editorKey = GlobalKey<NoteEditorState>();

  // 窗口焦点刷新回调（子窗口中的编辑感知）
  late VoidCallback _windowFocusCallback;

  @override
  void initState() {
    super.initState();
    _windowFocusCallback = () {
      if (mounted) _refresh(silent: true);
    };
    NotebookFocusBridge.instance.register(_windowFocusCallback);
    _init();
  }

  @override
  void dispose() {
    NotebookFocusBridge.instance.unregister(_windowFocusCallback);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _store.init();
    await _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final grouped = await _store.groupedNotebooks();
      _stacks = grouped.stacks;
      _unstackedNotebooks = grouped.unstacked;
      _tags = await _store.allTags();

      if (_isTrashSelected) {
        _notes = await _store.deletedNotes();
      } else if (_searchQuery.isNotEmpty) {
        _notes = await _store.searchNotes(_searchQuery);
      } else if (_selectedTagId != null) {
        _notes = await _store.notesForTag(_selectedTagId!);
      } else if (_selectedStack != null && _selectedNotebookId == null) {
        _notes = await _store.notesForStack(_selectedStack!);
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

  Future<void> _createNotebook({String? stack}) async {
    final targetStack = stack ?? _selectedStack;
    final title = targetStack != null ? '在 "$targetStack" 下新建笔记本' : '新建笔记本';
    final name = await _showInputDialog(title, '请输入笔记本名称');
    if (name == null || name.trim().isEmpty) return;
    await _store.createNotebook(name.trim(), stack: targetStack);
    await _refresh(silent: true);
  }

  Future<void> _renameNotebook(Notebook nb) async {
    final name = await _showInputDialog(
      '重命名笔记本',
      '笔记本名称',
      initialValue: nb.name,
    );
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

  Future<void> _setDefaultCaptureNotebook(String id) async {
    await _store.setDefaultCaptureNotebook(id);
    await NoteCaptureService.instance.setDefaultNotebookId(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已设为笔记捕获默认笔记本 📥'),
          duration: Duration(seconds: 2),
        ),
      );
      _refresh(silent: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Note actions
  // ---------------------------------------------------------------------------

  Future<void> _createNote() async {
    _isTrashSelected = false;
    _isBatchMode = false;
    _selectedNoteIds.clear();

    String? targetNbId = _selectedNotebookId;
    if (targetNbId == null && _selectedStack != null) {
      final stackNbs = _stacks[_selectedStack];
      if (stackNbs != null && stackNbs.isNotEmpty) {
        targetNbId = stackNbs.first.id;
      }
    }

    final id = await _store.createNote(
      title: '无标题笔记',
      deltaJson: AppFlowyCodec.documentToJson(
        Document.blank(withInitialText: true),
      ),
      notebookId: targetNbId,
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
    final confirm = await _showConfirmDialog('彻底删除', '确定彻底粉碎该笔记及其附件吗？此操作无法撤销。');
    if (confirm != true) return;
    await _store.permanentlyDeleteNote(id);
    if (_selectedNote?.id == id) _selectedNote = null;
    await _refresh(silent: true);
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  /// 支持的多格式导入扩展名
  static const _importExtensions = [
    'pdf',
    'docx',
    'xlsx',
    'md',
    'markdown',
    'txt',
  ];

  /// 多格式文档导入：pdf/docx/xlsx/md/txt → 新笔记。
  /// 可选"保留原文件为附件"。
  Future<void> _importDocuments() async {
    List<PlatformFile> picked = const [];
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _importExtensions,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      picked = result.files;
    } catch (e) {
      // 打开文件面板本身就可能失败（历史上缺 files.user-selected entitlement
      // 时这里抛 PlatformException，而外层无 catch 会让用户"点了没反应"）。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开文件选择器失败: $e'),
          backgroundColor: context.errorSolid,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    if (!mounted) return;
    // 导入选项：是否保留原文件为附件
    final keepOriginal = await _askKeepOriginal(picked.length);
    if (keepOriginal == null) return; // 用户取消

    int successCount = 0;
    int failCount = 0;
    var lostImages = 0;
    for (final file in picked) {
      if (file.path == null) continue;
      String? createdNoteId;
      try {
        final doc = await _extractMarkdownWithImages(file.path!, file.name);
        if (doc == null) {
          failCount++;
          continue;
        }
        final title = file.name.replaceAll(
          RegExp(r'\.(pdf|docx|xlsx|md|markdown|txt)$', caseSensitive: false),
          '',
        );
        var deltaJson = MarkdownConverter.markdownToDelta(doc.markdown);

        final noteId = await _store.createNote(
          title: title,
          deltaJson: deltaJson,
          notebookId: _selectedNotebookId,
        );
        createdNoteId = noteId;

        // 内嵌图片：占位标记 → 落库 → 附件节点。
        // 顺序不可换——addAttachment 需要 noteId。
        for (final img in doc.images) {
          final attId = await _store.addAttachment(
            noteId: noteId,
            sourceFile: await _writeTempImage(img),
          );
          deltaJson = AppFlowyCodec.replacePlaceholderWithAttachment(
            deltaJson,
            placeholder: img.placeholder,
            attachmentId: attId,
            filename: '${img.key}.${_extFor(img.mime)}',
            sizeBytes: img.bytes.length,
            mime: img.mime,
          );
        }
        lostImages += doc.unrecoverable;

        if (keepOriginal) {
          // 先建笔记拿到 noteId（addAttachment 需要），再把附件块追加进正文——
          // 只建记录不写正文的话，用户在笔记里看不到任何入口。
          final sourceFile = File(file.path!);
          final attId = await _store.addAttachment(
            noteId: noteId,
            sourceFile: sourceFile,
          );
          final stat = await sourceFile.stat();
          deltaJson = _appendAttachmentBlock(
            deltaJson,
            attId: attId,
            filename: file.name,
            sizeBytes: stat.size,
          );
        }
        await _store.updateNote(id: noteId, deltaJson: deltaJson);
        createdNoteId = null; // 已成功，退出回滚范围
        successCount++;
      } catch (e) {
        debugPrint('导入 ${file.name} 失败: $e');
        await _rollbackFailedImport(createdNoteId);
        failCount++;
      }
    }

    await _refresh(silent: true);

    if (mounted) {
      final msg = failCount > 0
          ? '已导入 $successCount 篇，$failCount 篇失败'
          : '已导入 $successCount 篇笔记';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lostImages > 0 ? '$msg（$lostImages 张图片未能提取）' : msg,
          ),
          backgroundColor: failCount > 0 || lostImages > 0 ? context.warningSolid : null,
        ),
      );
    }
  }

  /// MIME → 扩展名。
  static String _extFor(String mime) {
    if (mime == 'image/jpeg') return 'jpg';
    if (mime == 'image/png') return 'png';
    if (mime == 'image/gif') return 'gif';
    return 'bin';
  }

  /// 把待落库图片写入临时文件——[addAttachment] 收的是 File。
  ///
  /// 临时目录由调用方负责清理（导入结束后统一删）。
  static Future<File> _writeTempImage(_PendingImage img) async {
    final dir = Directory.systemTemp.createTempSync('v8_note_img_');
    final file = File('${dir.path}/${img.key}.${_extFor(img.mime)}');
    await file.writeAsBytes(img.bytes);
    return file;
  }

  /// 在笔记文档末尾追加一个附件块，返回更新后的 deltaJson。
  /// 用于"保留原文件为附件"——让附件在笔记里可见可操作。
  String _appendAttachmentBlock(
    String deltaJson, {
    required String attId,
    required String filename,
    required int sizeBytes,
  }) => AppFlowyCodec.appendAttachmentNode(
    deltaJson,
    attachmentId: attId,
    filename: filename,
    sizeBytes: sizeBytes,
  );

  /// 导入失败时回滚已建的半成品笔记。
  ///
  /// `createNote` 在附件追加之前执行，中途失败会留下正文不全 + 附件文件/记录
  /// 的孤儿笔记，但用户只看到"失败 1 篇"。此处彻底删除（含附件文件与 DB 记录、
  /// FTS 条目），使"失败"与磁盘/数据库状态一致。
  Future<void> _rollbackFailedImport(String? noteId) async {
    if (noteId == null) return;
    try {
      await _store.permanentlyDeleteNote(noteId);
      // permanentlyDeleteNote 未清理 FTS，同步删除索引条目避免可搜索到已删笔记。
      await _store.db.customStatement(
        'DELETE FROM notes_fts WHERE note_id = ?',
        [noteId],
      );
      debugPrint('已回滚失败的导入笔记 $noteId');
    } catch (e) {
      debugPrint('回滚导入笔记 $noteId 失败: $e');
    }
  }


  /// 解析结果：markdown + 待落库的图片字节。
  ///
  /// 图片此时还没有 noteId，故先以 [DocxToMarkdown.imagePlaceholderPrefix]
  /// 或 [PdfToMarkdown.imagePlaceholderPrefix] 占位，等 createNote 之后
  /// 逐个 addAttachment 拿真实 attId，再把占位替换为附件节点。
  Future<_ExtractedDoc?> _extractMarkdownWithImages(
    String path,
    String name,
  ) async {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'md':
      case 'markdown':
      case 'txt':
        return _ExtractedDoc(markdown: await File(path).readAsString());
      case 'docx':
        return _extractDocxWithImages(path);
      case 'pdf':
        return _extractPdfWithImages(path);
      case 'xlsx':
        return _ExtractedDoc(markdown: await XlsxToMarkdown.convert(path));
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('不支持的格式 .$ext（支持：${_importExtensions.join('、')}）'),
              backgroundColor: context.errorSolid,
            ),
          );
        }
        return null;
    }
  }

  /// docx：文本与图片一次抽出，markdown 中已含占位标记。
  Future<_ExtractedDoc> _extractDocxWithImages(String path) async {
    final bytes = await File(path).readAsBytes();
    final result = DocxToMarkdown.convertWithImages(bytes);
    return _ExtractedDoc(
      markdown: result.markdown,
      images: result.images
          .map((i) => _PendingImage(
                key: i.filename,
                placeholder: '${DocxToMarkdown.imagePlaceholderPrefix}${i.filename}${DocxToMarkdown.imagePlaceholderSuffix}',
                bytes: i.bytes,
                mime: i.mime,
              ))
          .toList(),
      unrecoverable: DocxToMarkdown.lastUnrecoverableCount,
    );
  }

  /// pdf：文本走 PDFKit，图片走 [PdfImageExtractor]。
  ///
  /// 两者无位置关联（PDF 无段落概念），故按"每页首之前"插入该页图片的
  /// 占位标记—— fidelity 到页这一级，与 spec 的 "extracted per page" 对齐。
  Future<_ExtractedDoc?> _extractPdfWithImages(String path) async {
    String markdown;
    try {
      markdown = await _extractPdfMarkdown(path);
    } on PdfNoTextLayerException catch (e) {
      // 扫描件无文字层：明确告知，并引导到"保留原文件为附件"这条可用路径
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e\n可在导入时勾选「保留原文件为附件」以保留原始文档。'),
            backgroundColor: context.warningSolid,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return null;
    }

    List<PdfExtractedImage> images = const [];
    var unrecoverable = 0;
    try {
      final bytes = await File(path).readAsBytes();
      images = PdfImageExtractor.extract(bytes);
      unrecoverable = PdfImageExtractor.lastUnrecoverableCount;
    } on PdfEncryptedException {
      // 加密 PDF：文本可能仍可读，图片不可提取。如实报告，不假装成功。
      unrecoverable = 1;
    }

    // 按页把该页图片的占位插到该页第一个文本之前。
    if (images.isNotEmpty) {
      markdown = _insertPdfImagePlaceholders(markdown, images);
    }
    return _ExtractedDoc(
      markdown: markdown,
      images: images
          .map((i) => _PendingImage(
                key: 'p${i.pageIndex}_${i.width}x${i.height}_${i.bytes.length}',
                placeholder: PdfToMarkdown.imagePlaceholder(i),
                bytes: i.bytes,
                mime: i.mime,
              ))
          .toList(),
      unrecoverable: unrecoverable,
    );
  }

  /// 把每页图片占位插到该页文本之前。[pdfToMarkdown] 以 `\n---\n` 分页。
  String _insertPdfImagePlaceholders(
    String markdown,
    List<PdfExtractedImage> images,
  ) {
    final byPage = <int, List<String>>{};
    for (final img in images) {
      byPage.putIfAbsent(img.pageIndex, () => []).add(
        PdfToMarkdown.imagePlaceholder(img),
      );
    }
    final blocks = markdown.split('\n---\n');
    final out = <String>[];
    for (var i = 0; i < blocks.length; i++) {
      final prefix = byPage[i]?.join('\n\n');
      out.add(prefix == null ? blocks[i] : '$prefix\n\n${blocks[i]}');
    }
    return out.join('\n---\n');
  }

  /// PDF 文本提取（复用朗读模块的解析能力）
  Future<String> _extractPdfMarkdown(String path) async {
    return PdfToMarkdown.convert(path);
  }

  /// 询问是否保留原文件为附件。返回 null 表示取消。
  Future<bool?> _askKeepOriginal(int fileCount) {
    bool keep = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Text('导入 $fileCount 个文件', style: AppTheme.fontTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('将提取文件内容生成新笔记。', style: AppTheme.fontBody),
              const SizedBox(height: AppTheme.space12),
              CheckboxListTile(
                value: keep,
                onChanged: (v) => setDialogState(() => keep = v ?? false),
                title: const Text('保留原文件为附件', style: AppTheme.fontBody),
                subtitle: const Text(
                  '原始文档将作为笔记附件保存，可随时下载查看',
                  style: AppTheme.fontCaption,
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(keep),
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEvernoteImportDialog() async {
    // 异步探测本机客户端状态
    final localInfo = await EvernoteImportService.instance
        .detectLocalEvernote();

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('导入印象笔记', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请选择导入方式：', style: AppTheme.fontBody),
            const SizedBox(height: AppTheme.space16),
            if (localInfo.detected) ...[
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.borderRadiusSmall,
                ),
                tileColor: context.accentSolid.withValues(alpha: 0.12),
                leading: Icon(Icons.flash_on, color: context.accentText),
                title: Text(
                  '从本机客户端一键全量迁移 (${localInfo.noteCount} 篇 · ${localInfo.notebookCount} 个笔记本)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.accentText,
                  ),
                ),
                subtitle: Text('免密直读本机缓存，秒级还原全部笔记本分类、未加密正文与附件'),
                onTap: () => Navigator.pop(ctx, 'local_client'),
              ),
              SizedBox(height: AppTheme.space8),
            ],
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusSmall,
              ),
              tileColor: context.bgInput,
              leading: Icon(
                Icons.file_open_outlined,
                color: context.textPrimary,
              ),
              title: Text('从本地 .notes / .enex 备份文件导入'),
              subtitle: Text('自动提取文件名作为所属笔记本，并智能匹配本机明文正文'),
              onTap: () => Navigator.pop(ctx, 'notes_file'),
            ),
            SizedBox(height: AppTheme.space8),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.borderRadiusSmall,
              ),
              tileColor: context.bgInput,
              leading: Icon(
                Icons.cloud_sync_outlined,
                color: context.infoText,
              ),
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
      final importResult = await EvernoteImportService.instance
          .importFromLocalClient(
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
          SnackBar(
            content: Text('本机迁移失败: $e'),
            backgroundColor: context.errorSolid,
          ),
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
          SnackBar(content: Text('导入失败: $e'), backgroundColor: context.errorSolid),
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
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ImportProgressDialog(),
    );

    try {
      final importResult = await EvernoteImportService.instance
          .importFromNotesFile(
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
          SnackBar(
            content: Text('解析导入失败: $e'),
            backgroundColor: context.errorSolid,
          ),
        );
      }
    }
  }

  void _showImportResult(ImportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('印象笔记导入完成', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总笔记数: ${result.total} 篇'),
            const SizedBox(height: 4),
            Text(
              '成功导入: ${result.imported} 篇',
              style: TextStyle(
                color: context.successText,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (result.failed > 0) ...[
              const SizedBox(height: 4),
              Text(
                '导入失败: ${result.failed} 篇',
                style: TextStyle(color: context.errorText),
              ),
            ],
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space8),
              const Text(
                '错误摘要:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 120,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.errors
                        .take(20)
                        .map(
                          (e) => Text(
                            '• $e',
                            style: AppTheme.fontCaption.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                        )
                        .toList(),
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

  Future<void> _exportNote(ExportFormat format, {Note? note}) async {
    final target = note ?? _selectedNote;
    if (target == null) return;

    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (outputDir == null) return;

    try {
      final file = await ExportService.instance.exportToFile(
        note: target,
        format: format,
        outputDir: outputDir,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已成功导出: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: context.errorSolid),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dialog helpers
  // ---------------------------------------------------------------------------

  Future<String?> _showInputDialog(
    String title,
    String hint, {
    String? initialValue,
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint, isDense: true),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 右键上下文菜单（10 项）
  // ---------------------------------------------------------------------------

  /// 在笔记卡片上触发右键菜单。
  ///
  /// 中间列卡片是纯展示的 [InkWell]，不含输入控件或手势竞技场，
  /// 因此直接在其上监听 `onSecondaryTapDown` 不会影响右列编辑器的焦点。
  Future<void> _showNoteContextMenu(Note note, Offset position) async {
    // 使用窗口物理尺寸计算菜单锚点，而非 MediaQuery.of(context).size：
    // context 在 widget 树里嵌套在 Container(320) 内，返回 320px 宽度，
    // 而 globalPosition 是整个窗口的坐标，坐标系不对齐会导致菜单偏移到右侧。
    final view = View.of(context);
    final windowSize = view.physicalSize / view.devicePixelRatio;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(0, 0),
        Offset.zero & windowSize,
      ),
      elevation: 6,
      shadowColor: const Color(0x40000000),
      color: const Color(0xFFFFFFFF), // 中间列是浅色背景，菜单底色也用白色
      surfaceTintColor: Colors.transparent, // 禁用 Material3 的 elevation 着色
      items: _noteMenuItems(note),
    );
    if (choice == null) return;
    await _runNoteMenuAction(choice, note);
  }

  List<PopupMenuEntry<String>> _noteMenuItems(Note note) {
    final trash = _isTrashSelected;
    return <PopupMenuEntry<String>>[
      _menuEntry('new', '新建笔记', Icons.note_add),
      _menuEntry('standalone', '在新窗口中打开笔记', Icons.open_in_new),
      _menuDivider(),
      _menuEntry(
        note.isPinned ? 'unpin' : 'pin',
        note.isPinned ? '从快捷方式中移除' : '添加笔记到快捷方式',
        Icons.push_pin_outlined,
      ),
      _menuEntry('task', '创建任务', Icons.check_box_outline_blank_rounded),
      _menuDivider(),
      _menuEntry('share', '共享笔记…', Icons.share_outlined),
      _menuEntry('export', '导出笔记…', Icons.file_download_outlined),
      _menuEntry('save-attachments', '将附件保存到文件夹…', Icons.folder_open),
      _menuDivider(),
      _menuEntry('copy-link', '复制笔记链接', Icons.link_outlined),
      _menuEntry('move', '移动笔记到…', Icons.drive_file_move_outlined),
      _menuDivider(),
      _menuEntry(
        'delete',
        trash ? '粉碎笔记' : '删除笔记',
        trash ? Icons.delete_forever_outlined : Icons.delete_outline,
        labelColor: trash ? context.errorSolid : null,
        iconColor: trash ? context.errorSolid : null,
      ),
    ];
  }

  PopupMenuItem<String> _menuEntry(
    String key,
    String label,
    IconData icon, {
    Color? labelColor,
    Color? iconColor,
  }) {
    return PopupMenuItem<String>(
      value: key,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? const Color(0xFF1E293B)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: labelColor ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuDivider _menuDivider() => const PopupMenuDivider(height: 6);

  /// 执行右键菜单动作。各动作自行负责刷新与提示。
  Future<void> _runNoteMenuAction(String key, Note note) async {
    switch (key) {
      case 'new':
        await _createNote();
        return;
      case 'standalone':
        await _openNoteInSubWindow(note);
        return;
      case 'pin':
      case 'unpin':
        await _togglePin(note);
        return;
      case 'task':
        await _appendTaskItem(note);
        return;
      case 'share':
        await _showShareNoteDialog(note);
        return;
      case 'export':
        await _showExportDialog(note);
        return;
      case 'save-attachments':
        await _saveAttachmentsToFolder(note);
        return;
      case 'copy-link':
        await _copyNoteLink(note);
        return;
      case 'move':
        final target = await _showNotebookPicker(note: note);
        if (target == null) return;
        await _store.updateNote(id: note.id, notebookId: target);
        _showToast('已移动到「${_notebookName(target)}」');
        return;
      case 'delete':
        if (_isTrashSelected) {
          await _permanentlyDeleteNote(note.id);
        } else {
          await _deleteNoteWithUndo(note);
        }
        return;
    }
  }

  String _notebookName(String id) {
    for (final stack in _stacks.values) {
      for (final nb in stack) {
        if (nb.id == id) return nb.name;
      }
    }
    for (final nb in _unstackedNotebooks) {
      if (nb.id == id) return nb.name;
    }
    return '未知笔记本';
  }

  Future<void> _togglePin(Note note) async {
    await _store.updateNote(id: note.id, isPinned: !note.isPinned);
    _showToast(note.isPinned ? '已移除快捷方式' : '已添加到快捷方式');
    await _refresh(silent: true);
  }

  /// 在笔记末尾追加一条未勾选的待办项。
  Future<void> _appendTaskItem(Note note) async {
    await _store.updateNote(
      id: note.id,
      deltaJson: NoteStore.appendTodoTask(note.deltaJson),
    );
    _showToast('已添加任务');
    await _refresh(silent: true);
  }

  Future<void> _copyNoteLink(Note note) async {
    final deepLink = 'v8work://notebook/note/${note.id}';
    final title = note.title.isEmpty ? '无标题笔记' : note.title;
    final markdownLink = '[$title]($deepLink)';
    await Clipboard.setData(ClipboardData(text: '$deepLink\n$markdownLink'));
    _showToast('已复制笔记链接');
  }

  /// 软删除并支持撤销。
  Future<void> _deleteNoteWithUndo(Note note) async {
    final id = note.id;
    final title = note.title.isEmpty ? '无标题笔记' : note.title;
    await _store.softDeleteNote(id);
    if (mounted && _selectedNote?.id == id) {
      setState(() => _selectedNote = null);
    }
    await _refresh(silent: true);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除「$title」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await _store.restoreNote(id);
            await _refresh(silent: true);
            _showToast('已撤销删除');
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 右键菜单：单篇笔记子窗口
  // ---------------------------------------------------------------------------

  /// 在独立桌面窗口中打开单篇笔记；已打开则前置。
  Future<void> _openNoteInSubWindow(Note note) async {
    final arg = 'note:${note.id}';
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments == arg) {
          await window.show();
          return;
        }
      }
      final controller = await WindowController.create(
        WindowConfiguration(arguments: arg),
      );
      await controller.show();
    } catch (e) {
      _showToast('打开子窗口失败: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 右键菜单：笔记本选择器
  // ---------------------------------------------------------------------------

  Future<String?> _showNotebookPicker({Note? note}) async {
    final allNotebooks = [
      ..._unstackedNotebooks,
      for (final stack in _stacks.values) ...stack,
    ];
    if (allNotebooks.isEmpty) {
      _showToast('没有可选择的笔记本');
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('移动笔记到…', style: AppTheme.fontTitle),
        content: SizedBox(
          width: 340,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allNotebooks.length,
            itemBuilder: (c, i) {
              final nb = allNotebooks[i];
              final isCurrent = note?.notebookId == nb.id;
              return ListTile(
                enabled: !isCurrent,
                selected: isCurrent,
                leading: Text(nb.icon),
                title: Text(nb.name),
                subtitle: nb.stack != null ? Text(nb.stack!) : null,
                trailing: isCurrent
                    ? Text(
                        '当前',
                        style: TextStyle(color: context.textTertiary),
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, isCurrent ? null : nb.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 右键菜单：共享笔记
  // ---------------------------------------------------------------------------

  Future<void> _showShareNoteDialog(Note note) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('共享笔记', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _shareOption(
              Icons.code_rounded,
              '复制 Markdown',
              '复制笔记正文的 Markdown 文本到剪贴板',
              () async {
                final md = await ExportService.instance.exportNote(
                  note,
                  ExportFormat.markdown,
                );
                await Clipboard.setData(ClipboardData(text: md));
                if (!ctx.mounted) return;
                _showToast('已复制 Markdown', at: ctx);
                Navigator.pop(ctx);
              },
            ),
            _shareOption(
              Icons.notes_rounded,
              '复制纯文本',
              '复制笔记正文的纯文本到剪贴板',
              () async {
                final txt = await ExportService.instance.exportNote(
                  note,
                  ExportFormat.plainText,
                );
                await Clipboard.setData(ClipboardData(text: txt));
                if (!ctx.mounted) return;
                _showToast('已复制纯文本', at: ctx);
                Navigator.pop(ctx);
              },
            ),
            _shareOption(
              Icons.save_alt_rounded,
              '另存为离线 HTML',
              '生成单文件 HTML 网页，可在浏览器离线查看',
              () async {
                final dir = await FilePicker.platform.getDirectoryPath(
                  dialogTitle: '选择保存目录',
                );
                if (dir == null) return;
                try {
                  final file = await ExportService.instance.exportToFile(
                    note: note,
                    format: ExportFormat.html,
                    outputDir: dir,
                  );
                  if (!ctx.mounted) return;
                  _showToast('已保存 HTML: ${file.path}', at: ctx);
                } catch (e) {
                  if (ctx.mounted) _showToast('保存失败: $e', at: ctx);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _shareOption(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, size: 20, color: context.accentText),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11)),
      dense: true,
      onTap: onTap,
    );
  }

  // ---------------------------------------------------------------------------
  // 右键菜单：导出
  // ---------------------------------------------------------------------------

  Future<void> _showExportDialog(Note note) async {
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('导出笔记', style: AppTheme.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in ExportFormat.values)
              ListTile(
                leading: const SizedBox(width: 0),
                title: Text(f.label),
                dense: true,
                onTap: () => Navigator.pop(ctx, f),
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
    if (format == null) return;
    await _exportNote(format, note: note);
  }

  // ---------------------------------------------------------------------------
  // 右键菜单：附件另存
  // ---------------------------------------------------------------------------

  Future<void> _saveAttachmentsToFolder(Note note) async {
    final attachments = await _store.attachmentsForNote(note.id);
    if (attachments.isEmpty) {
      _showToast('该笔记没有附件');
      return;
    }

    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择附件保存目录',
    );
    if (outputDir == null) return;

    final (copied, failed) = await _store.exportAttachments(
      noteId: note.id,
      outputDir: outputDir,
    );

    var message = '已保存 $copied 个附件';
    if (failed > 0) message += '，$failed 个失败';
    _showToast('$message → $outputDir');
  }

  // ---------------------------------------------------------------------------
  // 通用提示
  // ---------------------------------------------------------------------------

  void _showToast(String message, {SnackBarAction? action, BuildContext? at}) {
    if (at != null) {
      // 来自弹窗回调：页面可能已重建，改用 maybeOf 避免跨 async gap 使用旧 context。
      final messenger = ScaffoldMessenger.maybeOf(at);
      messenger?.showSnackBar(SnackBar(content: Text(message), action: action));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<bool?> _showConfirmDialog(String title, String message) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text(title, style: AppTheme.fontTitle),
        content: Text(message, style: AppTheme.fontBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.errorSolid),
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
          // Left: Notebook tree + tags + 常驻导入 (固定 240px)
          SizedBox(width: 240, child: _buildLeftPanel()),

          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFFE2E8F0),
          ),

          // Center: Note list (固定 320px)
          SizedBox(width: 320, child: _buildCenterPanel()),

          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFFE2E8F0),
          ),

          // Right: Editor (纯白纸质编辑器列，自适应撑满剩余宽度)
          Expanded(child: _buildRightPanel()),

          // Far right: AI 问答面板（阶段二，可切换）
          if (_showQa) ...[
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE2E8F0),
            ),
            SizedBox(
              width: 360,
              child: NotebookQaPanel(
                onOpenNote: _openNoteById,
                activeNote: _selectedNote,
                onNoteCreated: () => _refresh(silent: true),
                onAppendToActiveNote: (markdown) async {
                  if (_editorKey.currentState != null && _selectedNote != null) {
                    final ok = await _editorKey.currentState!.appendMarkdown(markdown);
                    if (ok) {
                      _refresh(silent: true);
                      return true;
                    }
                  }
                  return false;
                },
              ),
            ),
          ],

          // Far right: 知识星图（阶段四，与问答互斥）
          if (_showGraph) ...[
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE2E8F0),
            ),
            SizedBox(
              width: 420,
              child: KnowledgeGraphView(
                selectedNoteId: _selectedNote?.id,
                onOpenNote: _openNoteById,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 从星图或问答引用跳转到笔记：自动切换导航分类并保持稳定选中。
  Future<void> _openNoteById(String noteId) async {
    try {
      final note = await _store.noteById(noteId);
      if (note == null) return;
      if (!mounted) return;

      // 联动解析所属笔记本及分组
      Notebook? targetNb;
      if (note.notebookId != null) {
        final allNb = await _store.allNotebooks();
        for (final nb in allNb) {
          if (nb.id == note.notebookId) {
            targetNb = nb;
            break;
          }
        }
      }

      _searchController.clear();
      setState(() {
        _isTrashSelected = note.isDeleted;
        _selectedNotebookId = note.notebookId;
        _selectedStack = targetNb?.stack;
        _selectedTagId = null;
        _searchQuery = '';
        _isBatchMode = false;
        _selectedNoteIds.clear();
        _showQa = false;
        _selectedNote = note;
      });

      await _refresh(silent: true);

      if (mounted) {
        setState(() {
          _selectedNote = note;
        });
      }
    } catch (e) {
      debugPrint('跳转笔记失败: $e');
    }
  }

  Widget _buildLeftPanel() {
    return Container(
      color: context.bgSidebar,
      child: Column(
        children: [
          // macOS 沉浸式无边框窗口顶部预留红绿灯避让与标头
          Container(
            height: 68,
            padding: EdgeInsets.only(
              top: 28,
              left: 16,
              right: 12,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.borderSubtle)),
            ),
            alignment: Alignment.bottomLeft,
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 20,
                  color: context.accentText,
                ),
                const SizedBox(width: AppTheme.space8),
                Text(
                  '笔记本',
                  style: AppTheme.fontTitle.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // All notes & Trash
          ListTile(
            dense: true,
            leading: const Icon(Icons.all_inbox_rounded, size: 18),
            title: const Text('全部笔记'),
            selected:
                !_isTrashSelected &&
                _selectedStack == null &&
                _selectedNotebookId == null &&
                _selectedTagId == null,
            onTap: () {
              setState(() {
                _isTrashSelected = false;
                _selectedStack = null;
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
            leading: Icon(
              Icons.delete_outline,
              size: 18,
              color: context.warningText,
            ),
            title: const Text('废纸篓'),
            selected: _isTrashSelected,
            onTap: () {
              setState(() {
                _isTrashSelected = true;
                _selectedStack = null;
                _selectedNotebookId = null;
                _selectedTagId = null;
                _isBatchMode = false;
                _selectedNoteIds.clear();
              });
              _refresh(silent: true);
            },
          ),

          Divider(height: 1, color: context.borderSubtle),

          // AI 问答入口（阶段二）：切换右侧「问我的笔记」面板
          ListTile(
            dense: true,
            leading: Icon(
              Icons.auto_awesome,
              size: 18,
              color: _showQa ? context.accentText : context.textSecondary,
            ),
            title: Text(
              '问我的笔记',
              style: TextStyle(
                color: _showQa ? context.accentText : null,
                fontWeight: _showQa ? FontWeight.w600 : null,
              ),
            ),
            selected: _showQa,
            onTap: () => setState(() {
              _showQa = !_showQa;
              if (_showQa) _showGraph = false;
            }),
          ),

          // 知识星图入口（阶段四）
          ListTile(
            dense: true,
            leading: Icon(
              Icons.hub_outlined,
              size: 18,
              color: _showGraph ? context.accentText : context.textSecondary,
            ),
            title: Text(
              '知识星图',
              style: TextStyle(
                color: _showGraph ? context.accentText : null,
                fontWeight: _showGraph ? FontWeight.w600 : null,
              ),
            ),
            selected: _showGraph,
            onTap: () => setState(() {
              _showGraph = !_showGraph;
              if (_showGraph) _showQa = false;
            }),
          ),

          Divider(height: 1, color: context.borderSubtle),

          // Notebooks section header
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 4,
              top: 8,
              bottom: 4,
            ),
            child: Row(
              children: [
                Text(
                  '笔记本',
                  style: AppTheme.fontCaption.copyWith(
                    color: context.textTertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  onPressed: () => _createNotebook(),
                  tooltip: '新建笔记本',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
          ),

          // Notebooks tree with stacks and notebooks
          Expanded(flex: 3, child: _buildNotebookTree()),

          // Tags section
          if (_tags.isNotEmpty) ...[
            Divider(height: 1, color: context.borderSubtle),
            Padding(
              padding: EdgeInsets.only(left: 12, top: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '标签',
                  style: AppTheme.fontCaption.copyWith(
                    color: context.textTertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                    title: Text(
                      '#${tag.name}',
                      style: AppTheme.fontBody,
                      overflow: TextOverflow.ellipsis,
                    ),
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

          Divider(height: 1, color: context.borderSubtle),

          // 常驻导入入口
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentSolid,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text('导入印象笔记', style: TextStyle(fontSize: 12)),
                    onPressed: _showEvernoteImportDialog,
                  ),
                ),
                SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: context.borderSubtle),
                    ),
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('导入文档', style: TextStyle(fontSize: 12)),
                    onPressed: _importDocuments,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotebookTree() {
    final sortedStacks = _stacks.keys.toList()..sort();
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 2),
      children: [
        for (final stack in sortedStacks)
          _buildStackItem(stack, _stacks[stack] ?? []),
        if (_unstackedNotebooks.isNotEmpty) ...[
          if (sortedStacks.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: 14, top: 8, bottom: 4),
              child: Text(
                '未分类笔记本',
                style: AppTheme.fontCaption.copyWith(
                  color: context.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final nb in _unstackedNotebooks)
            _buildNotebookTile(nb, indent: false),
        ],
      ],
    );
  }

  Widget _buildStackItem(String stack, List<Notebook> notebooks) {
    final isCollapsed = _collapsedStacks.contains(stack);
    final isStackSelected =
        !_isTrashSelected &&
        _selectedStack == stack &&
        _selectedNotebookId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isTrashSelected = false;
              _selectedStack = stack;
              _selectedNotebookId = null;
              _selectedTagId = null;
              _isBatchMode = false;
              _selectedNoteIds.clear();
              // 点击组名自动展开
              _collapsedStacks.remove(stack);
            });
            _refresh(silent: true);
          },
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 6, right: 6),
            color: isStackSelected
                ? context.accentSolid.withAlpha(25)
                : Colors.transparent,
            child: Row(
              children: [
                // 折叠/展开箭头
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    setState(() {
                      if (isCollapsed) {
                        _collapsedStacks.remove(stack);
                      } else {
                        _collapsedStacks.add(stack);
                      }
                    });
                  },
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_right_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: context.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isCollapsed
                      ? Icons.folder_outlined
                      : Icons.folder_open_rounded,
                  size: 16,
                  color: isStackSelected
                      ? context.accentSolid
                      : Color(0xFF64748B),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stack,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isStackSelected
                          ? context.accentSolid
                          : context.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${notebooks.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 14,
                    color: context.textTertiary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  splashRadius: 12,
                  onSelected: (v) {
                    if (v == 'new_nb') {
                      _createNotebook(stack: stack);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'new_nb',
                      child: Text('在此组新建笔记本'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          for (final nb in notebooks) _buildNotebookTile(nb, indent: true),
      ],
    );
  }

  Widget _buildNotebookTile(Notebook nb, {required bool indent}) {
    final isSelected = !_isTrashSelected && _selectedNotebookId == nb.id;
    return InkWell(
      onTap: () {
        setState(() {
          _isTrashSelected = false;
          _selectedNotebookId = nb.id;
          _selectedStack = nb.stack;
          _selectedTagId = null;
          _isBatchMode = false;
          _selectedNoteIds.clear();
        });
        _refresh(silent: true);
      },
      child: Container(
        height: 32,
        padding: EdgeInsets.only(left: indent ? 28.0 : 12.0, right: 6.0),
        color: isSelected ? context.accentText.withAlpha(20) : Colors.transparent,
        child: Row(
          children: [
            Text(nb.icon, style: TextStyle(fontSize: 13)),
            SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      nb.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? context.accentText : context.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (nb.isDefaultForCapture == 1) ...[
                    SizedBox(width: 4),
                    Tooltip(
                      message: '笔记捕获默认目标',
                      child: Text('📥', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 13,
                color: context.textTertiary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              splashRadius: 12,
              onSelected: (v) {
                if (v == 'rename') {
                  _renameNotebook(nb);
                } else if (v == 'delete') {
                  _deleteNotebook(nb.id);
                } else if (v == 'set_default_capture') {
                  _setDefaultCaptureNotebook(nb.id);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                const PopupMenuItem(
                  value: 'set_default_capture',
                  child: Text('设为笔记捕获默认'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('删除笔记本', style: TextStyle(color: context.errorText)),
                ),
              ],
            ),
          ],
        ),
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
            height: 68,
            padding: const EdgeInsets.only(
              top: 28,
              left: 8,
              right: 8,
              bottom: 4,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      hintText: _isTrashSelected ? '搜索废纸篓...' : '搜索笔记...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
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
                    _isBatchMode
                        ? Icons.checklist_rtl_rounded
                        : Icons.checklist_rounded,
                    size: 20,
                    color: _isBatchMode
                        ? context.accentSolid
                        : const Color(0xFF64748B),
                  ),
                  onPressed: _toggleBatchMode,
                  tooltip: _isBatchMode ? '退出批量选择' : '批量选择',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                if (!_isTrashSelected) ...[
                  IconButton(
                    icon: Icon(
                      Icons.add_circle,
                      size: 22,
                      color: context.accentText,
                    ),
                    onPressed: _createNote,
                    tooltip: '新建笔记',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
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
                _isTrashSelected
                    ? '废纸篓：${_notes.length} 项'
                    : _selectedStack != null && _selectedNotebookId == null
                    ? '$_selectedStack：${_notes.length} 篇笔记'
                    : '共 ${_notes.length} 篇笔记',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
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
                      value:
                          _notes.isNotEmpty &&
                          _selectedNoteIds.length == _notes.length,
                      onChanged: (_) => _toggleSelectAll(),
                      activeColor: context.accentSolid,
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
                      onPressed: _selectedNoteIds.isNotEmpty
                          ? _batchRestoreSelected
                          : null,
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: Text(
                      _isTrashSelected ? '粉碎' : '删除',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: context.errorSolid,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _selectedNoteIds.isNotEmpty
                        ? _batchDeleteSelected
                        : null,
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
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _notes.length,
                    itemBuilder: (ctx, i) {
                      final note = _notes[i];
                      final isSelected =
                          !_isBatchMode && _selectedNote?.id == note.id;
                      final isChecked = _selectedNoteIds.contains(note.id);
                      return InkWell(
                        onTap: () {
                          if (_isBatchMode) {
                            _toggleSelectNote(note.id);
                          } else {
                            setState(() => _selectedNote = note);
                          }
                        },
                        onSecondaryTapDown: (details) {
                          _showNoteContextMenu(note, details.globalPosition);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isChecked
                                ? const Color(0xFFEFF6FF)
                                : (isSelected
                                      ? const Color(0xFFE8F0FE)
                                      : const Color(0xFFFFFFFF)),
                            border: Border(
                              bottom: const BorderSide(
                                color: Color(0xFFE5E7EB),
                                width: 0.5,
                              ),
                              left: BorderSide(
                                color: isSelected
                                    ? context.accentSolid
                                    : (isChecked
                                          ? const Color(0xFF3B82F6)
                                          : Colors.transparent),
                                width: 3.5,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isBatchMode)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 2,
                                  ),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Checkbox(
                                      value: isChecked,
                                      onChanged: (_) =>
                                          _toggleSelectNote(note.id),
                                      activeColor: context.accentSolid,
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
                                          Padding(
                                            padding: EdgeInsets.only(right: 4),
                                            child: Icon(
                                              Icons.push_pin,
                                              size: 12,
                                              color: context.accentText,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            note.title.isEmpty
                                                ? '无标题笔记'
                                                : note.title,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (note.assetExpiryDate != null)
                                          _buildAssetBadge(
                                            note.assetExpiryDate!,
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
          Container(
            height: 68,
            padding: const EdgeInsets.only(
              top: 28,
              left: AppTheme.space16,
              right: AppTheme.space16,
              bottom: 4,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: _selectedNote != null
                ? Row(
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
                      const Text(
                        '导出：',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      _buildExportButton('MD', ExportFormat.markdown),
                      _buildExportButton('HTML', ExportFormat.html),
                      _buildExportButton('PDF', ExportFormat.pdf),
                      _buildExportButton('TXT', ExportFormat.plainText),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Note Editor
          Expanded(
            child: NoteEditor(
              key: _editorKey,
              note: _selectedNote,
              onSaved: () => _refresh(silent: true),
              onTogglePin: () => _refresh(silent: true),
              onDelete: () => _deleteNote(_selectedNote!.id),
              onRestore: () => _restoreNote(_selectedNote!.id),
              onPermanentDelete: () =>
                  _permanentlyDeleteNote(_selectedNote!.id),
              onOpenNote: _openNoteById,
              // 资产/关联写入后，用数据库现值替换我们的快照。
              // 父层 `_refresh` 在笔记已不在当前过滤列表时会把选择清空，
              // 那样资产 chip 就永远拿不到新值。
              onNoteReloaded: (fresh) {
                if (!mounted) return;
                setState(() => _selectedNote = fresh);
              },
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
        child: Text(
          label,
          style: AppTheme.fontCaption.copyWith(color: context.accentText),
        ),
      ),
    );
  }

  /// 资产徽章：显示到期倒计时。已过期用红色，临期用蓝色。
  Widget _buildAssetBadge(DateTime expiry) {
    final days = expiry.difference(DateTime.now()).inDays;
    final expired = days < 0;
    final label = expired ? '已过期' : (days == 0 ? '今天到期' : '$days 天');
    final bg = expired ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE);
    final fg = expired ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 9, color: fg),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
      return text.isEmpty
          ? '空白笔记'
          : (text.length > 100 ? '${text.substring(0, 100)}...' : text);
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
      backgroundColor: context.bgCard,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: context.accentText),
          SizedBox(height: AppTheme.space16),
          Text('正在导入印象笔记数据...', style: AppTheme.fontTitle),
          SizedBox(height: AppTheme.space8),
          Text(
            '正在解析笔记、笔记本层级、标签及附件...\n过程视笔记数量可能需要数十秒，请勿关闭应用。',
            style: AppTheme.fontBody.copyWith(color: context.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
