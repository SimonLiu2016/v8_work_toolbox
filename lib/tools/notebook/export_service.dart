import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:delta_to_html/delta_to_html.dart';
import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md_pkg;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'appflowy_codec.dart';
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

  /// 单例
  static final ExportService _instance = ExportService._();
  static ExportService get instance => _instance;

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

  // ---------------------------------------------------------------------------
  // PDF 导出
  // ---------------------------------------------------------------------------

  /// 导出为 PDF 文件
  Future<void> _exportToPdf(Note note, File file) async {
    final cjkFont = await loadCjkFont();

    // 主题只影响未带 inline 样式的文字；下面每处 inline 样式都需单独补字体。
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: cjkFont, bold: cjkFont),
    );

    // 直接从 Delta 或 AppFlowy 结构渲染，保留 inline 格式与表格
    final blocks = await _parseBlocks(note);
    final widgets = <pw.Widget>[];
    for (final block in blocks) {
      final w = _renderBlock(block, cjkFont);
      if (w != null) widgets.add(w);
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

  List<_PdfInline> _deltaToInlines(Delta? delta) {
    if (delta == null || delta.isEmpty) return const [];
    final list = <_PdfInline>[];
    for (final op in delta.toJson()) {
      if (op is Map && op.containsKey('insert')) {
        final insert = op['insert'];
        if (insert is String) {
          final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
          list.add(_PdfInline(
            insert,
            bold: attrs['bold'] == true,
            italic: attrs['italic'] == true,
            code: attrs['code'] == true,
            underline: attrs['underline'] == true,
            link: (attrs['href'] ?? attrs['link'])?.toString(),
          ));
        }
      }
    }
    return list;
  }

  /// 统一解析笔记内容块（同时支持 AppFlowy 与旧版 Delta）
  Future<List<_PdfBlock>> _parseBlocks(Note note) async {
    final trimmed = note.deltaJson.trim();
    if (trimmed.startsWith('[')) {
      return _parseDeltaBlocks(note);
    }

    final cjkFont = await loadCjkFont();
    final doc = AppFlowyCodec.parseToDocument(note.deltaJson);
    final blocks = <_PdfBlock>[];
    int orderedIndex = 1;

    for (final node in doc.root.children) {
      switch (node.type) {
        case 'heading':
          final level = (node.attributes['level'] as int?) ?? 1;
          blocks.add(_PdfBlock.paragraph(
            _deltaToInlines(node.delta),
            headerLevel: level,
          ));
          break;
        case 'bulleted_list':
          blocks.add(_PdfBlock.paragraph(
            _deltaToInlines(node.delta),
            bulletLabel: '•',
          ));
          break;
        case 'numbered_list':
          blocks.add(_PdfBlock.paragraph(
            _deltaToInlines(node.delta),
            ordered: true,
            bulletLabel: '$orderedIndex',
          ));
          orderedIndex++;
          break;
        case 'todo_list':
          final checked = node.attributes['checked'] == true;
          blocks.add(_PdfBlock.paragraph(
            _deltaToInlines(node.delta),
            bulletLabel: checked ? '[x]' : '[ ]',
          ));
          break;
        case 'quote':
          blocks.add(_PdfBlock.paragraph(
            _deltaToInlines(node.delta),
            blockquote: true,
          ));
          break;
        case 'code':
        case 'code_block':
          final code = node.delta?.toPlainText() ?? '';
          final lang = node.attributes['language']?.toString() ?? '';
          blocks.add(_PdfBlock.widget(_codeBlockWidget(code, lang)));
          break;
        case 'image':
          final url = (node.attributes['url'] ?? node.attributes['src'])?.toString() ?? '';
          final w = await _imageWidget(url, cjkFont);
          if (w != null) blocks.add(_PdfBlock.widget(w));
          break;
        case 'table':
          final rows = <List<String>>[];
          try {
            final tableNode = TableNode(node: node);
            for (var r = 0; r < tableNode.rowsLen; r++) {
              final rowList = <String>[];
              for (var c = 0; c < tableNode.colsLen; c++) {
                final cellNode = tableNode.getCell(c, r);
                final cellText = cellNode.children.isNotEmpty
                    ? (cellNode.children.first.delta?.toPlainText().trim() ?? '')
                    : (cellNode.delta?.toPlainText().trim() ?? '');
                rowList.add(cellText);
              }
              rows.add(rowList);
            }
          } catch (_) {
            for (final r in node.children) {
              rows.add(r.children.map((c) => c.delta?.toPlainText().trim() ?? '').toList());
            }
          }
          final w = _tableWidget({'rows': rows}, cjkFont);
          if (w != null) blocks.add(_PdfBlock.widget(w));
          break;
        case 'mindmap':
          blocks.add(_PdfBlock.widget(_unknownEmbedWidget('思维导图', cjkFont)));
          break;
        case 'paragraph':
        default:
          blocks.add(_PdfBlock.paragraph(_deltaToInlines(node.delta)));
          break;
      }
    }

    return blocks;
  }

  /// 把 Delta 解析为 PDF 内容块列表。
  ///
  /// 支持：标题、段落、有序/无序/待办列表、引用、代码块、图片、表格、
  /// 附件与未知 embed（均以灰字占位提示，不静默丢弃）。
  Future<List<_PdfBlock>> _parseDeltaBlocks(Note note) async {
    final cjkFont = await loadCjkFont();
    final units = <_DeltaUnit>[];
    final rawOps = note.deltaJson.isEmpty ? <dynamic>[] : jsonDecode(note.deltaJson) as List<dynamic>;

    // 把 Delta 展平成 (文本, 属性) 单元，行尾换行符自带块级属性。
    for (final op in rawOps) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is String) {
        final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        units.add(_DeltaUnit.text(insert, attrs));
      } else if (insert is Map) {
        units.add(_DeltaUnit.embed(insert.cast<String, dynamic>()));
      }
    }

    final blocks = <_PdfBlock>[];
    final para = _ParagraphBuffer();
    int? orderedIndex;
    final codeBuf = StringBuffer();

    void flushPara(int? header, bool ordered, String bulletLabel) {
      if (ordered) orderedIndex = (orderedIndex ?? 0) + 1;
      para.flush(blocks, header: header, ordered: ordered, bulletLabel: bulletLabel);
    }

    int i = 0;
    while (i < units.length) {
      final unit = units[i];

      if (unit.isEmbed) {
        flushPara(null, false, '');
        final w = await _embedToWidget(unit.embed!, cjkFont);
        if (w != null) blocks.add(_PdfBlock.widget(w));
        i++;
        continue;
      }

      final text = unit.text!;
      final attrs = unit.attrs;

      // 代码块：把代码块标记内的所有文本原样累积，遇结尾换行闭合。
      if (attrs['code-block'] != null) {
        if (text != '\n') {
          codeBuf.write(text);
        } else {
          final lang = attrs['code-block'];
          blocks.add(_PdfBlock.widget(
            _codeBlockWidget(codeBuf.toString().trim(), lang is String ? lang : ''),
          ));
          codeBuf.clear();
        }
        i++;
        continue;
      }

      // 列表项：每个 \n 一项。
      if (attrs.containsKey('list')) {
        final listType = attrs['list'];
        if (text == '\n') {
          final bullet = listType == 'check' ? '[ ]' : '•';
          final isOrdered = listType == 'ordered';
          final label = isOrdered ? '${orderedIndex ?? 1}' : bullet;
          flushPara(null, isOrdered, label);
        } else {
          para.append(text, attrs);
        }
        i++;
        continue;
      }

      // 引用块。
      if (attrs['blockquote'] != null) {
        if (text == '\n') {
          flushPara(null, false, '');
        } else {
          para.append(text, attrs);
        }
        i++;
        continue;
      }

      // 普通文本。
      if (text == '\n') {
        final headerLevel = attrs['header'];
        final header = headerLevel is int && headerLevel > 0 ? headerLevel : null;
        flushPara(header, false, '');
      } else {
        para.append(text, attrs);
      }
      i++;
    }

    // 收尾：未闭合的列表项与代码块。
    if (codeBuf.isNotEmpty) {
      blocks.add(_PdfBlock.widget(_codeBlockWidget(codeBuf.toString().trim(), '')));
      codeBuf.clear();
    }
    flushPara(null, false, '');

    return blocks;
  }

  /// 渲染单个块为 PDF widget。
  pw.Widget? _renderBlock(_PdfBlock block, pw.Font cjkFont) {
    if (block.isWidget) return block.widget;

    // 标题。
    if (block.headerLevel > 0) {
      final size = switch (block.headerLevel) {
        1 => 22.0,
        2 => 18.0,
        3 => 15.0,
        _ => 13.0,
      };
      return pw.Paragraph(
        style: _withCjk(cjkFont, size, bold: true),
        text: _inlinesToString(block.inlines),
      );
    }

    // 列表项。
    if (block.bulletLabel.isNotEmpty || block.ordered) {
      final label = block.ordered ? '${block.bulletLabel}.' : block.bulletLabel;
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 24.0,
            child: pw.Text(label, style: _withCjk(cjkFont, 12)),
          ),
          pw.Expanded(
            child: pw.Paragraph(
              style: _withCjk(cjkFont, 12),
              text: _inlinesToString(block.inlines),
            ),
          ),
        ],
      );
    }

    // 空段落。
    if (_inlinesToString(block.inlines).isEmpty) {
      return pw.SizedBox(height: 6);
    }

    // 段落（可能带引用缩进）。
    final para = pw.Paragraph(
      style: _withCjk(cjkFont, 12),
      text: _inlinesToString(block.inlines),
    );
    if (block.blockquote) {
      return pw.Container(
        padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
        decoration: pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: PdfColors.grey, width: 3)),
        ),
        child: para,
      );
    }
    return para;
  }

  /// 行内格式在 PDF 里没有 span 级渲染路径，统一摊平成 Markdown 风格的纯文本，
  /// 以保住「加粗/斜体」等语义（用户可肉眼看出差异），而不是静默丢弃。
  String _inlinesToString(List<_PdfInline> inlines) {
    final out = StringBuffer();
    for (final inl in inlines) {
      var t = inl.text;
      if (inl.code) t = '`$t`';
      if (inl.bold) t = '**$t**';
      if (inl.italic) t = '*$t*';
      if (inl.underline) t = '<u>$t</u>';
      if (inl.link != null && inl.link!.isNotEmpty) t = '[$t](${inl.link})';
      out.write(t);
    }
    return out.toString();
  }

  /// 渲染代码块。
  pw.Widget _codeBlockWidget(String code, String lang) {
    if (code.isEmpty) return pw.SizedBox(height: 2);
    final header = lang.isNotEmpty ? '$lang  ' : '';
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF1E1E1E),
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        '$header$code',
        style: pw.TextStyle(
          font: pw.Font.courier(),
          fontNormal: pw.Font.courier(),
          fontBold: pw.Font.courier(),
          fontItalic: pw.Font.courier(),
          fontBoldItalic: pw.Font.courier(),
          fontSize: 10,
          color: PdfColors.white,
        ),
      ),
    );
  }

  /// 渲染 embed：图片（按尺寸缩排放入页面）、表格、附件、其余未知类型给灰字提示。
  Future<pw.Widget?> _embedToWidget(Map<String, dynamic> embed, pw.Font cjkFont) async {
    // 图片。
    if (embed.containsKey('image')) {
      return _imageWidget(embed['image'].toString(), cjkFont);
    }

    // 自定义表格块。
    if (embed.containsKey('table')) {
      return _tableWidget(embed['table'], cjkFont);
    }

    // 代码块（导出侧不依赖代码块卡片，这里也兜底一下）。
    if (embed.containsKey('code_block')) {
      try {
        final raw = embed['code_block'];
        final map = raw is Map ? raw : jsonDecode(raw.toString());
        final code = (map['code'] ?? '').toString().trim();
        final lang = (map['language'] ?? '').toString();
        return code.isEmpty ? null : _codeBlockWidget(code, lang);
      } catch (_) {
        return _unknownEmbedWidget('code_block', cjkFont);
      }
    }

    // 附件。
    if (embed.containsKey('attachment')) {
      final name = embed['attachment'].toString();
      return pw.Paragraph(
        style: _withCjk(cjkFont, 11, color: PdfColors.grey),
        text: '附件：$name',
      );
    }

    // 思维导图 / 视频等：给一行提示，避免静默丢弃。
    for (final key in embed.keys) {
      if (key == 'image' || key == 'table' || key == 'code_block' || key == 'attachment') {
        continue;
      }
      return _unknownEmbedWidget(key, cjkFont);
    }
    return null;
  }

  /// 渲染图片到 PDF：读取本地文件、按页面宽度等比缩放、居中显示。
  Future<pw.Widget?> _imageWidget(String url, pw.Font cjkFont) async {
    var path = url.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();

    try {
      final f = File(path);
      if (!f.existsSync()) {
        return pw.Paragraph(
          style: _withCjk(cjkFont, 11, color: PdfColors.grey),
          text: '图片（文件不存在：${p.basename(path)}）',
        );
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return null;
      final img = pw.MemoryImage(bytes);

      // 等比缩放到页面正文宽度（A4 减去左右页边距），超高时限制高度。
      const maxW = 460.0;
      const maxH = 400.0;
      final w = img.width!.toDouble();
      final h = img.height!.toDouble();
      if (w <= 0 || h <= 0) return null;
      final ratioW = w > maxW ? maxW / w : 1.0;
      final ratioH = h > maxH ? maxH / h : 1.0;
      final scale = ratioW < ratioH ? ratioW : ratioH;

      return pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        alignment: pw.Alignment.center,
        child: pw.Image(img, width: w * scale, height: h * scale),
      );
    } catch (e) {
      debugPrint('ExportService: failed to embed image $url: $e');
      return pw.Paragraph(
        style: _withCjk(cjkFont, 11, color: PdfColors.grey),
        text: '图片（读取失败：${p.basename(path)}）',
      );
    }
  }

  /// 渲染表格：首行作为表头，其余为数据行。
  pw.Widget? _tableWidget(dynamic raw, pw.Font cjkFont) {
    try {
      final map = raw is Map ? raw : jsonDecode(raw.toString());
      final rowsRaw = map['rows'];
      if (rowsRaw is! List) return _unknownEmbedWidget('table', cjkFont);

      final rows = <List<String>>[];
      for (final r in rowsRaw) {
        if (r is! List) continue;
        rows.add(r.map((c) => _flattenCell(c).trim()).toList());
      }
      if (rows.isEmpty) return null;

      final tableRows = <pw.TableRow>[];
      for (int i = 0; i < rows.length; i++) {
        final isHeader = i == 0;
        tableRows.add(pw.TableRow(
          children: rows[i]
              .map((cell) => pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    color: isHeader ? PdfColor.fromInt(0xFFF5F5F5) : null,
                    child: pw.Text(cell, style: _withCjk(cjkFont, 11, bold: isHeader)),
                  ))
              .toList(),
        ));
      }

      return pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Table(
          children: tableRows,
          border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
        ),
      );
    } catch (e) {
      debugPrint('ExportService: failed to export table: $e');
      return _unknownEmbedWidget('table', cjkFont);
    }
  }

  /// 把一个单元格（`{text, style}` 或纯文本）摊平成纯文本。
  String _flattenCell(dynamic cell) {
    if (cell is String) return cell;
    if (cell is Map) {
      return (cell['text']?.toString() ?? '').trim();
    }
    return cell?.toString() ?? '';
  }

  pw.Widget _unknownEmbedWidget(String kind, pw.Font cjkFont) {
    return pw.Paragraph(
      style: _withCjk(cjkFont, 11, color: PdfColors.grey),
      text: '[$kind]',
    );
  }

  // ---------------------------------------------------------------------------
  // Markdown / HTML / 纯文本
  // ---------------------------------------------------------------------------

  String _toMarkdown(Note note) {
    final buffer = StringBuffer();
    buffer.writeln('# ${note.title}');
    buffer.writeln();

    final trimmed = note.deltaJson.trim();
    if (trimmed.startsWith('[')) {
      buffer.writeln(MarkdownConverter.deltaToMarkdown(note.deltaJson));
    } else {
      final doc = AppFlowyCodec.parseToDocument(note.deltaJson);
      buffer.writeln(AppFlowyCodec.documentToMarkdownString(doc));
    }
    return buffer.toString();
  }

  String _toHtml(Note note) {
    final trimmed = note.deltaJson.trim();
    if (trimmed.startsWith('[')) {
      try {
        final deltaOps = jsonDecode(note.deltaJson) as List;
        var htmlBody = DeltaToHTML.encodeJson(deltaOps);
        htmlBody = _withTablesHtml(deltaOps, htmlBody);
        return _wrapHtml(note, htmlBody);
      } catch (e) {
        debugPrint('Delta to HTML conversion error: $e');
        return '<html><body><h1>${_escapeHtml(note.title)}</h1><pre>${_escapeHtml(note.deltaJson)}</pre></body></html>';
      }
    }

    try {
      final doc = AppFlowyCodec.parseToDocument(note.deltaJson);
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      final htmlBody = md_pkg.markdownToHtml(
        md,
        extensionSet: md_pkg.ExtensionSet.gitHubFlavored,
      );
      return _wrapHtml(note, htmlBody);
    } catch (e) {
      debugPrint('HTML export error: $e');
      return '<html><body><h1>${_escapeHtml(note.title)}</h1><pre>${_escapeHtml(note.deltaJson)}</pre></body></html>';
    }
  }

  String _wrapHtml(Note note, String htmlBody) {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeHtml(note.title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkSystemFont, "Segoe UI", Roboto, sans-serif;
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
    table { border-collapse: collapse; width: 100%; margin: 16px 0; }
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
  }

  /// 把 Delta 中的表格 embed 追加成原生 `<table>` 片段。
  ///
  /// `DeltaToHTML` 只认识 image/video/line，遇到 `{'table': ...}` 这类自定义
  /// embed 会直接忽略；这里把它提取出来单独渲染，保证表格不出现在 HTML 里就丢了。
  String _withTablesHtml(List deltaOps, String htmlBody) {
    final tableHtml = StringBuffer();
    for (final op in deltaOps) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is! Map) continue;
      if (!insert.containsKey('table')) continue;
      final chunk = _tableToHtml(insert['table']);
      if (chunk != null) {
        tableHtml.write('<p>');
        tableHtml.write(chunk);
        tableHtml.write('</p>');
      }
    }
    if (tableHtml.isEmpty) return htmlBody;
    // 追加到正文末尾，避免依赖 DeltaToHTML 的内部输出位置。
    return htmlBody.isEmpty ? tableHtml.toString() : '$htmlBody$tableHtml';
  }

  /// 把单个表格渲染为 HTML `<table>`。
  String? _tableToHtml(dynamic raw) {
    try {
      final map = raw is Map ? raw : jsonDecode(raw.toString());
      final rowsRaw = map['rows'];
      if (rowsRaw is! List) return null;

      final out = StringBuffer();
      out.write('<table>');
      for (var rowIdx = 0; rowIdx < rowsRaw.length; rowIdx++) {
        final r = rowsRaw[rowIdx];
        if (r is! List) continue;
        out.write('<tr>');
        for (final c in r) {
          // 首行渲染成 <th>，浏览器自带粗体与底色，不需要额外样式。
          final tag = rowIdx == 0 ? 'th' : 'td';
          out.write('<$tag>${_escapeHtml(_flattenCell(c))}</$tag>');
        }
        out.write('</tr>');
      }
      out.write('</table>');
      return out.isEmpty ? null : out.toString();
    } catch (_) {
      return null;
    }
  }

  String _toPlainText(Note note) {
    final buffer = StringBuffer();
    buffer.writeln(note.title);
    buffer.writeln();

    final trimmed = note.deltaJson.trim();
    if (trimmed.startsWith('[')) {
      try {
        final ops = jsonDecode(note.deltaJson) as List<dynamic>;
        for (final op in ops) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) {
              buffer.write(insert);
            } else if (insert is Map && insert.containsKey('table')) {
              // 表格在纯文本里用「|」分隔各单元格，保留列结构。
              final map = insert['table'] is Map
                  ? insert['table'] as Map
                  : jsonDecode(insert['table'].toString()) as Map;
              final rows = map['rows'];
              if (rows is List) {
                for (final r in rows) {
                  if (r is List) {
                    buffer.write(r.map(_flattenCell).join(' | '));
                    buffer.write('\n');
                  }
                }
              }
            } else if (insert is Map && insert.containsKey('attachment')) {
              buffer.write('[附件] ${insert['attachment']}');
              buffer.write('\n');
            }
          }
        }
      } catch (_) {
        buffer.write(note.deltaJson);
      }
    } else {
      try {
        final doc = AppFlowyCodec.parseToDocument(note.deltaJson);
        buffer.write(AppFlowyCodec.documentToPlainText(doc));
      } catch (_) {
        buffer.write(note.deltaJson);
      }
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

/// Delta 单元：文本（带属性）或 embed。
class _DeltaUnit {
  final String? text;
  final Map<String, dynamic> attrs;
  final Map<String, dynamic>? embed;

  const _DeltaUnit.text(this.text, this.attrs) : embed = null;
  const _DeltaUnit.embed(this.embed)
      : text = null,
        attrs = const <String, dynamic>{};

  bool get isEmbed => embed != null;
}

/// 段落行内片段累积器：把连续文本按属性切分，行尾换行时整体 flush。
class _ParagraphBuffer {
  final List<_PdfInline> _inlines = [];
  String _text = '';
  Map<String, dynamic> _attrs = const <String, dynamic>{};
  bool _hasContent = false;

  void append(String text, Map<String, dynamic> attrs) {
    _hasContent = true;
    if (text.isEmpty) return;

    // 行内格式变化时切断当前片段。
    if (_text.isNotEmpty && !_attrsEqual(_attrs, attrs)) {
      _push();
    }

    _text += text;
    _attrs = attrs;
  }

  void flush(List<_PdfBlock> out, {int? header, bool ordered = false, String bulletLabel = ''}) {
    _push();
    if (!_hasContent) return;

    _hasContent = false;
    out.add(_PdfBlock.paragraph(
      _inlines,
      headerLevel: header ?? 0,
      ordered: ordered,
      blockquote: _attrs.containsKey('blockquote'),
      bulletLabel: bulletLabel,
    ));
    _inlines.clear();
    _text = '';
    _attrs = const <String, dynamic>{};
  }

  void _push() {
    if (_text.isEmpty) return;
    _inlines.add(_PdfInline(
      _text,
      bold: _attrs['bold'] == true,
      italic: _attrs['italic'] == true,
      code: _attrs['code'] == true,
      underline: _attrs['underline'] == true,
      link: _attrs['link']?.toString(),
    ));
    _text = '';
  }

  bool _attrsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

/// PDF 内容块模型：把 Delta 展平成「块 + 行内片段」两级，避免依赖 Markdown。
class _PdfBlock {
  final pw.Widget? widget;
  final List<_PdfInline> inlines;
  final int headerLevel;
  final bool ordered;
  final bool blockquote;
  final String bulletLabel;

  /// 结构化块（空行、图片、表格、附件提示）。
  const _PdfBlock.widget(this.widget)
      : inlines = const <_PdfInline>[],
        headerLevel = 0,
        ordered = false,
        blockquote = false,
        bulletLabel = '';

  /// 带行内格式的文字块。
  const _PdfBlock.paragraph(this.inlines,
      {this.headerLevel = 0,
      this.ordered = false,
      this.blockquote = false,
      this.bulletLabel = ''})
      : widget = null;

  bool get isWidget => widget != null;
}

/// 行内片段：一段文本及其粗体/斜体/代码/下划线/超链接标记。
class _PdfInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool underline;
  final String? link;

  const _PdfInline(this.text,
      {this.bold = false,
      this.italic = false,
      this.code = false,
      this.underline = false,
      this.link});
}
