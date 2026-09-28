import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/ops_models.dart';

class ExcelService {
  ExcelService._();
  static final ExcelService instance = ExcelService._();

  Future<ExcelData> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Excel 文件不存在: $filePath');
    }
    final bytes = await file.readAsBytes();
    return parseBytes(bytes);
  }

  ExcelData parseBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Read shared strings table
    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final ssXml = utf8.decode(ssFile.content as List<int>);
      final doc = XmlDocument.parse(ssXml);
      for (final si in doc.findAllElements('si')) {
        final t = si.findElements('t').firstOrNull;
        if (t != null) {
          sharedStrings.add(t.innerText);
        } else {
          final buf = StringBuffer();
          for (final r in si.findElements('r')) {
            final rt = r.findElements('t').firstOrNull;
            if (rt != null) buf.write(rt.innerText);
          }
          sharedStrings.add(buf.toString());
        }
      }
    }

    // 2. Read workbook.xml for sheet names
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile == null) {
      throw Exception('无法识别的 Excel 文件格式 (缺失 xl/workbook.xml)');
    }
    final wbXml = utf8.decode(wbFile.content as List<int>);
    final wbDoc = XmlDocument.parse(wbXml);
    const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

    final sheetInfos = <(String name, String rId)>[];
    for (final s in wbDoc.findAllElements('sheet', namespace: ns)) {
      final name = s.getAttribute('name') ?? 'Sheet';
      final rId = s.getAttribute('r:id') ?? '';
      sheetInfos.add((name, rId));
    }

    // 3. Read rels
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    final relsMap = <String, String>{};
    if (relsFile != null) {
      final relsXml = utf8.decode(relsFile.content as List<int>);
      final relsDoc = XmlDocument.parse(relsXml);
      for (final rel in relsDoc.findAllElements('Relationship',
          namespace: 'http://schemas.openxmlformats.org/package/2006/relationships')) {
        final id = rel.getAttribute('Id') ?? '';
        final target = rel.getAttribute('Target') ?? '';
        relsMap[id] = target;
      }
    }

    // 4. Parse each sheet
    final List<SheetData> sheets = [];

    for (var i = 0; i < sheetInfos.length; i++) {
      final (name, rId) = sheetInfos[i];
      String sheetPath;
      if (relsMap.containsKey(rId)) {
        final target = relsMap[rId]!;
        sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      } else {
        sheetPath = 'xl/worksheets/sheet${i + 1}.xml';
      }

      final sheetFile = archive.findFile(sheetPath);
      if (sheetFile == null) continue;

      final sheetXml = utf8.decode(sheetFile.content as List<int>);
      final sheetDoc = XmlDocument.parse(sheetXml);

      final rowElements = sheetDoc.findAllElements('row', namespace: ns).toList();
      final tableRows = <List<String>>[];

      for (final rowElem in rowElements) {
        final rowData = <String>[];
        int expectedCol = 0;

        for (final cell in rowElem.findAllElements('c', namespace: ns)) {
          final r = cell.getAttribute('r');
          if (r != null) {
            final colIdx = _colIndexFromRef(r);
            while (expectedCol < colIdx) {
              rowData.add('');
              expectedCol++;
            }
          }

          final type = cell.getAttribute('t');
          String val = '';

          final vElem = cell.findElements('v', namespace: ns).firstOrNull;
          if (vElem != null) {
            final raw = vElem.innerText.trim();
            if (type == 's') {
              final idx = int.tryParse(raw) ?? -1;
              if (idx >= 0 && idx < sharedStrings.length) {
                val = sharedStrings[idx];
              }
            } else if (type == 'b') {
              val = raw == '1' ? 'TRUE' : 'FALSE';
            } else {
              val = raw;
            }
          } else {
            final isElem = cell.findElements('is', namespace: ns).firstOrNull;
            if (isElem != null) {
              val = isElem.innerText.trim();
            }
          }

          rowData.add(val);
          expectedCol++;
        }

        if (rowData.any((c) => c.isNotEmpty)) {
          tableRows.add(rowData);
        }
      }

      List<String> headers = [];
      List<List<String>> dataRows = [];

      if (tableRows.isNotEmpty) {
        headers = tableRows.first;
        if (tableRows.length > 1) {
          dataRows = tableRows.sublist(1);
        }
      }

      sheets.add(SheetData(
        name: name,
        headers: headers,
        rows: dataRows,
      ));
    }

    return ExcelData(sheets: sheets);
  }

  static int _colIndexFromRef(String ref) {
    int col = 0;
    for (int i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else {
        break;
      }
    }
    return col - 1;
  }
}
