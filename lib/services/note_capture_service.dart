import 'package:flutter/material.dart';

import '../tools/notebook/appflowy_codec.dart';
import '../tools/notebook/note_database.dart';
import '../tools/notebook/note_store.dart';
import 'context_services_bridge.dart';
import 'html_to_markdown.dart';
import 'settings_store.dart';

/// 笔记捕获设置键
const _kCaptureDefaultNotebookId = 'captureDefaultNotebookId';

/// 笔记捕获服务
///
/// 将外部应用选区内容保存为笔记本笔记，支持：
/// - HTML→Markdown 格式转换
/// - 通过 AppleScript 自动获取浏览器 URL
/// - 非浏览器来源弹出 URL 输入对话框
/// - 首次使用引导配置默认笔记本
class NoteCaptureService {
  NoteCaptureService._();
  static final NoteCaptureService instance = NoteCaptureService._();

  /// 已知浏览器 bundle ID
  static const _browserBundleIds = {
    'com.google.Chrome',
    'com.google.Chrome.canary',
    'com.apple.Safari',
    'org.mozilla.firefox',
    'com.microsoft.edgemac',
    'com.brave.Browser',
    'com.operasoftware.Opera',
  };

  /// 获取捕获默认笔记本 ID
  Future<String?> getDefaultNotebookId() async {
    final cfg = await SettingsStore.instance.readToolConfig('note-capture');
    return cfg[_kCaptureDefaultNotebookId] as String?;
  }

  /// 设置捕获默认笔记本 ID
  Future<void> setDefaultNotebookId(String notebookId) async {
    final cfg = await SettingsStore.instance.readToolConfig('note-capture');
    cfg[_kCaptureDefaultNotebookId] = notebookId;
    await SettingsStore.instance.writeToolConfig('note-capture', cfg);
    // 同步到数据库标记
    try {
      await NoteStore.instance.db.setDefaultCaptureNotebook(notebookId);
    } catch (e) {
      debugPrint('[NoteCaptureService] setDefaultCaptureNotebook DB error: $e');
    }
  }

  /// 主入口：捕获选区内容为笔记
  ///
  /// [text] 纯文本选区内容
  /// [html] 富文本（HTML）选区内容，可为空
  /// [sourceApp] 来源应用 bundle ID
  /// [context] Flutter 上下文，用于显示对话框
  Future<bool> captureNote({
    required String text,
    required String html,
    required String sourceApp,
    required BuildContext context,
    String? directUrl,
    String? directTitle,
  }) async {
    if (text.trim().isEmpty && html.trim().isEmpty) return false;

    // 确保默认笔记本已配置
    String? notebookId = await getDefaultNotebookId();
    if (notebookId == null || notebookId.isEmpty) {
      final defaultNb = await NoteStore.instance.defaultCaptureNotebook();
      if (defaultNb != null) {
        notebookId = defaultNb.id;
        await setDefaultNotebookId(notebookId);
      } else {
        final all = await NoteStore.instance.allNotebooks();
        if (all.isNotEmpty) {
          notebookId = all.first.id;
          await setDefaultNotebookId(notebookId);
        } else if (context.mounted) {
          notebookId = await _promptSelectDefaultNotebook(context);
          if (notebookId == null) return false;
          await setDefaultNotebookId(notebookId);
        }
      }
    }

    if (notebookId == null || notebookId.isEmpty) return false;

    // 内容格式转换
    final markdownContent = _buildNoteContent(text: text, html: html);

    // 获取来源 URL（优先使用传入的 directUrl，否则浏览器自动读取，非浏览器静默跳过以防抢焦点）
    String? url = directUrl;
    if ((url == null || url.isEmpty) && _browserBundleIds.contains(sourceApp)) {
      try {
        url = await ContextServicesBridge.instance.getBrowserUrl();
      } catch (_) {}
    }

    // 构建最终笔记正文（Markdown + 来源 URL）
    final fullContent = _assembleNote(
      markdown: markdownContent,
      sourceUrl: url,
    );

    // 提取标题（首行，截断至60字符）
    final title = directTitle != null && directTitle.isNotEmpty
        ? directTitle
        : _extractTitle(text.isNotEmpty ? text : _stripHtml(html));

    // 保存到 NoteStore（转换为 AppFlowy delta 格式）
    try {
      await NoteStore.instance.createNote(
        title: title,
        deltaJson: _markdownToDelta(fullContent),
        notebookId: notebookId,
      );
      final nb = await NoteStore.instance.db.notebookById(notebookId);
      final nbName = nb?.name ?? '默认笔记本';
      _notifySuccess(title: title, notebookName: nbName);
      return true;
    } catch (e) {
      debugPrint('[NoteCaptureService] createNote error: $e');
      return false;
    }
  }

