import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/xlsx_to_markdown.dart';

/// 构造最小化 XLSX：含 sharedStrings + workbook + 1 个 sheet
Uint8List _buildMinimalXlsx({
  required String sheetName,
  required List<String> sharedStrings,
  required String sheetXml,
}) {
  final archive = Archive();

  // sharedStrings.xml
  final ssBuffer = StringBuffer();
  ssBuffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  ssBuffer.writeln('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  for (final s in sharedStrings) {
    ssBuffer.writeln('<si><t>$s</t></si>');
  }
  ssBuffer.writeln('</sst>');
  archive.addFile(
      ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(ssBuffer.toString())));

  // workbook.xml
  final wbXml = '<?xml version="1.0"?>\n'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>';
  archive.addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(wbXml)));

  // workbook.xml.rels
  final relsXml = '<?xml version="1.0"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';
  archive.addFile(
      ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(relsXml)));

  // sheet1.xml
  archive.addFile(
      ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheetXml)));

  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}

void main() {
  group('XlsxToMarkdown', () {
    test('简单 2×3 表格转换为 Markdown 表格', () {
      const sharedStrings = ['姓名', '年龄', '城市', '张三', '25', '北京'];
      const sheetXml = '<?xml version="1.0"?>\n'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2" t="s"><v>5</v></c></row>'
          '</sheetData></worksheet>';
      final bytes = _buildMinimalXlsx(
          sheetName: 'Sheet1', sharedStrings: sharedStrings, sheetXml: sheetXml);
      final md = XlsxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('## Sheet1'));
      expect(md, contains('| 姓名 | 年龄 | 城市 |'));
      expect(md, contains('| --- | --- | --- |'));
      expect(md, contains('| 张三 | 25 | 北京 |'));
    });

    test('数值类型单元格直接输出', () {
      const sheetXml = '<?xml version="1.0"?>\n'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>'
          '<row r="1"><c r="A1"><v>42</v></c><c r="B1"><v>3.14</v></c></row>'
          '</sheetData></worksheet>';
      final bytes = _buildMinimalXlsx(
          sheetName: 'Data', sharedStrings: const <String>[], sheetXml: sheetXml);
      final md = XlsxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('| 42 | 3.14 |'));
    });

    test('管道符转义', () {
      const sharedStrings = ['A|B'];
      const sheetXml = '<?xml version="1.0"?>\n'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
          '</sheetData></worksheet>';
      final bytes = _buildMinimalXlsx(
          sheetName: 'Esc', sharedStrings: sharedStrings, sheetXml: sheetXml);
      final md = XlsxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('A\\|B'));
    });

    test('500 行截断', () {
      final rows = StringBuffer();
      for (var i = 1; i <= 600; i++) {
        rows.writeln('<row r="$i"><c r="A$i"><v>$i</v></c></row>');
      }
      final sheetXml = '<?xml version="1.0"?>\n'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData>$rows</sheetData></worksheet>';
      final bytes = _buildMinimalXlsx(
          sheetName: 'Big', sharedStrings: const <String>[], sheetXml: sheetXml);
      final md = XlsxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('已截断至前 500 行'));
      // 不应包含第 600 行
      expect(md, isNot(contains('| 600 |')));
    });
  });
}
