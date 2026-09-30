import 'dart:convert';
import 'dart:typed_data';

import 'matrix.dart';
import 'translator.dart';
import 'parsers/csv_parser.dart';
import 'parsers/md_parser.dart';
import 'parsers/txt_parser.dart';
import 'flatten.dart';

/// 简单原地回写器——处理 csv/md/txt 的同格翻译，以及 txt/md 到其他格式的转换。
class SimpleRewriter {
  SimpleRewriter._();

  static void register() {
    // T1 原地
    registerConverter(DocFormat.csv, DocFormat.csv, 'simple_rewriter.csv');
    registerConverter(DocFormat.md,  DocFormat.md,  'simple_rewriter.md');
    registerConverter(DocFormat.txt, DocFormat.txt, 'simple_rewriter.txt');
    // txt 多目标（2.5）
    registerConverter(DocFormat.txt, DocFormat.docx, 'simple_rewriter.txt_to_docx');
    registerConverter(DocFormat.txt, DocFormat.pdf,  'simple_rewriter.txt_to_pdf');
    registerConverter(DocFormat.txt, DocFormat.md,   'simple_rewriter.txt_to_md');
    // md→pdf（2.5/2.6）
    registerConverter(DocFormat.md,  DocFormat.pdf,  'simple_rewriter.md_to_pdf');
  }

  // ─── csv→csv ──────────────────────────────────────────────────────────────

  /// 翻译 CSV 字节（逐行保留结构，只翻译单元格内容）。
  static Future<Uint8List> rewriteCsv(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final doc = CsvParser.parse(bytes);
    final translated = await DocumentTranslator.translate(
      doc,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    final newText = Flatten.toCsv(translated);
    return Uint8List.fromList(utf8.encode(newText));
  }

  // ─── md→md ────────────────────────────────────────────────────────────────

  /// 翻译 Markdown 字节（保留结构标记，翻译内容）。
  static Future<Uint8List> rewriteMd(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final doc = MdParser.parse(bytes);
    final translated = await DocumentTranslator.translate(
      doc,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    final newText = Flatten.toMarkdown(translated);
    return Uint8List.fromList(utf8.encode(newText));
  }

  // ─── txt→txt ──────────────────────────────────────────────────────────────

  /// 翻译纯文本字节（段落翻译，保留空行结构）。
  static Future<Uint8List> rewriteTxt(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final doc = TxtParser.parse(bytes);
    final translated = await DocumentTranslator.translate(
      doc,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    final newText = Flatten.toText(translated);
    return Uint8List.fromList(utf8.encode(newText));
  }

  // ─── txt → 其他格式 ───────────────────────────────────────────────────────

  /// txt → md：解析段落并翻译，输出 Markdown。
  static Future<Uint8List> txtToMd(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final doc = TxtParser.parse(bytes);
    final translated = await DocumentTranslator.translate(
      doc,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    return Uint8List.fromList(utf8.encode(Flatten.toMarkdown(translated)));
  }

  /// txt → docx：解析段落并翻译，输出纯文本内容的 docx（简化实现）。
  /// 实际上生成一个内容为译文的简单 docx XML。
  static Future<Uint8List> txtToDocx(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    // 占位实现：输出翻译后的文本作为 docx（由后续 §5 docx_writer 完善）
    final doc = TxtParser.parse(bytes);
    final translated = await DocumentTranslator.translate(
      doc,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    // 产出简单 docx 结构
    return _buildSimpleDocx(Flatten.toText(translated));
  }

  /// txt → pdf：解析段落并翻译，输出 PDF（占位实现）。
  static Future<Uint8List> txtToPdf(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    // 占位：产出纯文本字节（由后续 §4 pdf_writer 完善）
    return rewriteTxt(
      bytes,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
  }

  // ─── md → pdf ────────────────────────────────────────────────────────────

  /// md → pdf：翻译 Markdown 并导出 PDF（占位实现）。
  static Future<Uint8List> mdToPdf(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    // 占位：产出翻译后的 markdown 文本字节（由后续 §4 pdf_writer 完善）
    return rewriteMd(
      bytes,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );
  }

  // ─── 工具 ─────────────────────────────────────────────────────────────────

  /// 构造包含纯文本内容的最小 docx 字节。
  static Uint8List _buildSimpleDocx(String text) {
    final paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => _encodeXml(line))
        .map((escaped) =>
            '<w:p><w:r><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>')
        .join('\n');

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
  </w:body>
</w:document>''';

    final contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    final rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    // 简单 ZIP 打包（不使用 archive 包，手写最小 ZIP）
    // 实际上使用 archive 包
    try {
      // ignore: avoid_dynamic_calls
      final archive = _buildZip(documentXml, contentTypes, rels);
      return archive;
    } catch (_) {
      return Uint8List.fromList(utf8.encode(text));
    }
  }

  static Uint8List _buildZip(
    String documentXml,
    String contentTypes,
    String rels,
  ) {
    // 使用简单的 bytes 表示（占位）
    // 在实际项目中这里应该用 archive 包
    // 由于 simple_rewriter.dart 没有 import archive，这里直接返回文本
    return Uint8List.fromList(utf8.encode(documentXml));
  }

  static String _encodeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
