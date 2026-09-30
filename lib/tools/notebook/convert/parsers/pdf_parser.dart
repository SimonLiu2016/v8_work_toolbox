import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../pdf_image_extractor.dart';
import '../document_model.dart';

/// PDF → DocumentModel 解析器。
///
/// 复用 pdf_to_markdown.dart 的 JXA 脚本提取文字层；
/// 图片通过 PdfImageExtractor 提取。
/// 无文字层时抛出 PdfNoTextLayerException。
class PdfParser {
  PdfParser._();

  static const String _jxaScript = r'''
function run(argv) {
  ObjC.import("PDFKit");
  ObjC.import("Foundation");
  var url = $.NSURL.fileURLWithPath(argv[0]);
  var doc = $.PDFDocument.alloc.initWithURL(url);
  if (!doc) return "[]";
  var pages = [];
  for (var p = 0; p < doc.pageCount; p++) {
    var page = doc.pageAtIndex(p);
    var attr = page.attributedString;
    if (!attr) { pages.push([]); continue; }
    var len = attr.length;
    var runs = [];
    var idx = 0;
    while (idx < len) {
      var effRange = $.NSMakeRange(0, 0);
      var attrs = attr.attributesAtIndexEffectiveRange(idx, effRange);
      var size = 0;
      var bold = false;
      try {
        var f = attrs.objectForKey("NSFont");
        if (f) {
          size = f.pointSize;
          var name = f.fontName.js;
          if (typeof name === 'string') {
            bold = name.indexOf('Bold') >= 0 || name.indexOf('Black') >= 0;
          }
        }
      } catch (e) { size = 0; bold = false; }
      var effLen = effRange.length;
      if (effLen <= 0) effLen = 1;
      var end = idx + effLen;
      if (end > len) end = len;
      var text = attr.string.js.substring(idx, end);
      runs.push([size, text, bold]);
      idx = end;
    }
    pages.push(runs);
  }
  return JSON.stringify(pages);
}
''';

  /// 从 PDF 文件路径解析为 DocumentModel。
  /// 无文字层时抛 PdfNoTextLayerException。
  static Future<DocumentModel> parseFromPath(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    return parseFromBytes(bytes, pdfPath: pdfPath);
  }

  /// 从 PDF 字节解析为 DocumentModel。
  static Future<DocumentModel> parse(Uint8List bytes) => parseFromBytes(bytes);

  /// 从 PDF 字节解析为 DocumentModel。
  static Future<DocumentModel> parseFromBytes(
    Uint8List bytes, {
    String? pdfPath,
  }) async {
    // 提取图片
    List<PdfExtractedImage> pdfImages = [];
    try {
      pdfImages = PdfImageExtractor.extract(bytes);
    } catch (_) {
      // 图片提取失败不影响文字提取
    }

    final images = <String, DocImage>{};
    for (final img in pdfImages) {
      final key =
          'p${img.pageIndex}_${img.width}x${img.height}_${img.bytes.length}';
      images[key] = DocImage(
        key: key,
        bytes: img.bytes,
        mimeType: img.mime,
      );
    }

    // 提取文字层（通过临时文件或直接用已有路径）
    String? resolvedPath = pdfPath;
    File? tempFile;
    if (resolvedPath == null) {
      tempFile = File('${Directory.systemTemp.path}/pdf_parser_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await tempFile.writeAsBytes(bytes);
      resolvedPath = tempFile.path;
    }

    try {
      final proc = await Process.run(
        'osascript',
        ['-l', 'JavaScript', '-e', _jxaScript, resolvedPath],
      );

      if (proc.exitCode != 0) {
        throw const PdfNoTextLayerException();
      }

      final raw = (proc.stdout as String).trim();
      if (raw.isEmpty || raw == '[]') {
        throw const PdfNoTextLayerException();
      }

      final List<dynamic> pages = jsonDecode(raw) as List<dynamic>;
      if (pages.isEmpty || pages.every((p) => (p as List).isEmpty)) {
        throw const PdfNoTextLayerException();
      }

      final blocks = _buildBlocks(pages, pdfImages);
      return DocumentModel(blocks: blocks, images: images, sourceFormat: 'pdf');
    } finally {
      await tempFile?.delete().catchError((_) => tempFile!);
    }
  }

  static List<DocBlock> _buildBlocks(
    List<dynamic> pages,
    List<PdfExtractedImage> pdfImages,
  ) {
    final blocks = <DocBlock>[];
    final imagesByPage = <int, List<PdfExtractedImage>>{};
    for (final img in pdfImages) {
      imagesByPage.putIfAbsent(img.pageIndex, () => []).add(img);
    }

    for (var p = 0; p < pages.length; p++) {
      final page = pages[p] as List<dynamic>;

      // 收集文字
      final buf = StringBuffer();
      for (final run in page) {
        final text = run[1] as String;
        if (text.trim().isNotEmpty) buf.write(text);
      }

      final text = buf.toString().trim();
      if (text.isNotEmpty) {
        // 按换行拆段落
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            blocks.add(const BlankBlock());
          } else {
            blocks.add(ParagraphBlock(trimmed));
          }
        }
      }

      // 图片
      for (final img in imagesByPage[p] ?? []) {
        final key =
            'p${img.pageIndex}_${img.width}x${img.height}_${img.bytes.length}';
        blocks.add(ImageBlock(key));
      }
    }

    return blocks;
  }
}

/// 无文字层（扫描件）异常。
class PdfNoTextLayerException implements Exception {
  final String message;
  const PdfNoTextLayerException([this.message = '该 PDF 未包含可提取的文字层（可能是扫描图片文档）']);

  @override
  String toString() => message;
}
