import 'dart:convert';
import 'dart:typed_data';

import 'document_model.dart';
import 'docx_writer.dart';
import 'flatten.dart';
import 'matrix.dart';
import 'ooxml_rewriter.dart';
import 'parsers/csv_parser.dart';
import 'parsers/docx_parser.dart';
import 'parsers/md_parser.dart';
import 'parsers/pdf_parser.dart';
import 'parsers/txt_parser.dart';
import 'parsers/xlsx_parser.dart';
import 'pdf_writer.dart';
import 'simple_rewriter.dart';
import 'spreadsheetml_rewriter.dart';
import 'translator.dart';
import 'xlsx_writer.dart';

export 'parsers/pdf_parser.dart' show PdfNoTextLayerException;

/// 文档转换与翻译统一引擎。
///
/// 驱动矩阵中所有 27 个可用格的转换与翻译，遵循：
/// - T1 路径：原地替换文本节点，保证排版与图片零变化
/// - T2 路径：基于 DocumentModel 解析、翻译并由对应 Writer 重构排版与保留图片
/// - 扫描件 PDF 检测：明确抛出 [PdfNoTextLayerException]，阻断空转换
class ConversionEngine {
  ConversionEngine._();

  /// 执行文档转换与翻译。
  static Future<Uint8List> convert({
    required Uint8List bytes,
    required DocFormat sourceFormat,
    required DocFormat targetFormat,
    required bool translate,
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final tier = conversionTier(sourceFormat, targetFormat);
    if (tier == ConversionTier.unavailable) {
      throw UnsupportedError('不支持从 ${sourceFormat.name} 转换到 ${targetFormat.name}');
    }

    // 针对 PDF 源文件：先检查是否存在文字层（避免对扫描件产出空文档）
    if (sourceFormat == DocFormat.pdf) {
      final probeDoc = await PdfParser.parse(bytes);
      if (!probeDoc.hasText) {
        throw const PdfNoTextLayerException();
      }
    }

    // 1. T1 原地回写分支（仅当开启翻译且属于 T1 格）
    if (translate && tier == ConversionTier.t1) {
      if (sourceFormat == DocFormat.docx && targetFormat == DocFormat.docx) {
        return OoxmlRewriter.rewrite(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.xlsx && targetFormat == DocFormat.xlsx) {
        return SpreadsheetmlRewriter.rewrite(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.csv && targetFormat == DocFormat.csv) {
        return SimpleRewriter.rewriteCsv(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.md && targetFormat == DocFormat.md) {
        return SimpleRewriter.rewriteMd(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.txt && targetFormat == DocFormat.txt) {
        return SimpleRewriter.rewriteTxt(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.txt && targetFormat == DocFormat.docx) {
        return SimpleRewriter.txtToDocx(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.txt && targetFormat == DocFormat.pdf) {
        return SimpleRewriter.txtToPdf(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.txt && targetFormat == DocFormat.md) {
        return SimpleRewriter.txtToMd(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
      if (sourceFormat == DocFormat.md && targetFormat == DocFormat.pdf) {
        return SimpleRewriter.mdToPdf(
          bytes,
          sourceLang: sourceLang,
          targetLang: targetLang,
          onProgress: onProgress,
        );
      }
    }

    // 2. T2 或 不翻译 的通用模型流转分支
    // a. 解析为 DocumentModel
    var doc = await _parseToModel(bytes, sourceFormat);

    // b. 如需翻译，送 DocumentTranslator
    if (translate) {
      doc = await DocumentTranslator.translate(
        doc,
        sourceLang: sourceLang,
        targetLang: targetLang,
        onProgress: onProgress,
      );
    }

    // c. 由目标格式 Writer 输出
    return _writeModel(doc, targetFormat);
  }

  static Future<DocumentModel> _parseToModel(Uint8List bytes, DocFormat format) async {
    switch (format) {
      case DocFormat.docx:
        return DocxParser.parse(bytes);
      case DocFormat.xlsx:
        return XlsxParser.parse(bytes);
      case DocFormat.csv:
        return CsvParser.parse(bytes);
      case DocFormat.md:
        return MdParser.parse(bytes);
      case DocFormat.txt:
        return TxtParser.parse(bytes);
      case DocFormat.pdf:
        return PdfParser.parse(bytes);
    }
  }

  static Future<Uint8List> _writeModel(DocumentModel doc, DocFormat targetFormat) async {
    switch (targetFormat) {
      case DocFormat.docx:
        return DocxWriter.write(doc);
      case DocFormat.pdf:
        return PdfWriter.write(doc);
      case DocFormat.md:
        return Uint8List.fromList(utf8.encode(Flatten.toMarkdown(doc)));
      case DocFormat.txt:
        return Uint8List.fromList(utf8.encode(Flatten.toText(doc)));
      case DocFormat.xlsx:
        return XlsxWriter.write(doc);
      case DocFormat.csv:
        return Uint8List.fromList(utf8.encode(Flatten.toCsv(doc)));
    }
  }
}
