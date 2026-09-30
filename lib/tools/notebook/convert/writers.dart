import 'dart:convert';
import 'dart:typed_data';

import 'matrix.dart';
import 'parsers/docx_parser.dart';
import 'parsers/xlsx_parser.dart';
import 'parsers/csv_parser.dart';
import 'parsers/md_parser.dart';
import 'flatten.dart';

import 'docx_writer.dart';
import 'pdf_writer.dart';
import 'xlsx_writer.dart';

/// 剩余格式 writers——T2 转换实现。
class Writers {
  Writers._();

  static void register() {
    registerConverter(DocFormat.docx, DocFormat.pdf, 'writers.docx_to_pdf');
    registerConverter(DocFormat.md, DocFormat.docx, 'writers.md_to_docx');
    registerConverter(DocFormat.pdf, DocFormat.pdf, 'writers.pdf_to_pdf');
    registerConverter(DocFormat.xlsx, DocFormat.docx, 'writers.xlsx_to_docx');
    registerConverter(DocFormat.xlsx, DocFormat.pdf, 'writers.xlsx_to_pdf');
    registerConverter(DocFormat.xlsx, DocFormat.csv, 'writers.xlsx_to_csv');
    registerConverter(DocFormat.csv, DocFormat.docx, 'writers.csv_to_docx');
    registerConverter(DocFormat.csv, DocFormat.pdf, 'writers.csv_to_pdf');
    registerConverter(DocFormat.csv, DocFormat.xlsx, 'writers.csv_to_xlsx');
  }

  // ─── docx → pdf ───────────────────────────────────────────────────────────

  static Future<Uint8List> docxToPdf(Uint8List bytes) async {
    final doc = DocxParser.parse(bytes);
    return PdfWriter.write(doc);
  }

  // ─── md → docx ────────────────────────────────────────────────────────────

  static Future<Uint8List> mdToDocx(Uint8List bytes) async {
    final doc = MdParser.parse(bytes);
    return DocxWriter.write(doc);
  }

  // ─── pdf → pdf ────────────────────────────────────────────────────────────

  static Future<Uint8List> pdfToPdf(Uint8List bytes) async {
    return bytes;
  }

  // ─── xlsx → docx ──────────────────────────────────────────────────────────

  static Future<Uint8List> xlsxToDocx(Uint8List bytes) async {
    final doc = XlsxParser.parse(bytes);
    return DocxWriter.write(doc);
  }

  // ─── xlsx → pdf ───────────────────────────────────────────────────────────

  static Future<Uint8List> xlsxToPdf(Uint8List bytes) async {
    final doc = XlsxParser.parse(bytes);
    return PdfWriter.write(doc);
  }

  // ─── xlsx → csv ───────────────────────────────────────────────────────────

  static Future<Uint8List> xlsxToCsv(Uint8List bytes) async {
    final doc = XlsxParser.parse(bytes);
    final csv = Flatten.toCsv(doc);
    return _utf8(csv);
  }

  // ─── csv → docx ───────────────────────────────────────────────────────────

  static Future<Uint8List> csvToDocx(Uint8List bytes) async {
    final doc = CsvParser.parse(bytes);
    return DocxWriter.write(doc);
  }

  // ─── csv → pdf ────────────────────────────────────────────────────────────

  static Future<Uint8List> csvToPdf(Uint8List bytes) async {
    final doc = CsvParser.parse(bytes);
    return PdfWriter.write(doc);
  }

  // ─── csv → xlsx ───────────────────────────────────────────────────────────

  static Future<Uint8List> csvToXlsx(Uint8List bytes) async {
    final doc = CsvParser.parse(bytes);
    return XlsxWriter.write(doc);
  }

  // ─── 工具 ─────────────────────────────────────────────────────────────────

  static Uint8List _utf8(String text) =>
      Uint8List.fromList(utf8.encode(text));
}
