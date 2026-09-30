import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/conversion_engine.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/matrix.dart';

void main() {
  group('ConversionEngine 与矩阵行为契约测试', () {
    test('不可用格被拒绝执行并抛出 UnsupportedError', () async {
      final dummyBytes = Uint8List.fromList(utf8.encode('test'));
      expect(
        () => ConversionEngine.convert(
          bytes: dummyBytes,
          sourceFormat: DocFormat.docx,
          targetFormat: DocFormat.xlsx, // 矩阵声明为不可用
          translate: false,
          sourceLang: 'en',
          targetLang: 'zh',
        ),
        throwsUnsupportedError,
      );
    });

    test('纯格式转换（不翻译）可在可用格上直接生成合法格式产物', () async {
      final csvBytes = Uint8List.fromList(utf8.encode('Name,Age\nBob,20\n'));
      // csv -> md (T2)
      final mdBytes = await ConversionEngine.convert(
        bytes: csvBytes,
        sourceFormat: DocFormat.csv,
        targetFormat: DocFormat.md,
        translate: false,
        sourceLang: 'en',
        targetLang: 'zh',
      );
      final mdText = utf8.decode(mdBytes);
      expect(mdText, contains('| Name | Age |'));
      expect(mdText, contains('| Bob | 20 |'));
    });

    test('csv -> xlsx 纯转换生成合法的 ZIP 结构', () async {
      final csvBytes = Uint8List.fromList(utf8.encode('Col1,Col2\nVal1,Val2\n'));
      final xlsxBytes = await ConversionEngine.convert(
        bytes: csvBytes,
        sourceFormat: DocFormat.csv,
        targetFormat: DocFormat.xlsx,
        translate: false,
        sourceLang: 'en',
        targetLang: 'zh',
      );
      expect(xlsxBytes, isNotEmpty);
      // ZIP 头部标志 PK (0x50, 0x4B)
      expect(xlsxBytes[0], 0x50);
      expect(xlsxBytes[1], 0x4B);
    });

    test('扫描版 PDF 无文字层时明确报告 PdfNoTextLayerException', () async {
      // 构造一个不含任何文字对象流的空白 PDF
      const blankPdf = '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>\nendobj\n'
          'xref\n0 4\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n'
          'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n190\n%%EOF';
      final pdfBytes = Uint8List.fromList(utf8.encode(blankPdf));

      expect(
        () => ConversionEngine.convert(
          bytes: pdfBytes,
          sourceFormat: DocFormat.pdf,
          targetFormat: DocFormat.txt,
          translate: false,
          sourceLang: 'en',
          targetLang: 'zh',
        ),
        throwsA(isA<PdfNoTextLayerException>()),
      );
    });
  });
}
