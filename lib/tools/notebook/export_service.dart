import 'dart:convert';
import 'dart:io';

import 'package:delta_to_html/delta_to_html.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'markdown_converter.dart';
import 'note_database.dart';

/// 导出格式枚举
enum ExportFormat {
  markdown('Markdown', '.md'),
  html('HTML', '.html'),
  pdf('PDF', '.pdf'),
  plainText('Plain Text', '.txt');

  final String label;
  final String extension;
  const ExportFormat(this.label, this.extension);
}

/// 笔记导出服务
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  /// 导出单条笔记为指定格式的文件内容
  Future<String> exportNote(Note note, ExportFormat format) async {
    switch (format) {
      case ExportFormat.markdown:
        return _toMarkdown(note);
      case ExportFormat.html:
        return _toHtml(note);
      case ExportFormat.plainText:
        return _toPlainText(note);
      case ExportFormat.pdf:
        // PDF 需要先生成 HTML，再调用 PDFKit
        return _toHtml(note); // 返回 HTML，由调用方转 PDF
    }
  }

  /// 导出为文件并返回文件路径
  Future<File> exportToFile({
    required Note note,
    required ExportFormat format,
    required String outputDir,
  }) async {
    final content = await exportNote(note, format);
    final filename = '${_sanitizeFilename(note.title)}${format.extension}';
    final filePath = p.join(outputDir, filename);
    final file = File(filePath);
    await file.writeAsString(content, encoding: utf8);
    return file;
  }

  String _toMarkdown(Note note) {
    final buffer = StringBuffer();
    buffer.writeln('# ${note.title}');
    buffer.writeln();
    buffer.writeln(MarkdownConverter.deltaToMarkdown(note.deltaJson));
    return buffer.toString();
  }

  String _toHtml(Note note) {
    try {
      final deltaOps = jsonDecode(note.deltaJson) as List;
      final htmlBody = DeltaToHTML.encodeJson(deltaOps);

      return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeHtml(note.title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 40px 20px;
      color: #333;
      line-height: 1.6;
    }
    h1 { border-bottom: 1px solid #eee; padding-bottom: 8px; }
    pre { background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; }
    code { background: #f0f0f0; padding: 2px 4px; border-radius: 3px; font-size: 0.9em; }
    pre code { background: none; padding: 0; }
    blockquote { border-left: 3px solid #6366f1; padding-left: 12px; color: #666; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background: #f5f5f5; }
    img { max-width: 100%; }
    .meta { color: #999; font-size: 0.85em; margin-bottom: 24px; }
  </style>
</head>
<body>
  <h1>${_escapeHtml(note.title)}</h1>
  <div class="meta">Created: ${note.createdAt.toIso8601String()} | Updated: ${note.updatedAt.toIso8601String()}</div>
  $htmlBody
</body>
</html>''';
    } catch (e) {
      debugPrint('Delta to HTML conversion error: $e');
      return '<html><body><h1>${_escapeHtml(note.title)}</h1><pre>${_escapeHtml(note.deltaJson)}</pre></body></html>';
    }
  }

  String _toPlainText(Note note) {
    final buffer = StringBuffer();
    buffer.writeln(note.title);
    buffer.writeln();
    // Extract plain text from delta
    try {
      final ops = jsonDecode(note.deltaJson) as List<dynamic>;
      for (final op in ops) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
      }
    } catch (_) {
      buffer.write(note.deltaJson);
    }
    return buffer.toString();
  }

  String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, name.length > 100 ? 100 : name.length);
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
