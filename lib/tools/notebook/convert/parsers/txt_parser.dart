import 'dart:convert';
import 'dart:typed_data';

import '../document_model.dart';

/// TXT → DocumentModel 解析器。
///
/// 每段（由空行分隔）→ ParagraphBlock，完全空行 → BlankBlock。
class TxtParser {
  TxtParser._();

  /// 从 TXT 字节解析为 DocumentModel。
  static DocumentModel parse(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return parseText(text);
  }

  /// 从纯文本解析为 DocumentModel（便于测试）。
  static DocumentModel parseText(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final blocks = <DocBlock>[];

    final paragraphLines = <String>[];

    void flushParagraph() {
      if (paragraphLines.isEmpty) return;
      final content = paragraphLines.join('\n').trim();
      if (content.isNotEmpty) {
        blocks.add(ParagraphBlock(content));
      }
      paragraphLines.clear();
    }

    for (final line in lines) {
      if (line.trim().isEmpty) {
        flushParagraph();
        if (blocks.isNotEmpty && blocks.last is! BlankBlock) {
          blocks.add(const BlankBlock());
        }
      } else {
        paragraphLines.add(line);
      }
    }
    flushParagraph();

    return DocumentModel(blocks: blocks, sourceFormat: 'txt');
  }
}
