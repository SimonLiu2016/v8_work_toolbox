import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// XLSX → Markdown 转换器
///
/// XLSX 本质是 ZIP，`xl/worksheets/sheet1.xml` 等含各 sheet 的单元格数据，
/// `xl/sharedStrings.xml` 含字符串共享表（内联字符串通过索引引用）。
/// 本转换器解析每个 sheet 为 Markdown 表格并用 sheet 名拼接。
/// 不引入 `excel` 包（与项目 archive ^4 / xml ^6 版本冲突），
/// 直接用已有的 archive + xml 包手写解析。
class XlsxToMarkdown {
  XlsxToMarkdown._();

  static const _maxRows = 500;

  /// 从 XLSX 文件路径转换为 Markdown 字符串
  static Future<String> convert(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return convertFromBytes(bytes);
  }

  /// 从字节数据转换（便于测试）
  static String convertFromBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. 读取共享字符串表
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
          // 富文本：拼接所有 <r><t> 子节点
          final buf = StringBuffer();
          for (final r in si.findElements('r')) {
            final rt = r.findElements('t').firstOrNull;
            if (rt != null) buf.write(rt.innerText);
          }
          sharedStrings.add(buf.toString());
        }
      }
    }

    // 2. 读取 workbook.xml 获取 sheet 名称与顺序
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile == null) throw Exception('XLSX 内部未找到 xl/workbook.xml');
    final wbXml = utf8.decode(wbFile.content as List<int>);
    final wbDoc = XmlDocument.parse(wbXml);
    final ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

    final sheets = <(String name, String rId)>[];
    for (final sheet in wbDoc.findAllElements('sheet', namespace: ns)) {
      final name = sheet.getAttribute('name') ?? 'Sheet';
      final rId = sheet.getAttribute('r:id') ?? '';
      sheets.add((name, rId));
    }

    // 3. 读取 workbook.xml.rels 映射 rId → sheetN.xml
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

    // 4. 逐 sheet 解析
    final buffer = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      final (name, rId) = sheets[i];
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

      buffer.writeln('## $name');
      buffer.writeln();

      final rows = sheetDoc.findAllElements('row', namespace: ns).toList();
      var rowCount = 0;
      var truncated = false;

      for (final row in rows) {
        if (rowCount >= _maxRows) {
          truncated = true;
          break;
        }
        final cells = row.findElements('c', namespace: ns);
        final cellValues = <String>[];
        for (final cell in cells) {
          final type = cell.getAttribute('t');
          final vElement = cell.findElements('v', namespace: ns).firstOrNull;
          final inlineValue = cell.findElements('is', namespace: ns).firstOrNull;

          String value = '';
          if (type == 's' && vElement != null) {
            // 共享字符串索引
            final idx = int.tryParse(vElement.innerText) ?? 0;
            value = idx < sharedStrings.length ? sharedStrings[idx] : '';
          } else if (type == 'inlineStr' && inlineValue != null) {
            final t = inlineValue.findElements('t', namespace: ns).firstOrNull;
            value = t?.innerText ?? '';
          } else if (vElement != null) {
            value = vElement.innerText;
          }
          // 转义 Markdown 表格管道符
          value = value.replaceAll('|', '\\|').replaceAll('\n', ' ');
          cellValues.add(value);
        }

        if (cellValues.isNotEmpty) {
          buffer.writeln('| ${cellValues.join(' | ')} |');
          if (rowCount == 0) {
            buffer.writeln('| ${cellValues.map((_) => '---').join(' | ')} |');
          }
          rowCount++;
        }
      }

      if (truncated) {
        buffer.writeln();
        buffer.writeln('> ⚠️ 表格过大，已截断至前 $_maxRows 行');
      }

      buffer.writeln();
    }

    return buffer.toString().trim();
  }
}
