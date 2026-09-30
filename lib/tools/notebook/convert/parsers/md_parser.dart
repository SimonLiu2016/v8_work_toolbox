import 'dart:typed_data';

import '../document_model.dart';

/// Markdown → DocumentModel 解析器。
class MdParser {
  MdParser._();

  /// 从 Markdown 字节解析为 DocumentModel。
  static DocumentModel parse(Uint8List bytes) {
    final text = String.fromCharCodes(bytes);
    return parseText(text);
  }

  /// 从 Markdown 文本解析为 DocumentModel（便于测试）。
  static DocumentModel parseText(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final blocks = <DocBlock>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // 代码块 ```
      if (line.startsWith('```')) {
        final lang = line.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        i++; // skip closing ```
        blocks.add(CodeBlock(codeLines.join('\n'), language: lang.isEmpty ? null : lang));
        continue;
      }

      // 水平线
      if (line == '---' || line == '***' || line == '___' ||
          RegExp(r'^-{3,}$').hasMatch(line) ||
          RegExp(r'^\*{3,}$').hasMatch(line) ||
          RegExp(r'^_{3,}$').hasMatch(line)) {
        blocks.add(const HorizontalRuleBlock());
        i++;
        continue;
      }

      // 标题
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!.trim();
        blocks.add(HeadingBlock(text, level: level));
        i++;
        continue;
      }

      // Markdown 表格（| col | col |）
      if (line.startsWith('|') && line.endsWith('|')) {
        final tableLines = <String>[];
        while (i < lines.length &&
            lines[i].startsWith('|') &&
            lines[i].endsWith('|')) {
          tableLines.add(lines[i]);
          i++;
        }
        final tableBlock = _parseTable(tableLines);
        if (tableBlock != null) {
          blocks.add(tableBlock);
        }
        continue;
      }

      // 无序列表
      final unorderedMatch = RegExp(r'^[-*+]\s+(.+)').firstMatch(line);
      if (unorderedMatch != null) {
        blocks.add(ListItemBlock(unorderedMatch.group(1)!, ordered: false));
        i++;
        continue;
      }

      // 有序列表
      final orderedMatch = RegExp(r'^\d+\.\s+(.+)').firstMatch(line);
      if (orderedMatch != null) {
        blocks.add(ListItemBlock(orderedMatch.group(1)!, ordered: true));
        i++;
        continue;
      }

      // 空行
      if (line.trim().isEmpty) {
        // 多个连续空行合并为一个 BlankBlock
        while (i < lines.length && lines[i].trim().isEmpty) {
          i++;
        }
        if (blocks.isNotEmpty && blocks.last is! BlankBlock) {
          blocks.add(const BlankBlock());
        }
        continue;
      }

      // 普通段落
      blocks.add(ParagraphBlock(line));
      i++;
    }

    return DocumentModel(blocks: blocks, sourceFormat: 'md');
  }

  static TableBlock? _parseTable(List<String> tableLines) {
    if (tableLines.isEmpty) return null;

    final rows = <List<String>>[];
    bool hasHeader = false;

    for (final line in tableLines) {
      // 跳过分隔行（| --- | --- |）
      if (RegExp(r'^\|[\s\-:|]+\|$').hasMatch(line)) {
        hasHeader = true;
        continue;
      }
      final cells = line
          .split('|')
          .where((s) => s.isNotEmpty)
          .map((s) => s.trim())
          .toList();
      if (cells.isNotEmpty) rows.add(cells);
    }

    if (rows.isEmpty) return null;
    return TableBlock(rows, hasHeader: hasHeader);
  }
}
