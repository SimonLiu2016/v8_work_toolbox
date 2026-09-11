import 'dart:convert';
import 'dart:io';

import 'package:delta_to_html/delta_to_html.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  /// macOS 系统 CJK 字体候选路径（按优先级排列）。
  /// 注意：`package:pdf` 的 `TtfWriter` 会按实际使用的字符子集化字体，
  /// 因此 22MB 的完整字体文件不会进入产物，PDF 体积由字符集决定。
  static const List<String> _kCjkFontPaths = [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode MS.ttf',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/Supplemental/Songti.ttc',
  ];

  /// 缓存的 CJK 字体；`null` 表示未找到系统字体，走内置字体回退。
  pw.Font? _cachedCjkFont;

  /// 是否已完成一次字体解析（避免失败后每次导出都重复读盘）。
  bool _cjkFontResolved = false;

  /// 是否已加载到系统 CJK 字体
  bool get hasCjkFont => _cachedCjkFont != null;

  /// 加载离线 CJK 字体，结果按单例缓存。
  /// 找不到系统字体时回退内置 Helvetica，全程不发起任何网络请求。
  ///
  /// [paths] 仅用于测试注入，生产环境始终使用系统候选路径。
  Future<pw.Font> loadCjkFont({List<String>? paths}) async {
    if (_cjkFontResolved) {
      return _cachedCjkFont ?? pw.Font.helvetica();
    }
    _cjkFontResolved = true;

    for (final path in (paths ?? _kCjkFontPaths)) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        _cachedCjkFont = pw.Font.ttf(bytes.buffer.asByteData());
        debugPrint('ExportService: CJK font loaded from $path');
        return _cachedCjkFont!;
      } catch (e) {
        debugPrint('ExportService: failed to load $path: $e');
      }
    }

    debugPrint('ExportService: no system CJK font found, using built-in fallback');
    return pw.Font.helvetica();
  }

  /// 重置字体缓存（测试用）。
  void resetCjkFontCache() {
    _cachedCjkFont = null;
    _cjkFontResolved = false;
  }

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
    final filename = '${_sanitizeFilename(note.title)}${format.extension}';
    final filePath = p.join(outputDir, filename);
    final file = File(filePath);

    if (format == ExportFormat.pdf) {
      await _exportToPdf(note, file);
    } else {
      final content = await exportNote(note, format);
      await file.writeAsString(content, encoding: utf8);
    }

    return file;
  }

  /// 导出为 PDF 文件
  Future<void> _exportToPdf(Note note, File file) async {
    final cjkFont = await loadCjkFont();

    // 主题只影响未带 inline 样式的文字；下面每处 inline 样式都需单独补字体。
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: cjkFont, bold: cjkFont),
    );
    final markdown = _toMarkdown(note);

    // Split markdown into paragraphs and render
    final lines = markdown.split('\n');
    final widgets = <pw.Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }

      // Heading
      if (line.startsWith('# ')) {
        widgets.add(pw.Header(
          level: 0,
          child: pw.Text(line.substring(2), style: _withCjk(cjkFont, 24, bold: true)),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(pw.Header(
          level: 1,
          child: pw.Text(line.substring(3), style: _withCjk(cjkFont, 20, bold: true)),
        ));
        continue;
      }
      if (line.startsWith('### ')) {
        widgets.add(pw.Header(
          level: 2,
          child: pw.Text(line.substring(4), style: _withCjk(cjkFont, 16, bold: true)),
        ));
        continue;
      }

      // Code block
      if (line.startsWith('```')) {
        continue; // Skip code block markers
      }

      // List item
      if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(pw.Bullet(text: line.substring(2)));
        continue;
      }

      // Regular paragraph
      widgets.add(pw.Paragraph(text: line, style: _withCjk(cjkFont, 12)));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          margin: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Text(note.title, style: _withCjk(cjkFont, 28, bold: true)),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _withCjk(cjkFont, 10, color: PdfColors.grey),
          ),
        ),
        build: (context) => widgets,
      ),
    );

    await file.writeAsBytes(await pdf.save());
  }

  /// 构造带 CJK 字体的 inline 样式。
  ///
  /// `package:pdf` 的主题合并（`TextStyle.merge`）不会把 theme base 的字体灌进
  /// inline 样式，而渲染时 `Text._preProcessSpans` 使用 `style.font!`（非空断言）。
  /// 因此仅注入 `pw.Document(theme: pw.ThemeData.withFont(...))` 不会生效，
  /// 每处手写 inline 样式都必须自带字体，否则中文渲染为空白占位块。
  pw.TextStyle _withCjk(pw.Font font, double fontSize, {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      font: font,
      fontNormal: font,
      fontBold: font,
      fontItalic: font,
      fontBoldItalic: font,
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : null,
      color: color,
    );
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
