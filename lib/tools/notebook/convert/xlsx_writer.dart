import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'document_model.dart';

/// T2 SpreadsheetML (XLSX) 写出器——将 [DocumentModel] 转换为 .xlsx 字节。
///
/// 特性：
/// - 产出符合 SpreadsheetML 规范的最小合法 XLSX 包结构
/// - 将文档中的 TableBlock 数据写为 sheet1
/// - 支持共享字符串表（sharedStrings.xml）
class XlsxWriter {
  XlsxWriter._();

  /// 将 [DocumentModel] 转换为 .xlsx 文件的原始字节。
  static Future<Uint8List> write(DocumentModel doc) async {
    final archive = Archive();

    // 提取表格行
    final rows = <List<String>>[];
    for (final block in doc.blocks) {
      if (block is TableBlock) {
        rows.addAll(block.rows);
      }
    }
    if (rows.isEmpty) {
      rows.add(['']);
    }

    // 1. 构建共享字符串表
    final stringMap = <String, int>{};
    final stringList = <String>[];

    int getOrAddString(String s) {
      return stringMap.putIfAbsent(s, () {
        final idx = stringList.length;
        stringList.add(s);
        return idx;
      });
    }

    // 2. 构建 sheet1.xml
    final sheetDataXml = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final rowNum = r + 1;
      sheetDataXml.write('    <row r="$rowNum">\r\n');
      for (var c = 0; c < row.length; c++) {
        final cellVal = row[c];
        final colLetter = _columnName(c);
        final cellRef = '$colLetter$rowNum';
        final strIndex = getOrAddString(cellVal);
        sheetDataXml.write('      <c r="$cellRef" t="s"><v>$strIndex</v></c>\r\n');
      }
      sheetDataXml.write('    </row>\r\n');
    }

    final sheet1Xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\r\n'
        '  <sheetData>\r\n'
        '${sheetDataXml.toString()}'
        '  </sheetData>\r\n'
        '</worksheet>';
    archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheet1Xml)));

    // 3. 构建 sharedStrings.xml
    final sstXml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${stringList.length}" uniqueCount="${stringList.length}">\r\n');
    for (final s in stringList) {
      sstXml.write('  <si><t xml:space="preserve">${_escapeXml(s)}</t></si>\r\n');
    }
    sstXml.write('</sst>');
    archive.addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(sstXml.toString())));

    // 4. xl/workbook.xml
    final workbookXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\r\n'
        '  <sheets>\r\n'
        '    <sheet name="Sheet1" sheetId="1" r:id="rId1"/>\r\n'
        '  </sheets>\r\n'
        '</workbook>';
    archive.addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbookXml)));

    // 5. xl/_rels/workbook.xml.rels
    final wbRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\r\n'
        '  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\r\n'
        '  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>\r\n'
        '</Relationships>';
    archive.addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(wbRelsXml)));

    // 6. _rels/.rels
    final rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\r\n'
        '  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\r\n'
        '</Relationships>';
    archive.addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRelsXml)));

    // 7. [Content_Types].xml
    final contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\r\n'
        '  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\r\n'
        '  <Default Extension="xml" ContentType="application/xml"/>\r\n'
        '  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\r\n'
        '  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\r\n'
        '  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\r\n'
        '</Types>';
    archive.addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypesXml)));

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static String _columnName(int colIndex) {
    var name = '';
    var num = colIndex;
    while (num >= 0) {
      name = String.fromCharCode((num % 26) + 65) + name;
      num = (num ~/ 26) - 1;
    }
    return name;
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
