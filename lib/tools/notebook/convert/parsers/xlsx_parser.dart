import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../document_model.dart';

/// XLSX → DocumentModel 解析器。
///
/// 复用 xlsx_to_markdown.dart 的逻辑：按 sheet 分组，
/// 每个 sheet 产出一个标题（HeadingBlock）+ TableBlock。
class XlsxParser {
  XlsxParser._();

  static const _maxRows = 500;

  /// 从 XLSX 字节解析为 DocumentModel。
  static DocumentModel parse(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. 共享字符串表
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

      // 2. workbook.xml
      final wbFile = archive.findFile('xl/workbook.xml');
      if (wbFile == null) return _empty();
      final wbXml = utf8.decode(wbFile.content as List<int>);
      final wbDoc = XmlDocument.parse(wbXml);
      const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

      final sheets = <(String name, String rId)>[];
      for (final sheet in wbDoc.findAllElements('sheet', namespace: ns)) {
        final name = sheet.getAttribute('name') ?? 'Sheet';
        final rId = sheet.getAttribute('r:id') ?? '';
        sheets.add((name, rId));
      }

      // 3. rels
      final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
      final relsMap = <String, String>{};
      if (relsFile != null) {
        final relsXml = utf8.decode(relsFile.content as List<int>);
        final relsDoc = XmlDocument.parse(relsXml);
        for (final rel in relsDoc.findAllElements(
          'Relationship',
          namespace:
              'http://schemas.openxmlformats.org/package/2006/relationships',
        )) {
          final id = rel.getAttribute('Id') ?? '';
          final target = rel.getAttribute('Target') ?? '';
          relsMap[id] = target;
        }
      }

      // 4. 逐 sheet 解析
      final blocks = <DocBlock>[];
      for (var i = 0; i < sheets.length; i++) {
        final (name, rId) = sheets[i];
        String sheetPath;
        if (relsMap.containsKey(rId)) {
          final target = relsMap[rId]!;
          sheetPath =
              target.startsWith('/') ? target.substring(1) : 'xl/$target';
        } else {
          sheetPath = 'xl/worksheets/sheet${i + 1}.xml';
        }

        final sheetFile = archive.findFile(sheetPath);
        if (sheetFile == null) continue;
        final sheetXml = utf8.decode(sheetFile.content as List<int>);
        final sheetDoc = XmlDocument.parse(sheetXml);

        blocks.add(HeadingBlock(name, level: 2));

        final rows = sheetDoc.findAllElements('row', namespace: ns).toList();
        final tableRows = <List<String>>[];
        var rowCount = 0;

        for (final row in rows) {
          if (rowCount >= _maxRows) break;
          final cells = row.findElements('c', namespace: ns);
          final cellValues = <String>[];
          for (final cell in cells) {
            final type = cell.getAttribute('t');
            final vElement =
                cell.findElements('v', namespace: ns).firstOrNull;
            final inlineValue =
                cell.findElements('is', namespace: ns).firstOrNull;

            String value = '';
            if (type == 's' && vElement != null) {
              final idx = int.tryParse(vElement.innerText) ?? 0;
              value = idx < sharedStrings.length ? sharedStrings[idx] : '';
            } else if (type == 'inlineStr' && inlineValue != null) {
              final t = inlineValue.findElements('t', namespace: ns).firstOrNull;
              value = t?.innerText ?? '';
            } else if (vElement != null) {
              value = vElement.innerText;
            }
            cellValues.add(value);
          }

          if (cellValues.isNotEmpty) {
            tableRows.add(cellValues);
            rowCount++;
          }
        }

        if (tableRows.isNotEmpty) {
          blocks.add(TableBlock(tableRows, hasHeader: tableRows.length > 1));
        }
      }

      return DocumentModel(blocks: blocks, sourceFormat: 'xlsx');
    } catch (_) {
      return _empty();
    }
  }

  static DocumentModel _empty() =>
      const DocumentModel(blocks: [], sourceFormat: 'xlsx');
}