  void _notifySuccess({required String title, required String notebookName}) {
    try {
      final safeTitle = title.replaceAll('"', '\\"').replaceAll('\n', ' ');
      final safeNb = notebookName.replaceAll('"', '\\"');
      ContextServicesBridge.instance.showNotification(
        title: safeTitle,
        notebook: safeNb,
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 内容转换
  // ---------------------------------------------------------------------------

  /// 将 HTML 或纯文本转换为 Markdown
  String _buildNoteContent({required String text, required String html}) {
    if (html.isNotEmpty) {
      final md = htmlToMarkdown(html);
      if (md.trim().isNotEmpty) return md;
    }
    // 纯文本：保留段落换行
    return text;
  }

  String _assembleNote({required String markdown, String? sourceUrl}) {
    final sb = StringBuffer(markdown.trim());
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      sb.write('\n\n---\n\n**来源：** $sourceUrl');
    }
    return sb.toString();
  }

  /// 转换为 AppFlowy document delta JSON
  ///
  /// 将 Markdown 正文解析为 AppFlowy 结构化文档节点（段落、粗体、分割线、链接等），
  /// 避免在编辑器中呈现原始语法字符。
  String _markdownToDelta(String markdown) {
    try {
      final doc = AppFlowyCodec.parseToDocument(markdown);
      return AppFlowyCodec.documentToJson(doc);
    } catch (e) {
      debugPrint('[NoteCaptureService] _markdownToDelta error: $e');
      final escaped = markdown
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"')
          .replaceAll('\n', '\\n')
          .replaceAll('\r', '');
      return '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"$escaped"}]}}]}}';
    }
  }

  String _extractTitle(String text) {
    final firstLine = text.split('\n').firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '来自外部捕获的笔记',
    );
    var title = firstLine.trim();
    // 移除 Markdown 标题前缀
    title = title.replaceAll(RegExp(r'^#+\s*'), '');
    if (title.length > 60) title = '${title.substring(0, 60)}…';
    return title.isEmpty ? '来自外部捕获的笔记' : title;
  }

  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ---------------------------------------------------------------------------
  // 对话框
  // ---------------------------------------------------------------------------

  /// 弹出笔记本选择对话框（首次使用引导）
  Future<String?> _promptSelectDefaultNotebook(BuildContext context) async {
    final notebooks = await NoteStore.instance.allNotebooks();
    if (notebooks.isEmpty) return null;
    if (!context.mounted) return null;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NotebookPickerDialog(
        notebooks: notebooks,
        title: '选择默认笔记本',
        message: '请选择"保存笔记"功能的默认目标笔记本：',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 内部 Widget：笔记本选择对话框
// ---------------------------------------------------------------------------

class _NotebookPickerDialog extends StatefulWidget {
  const _NotebookPickerDialog({
    required this.notebooks,
    required this.title,
    required this.message,
  });

  final List<Notebook> notebooks;
  final String title;
  final String message;

  @override
  State<_NotebookPickerDialog> createState() => _NotebookPickerDialogState();
}

class _NotebookPickerDialogState extends State<_NotebookPickerDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.notebooks.isNotEmpty) _selected = widget.notebooks.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            ...widget.notebooks.map(
              (nb) => RadioListTile<String>(
                value: nb.id,
                groupValue: _selected,
                title: Text('${nb.icon} ${nb.name}'),
                dense: true,
                onChanged: (v) => setState(() => _selected = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
