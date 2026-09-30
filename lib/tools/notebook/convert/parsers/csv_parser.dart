import 'dart:convert';
import 'dart:typed_data';

import '../document_model.dart';

/// CSV → DocumentModel 解析器。
///
/// 逐行解析 CSV（支持双引号包裹字段），第一行作为表头。
class CsvParser {
  CsvParser._();

  /// 从 CSV 字节解析为 DocumentModel。
  static DocumentModel parse(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final rows = _parseCsv(text);
    if (rows.isEmpty) {
      return const DocumentModel(blocks: [], sourceFormat: 'csv');
    }
    return DocumentModel(
      blocks: [TableBlock(rows, hasHeader: true)],
      sourceFormat: 'csv',
    );
  }

  /// 解析 CSV 文本为行列表。
  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    final lines = text.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      if (line.isEmpty) continue;
      rows.add(_parseLine(line));
    }
    return rows;
  }

  /// 解析单行 CSV，支持双引号包裹（含逗号和换行）。
  static List<String> _parseLine(String line) {
    final fields = <String>[];
    var pos = 0;
    while (pos <= line.length) {
      if (pos == line.length) {
        // 空结尾字段
        if (fields.isNotEmpty) break;
        fields.add('');
        break;
      }

      if (line[pos] == '"') {
        // 引号包裹字段
        pos++; // 跳过开头引号
        final buf = StringBuffer();
        while (pos < line.length) {
          if (line[pos] == '"') {
            if (pos + 1 < line.length && line[pos + 1] == '"') {
              // 转义引号 ""
              buf.write('"');
              pos += 2;
            } else {
              pos++; // 跳过结尾引号
              break;
            }
          } else {
            buf.write(line[pos]);
            pos++;
          }
        }
        fields.add(buf.toString());
        // 跳过逗号
        if (pos < line.length && line[pos] == ',') pos++;
      } else {
        // 普通字段
        final comma = line.indexOf(',', pos);
        if (comma == -1) {
          fields.add(line.substring(pos));
          break;
        } else {
          fields.add(line.substring(pos, comma));
          pos = comma + 1;
        }
      }
    }
    return fields;
  }
}
