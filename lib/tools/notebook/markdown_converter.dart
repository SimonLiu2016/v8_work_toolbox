import 'dart:convert';

/// Quill Delta ↔ Markdown 双向转换器
class MarkdownConverter {
  // ---------------------------------------------------------------------------
  // Delta → Markdown
  // ---------------------------------------------------------------------------

  /// 将 Quill Delta JSON 转换为 Markdown 字符串
  static String deltaToMarkdown(String deltaJson) {
    try {
      final ops = jsonDecode(deltaJson) as List<dynamic>;
      final buffer = StringBuffer();
      int i = 0;

      while (i < ops.length) {
        final op = ops[i] as Map<String, dynamic>;
        final insert = op['insert'];
        final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();

        if (insert is! String) {
          // Embed (image, video, etc.)
          if (insert is Map) {
            buffer.write(_handleEmbed(insert.cast<String, dynamic>()));
          }
          i++;
          continue;
        }

        // Split by newlines to handle block-level formatting
        final lines = insert.split('\n');
        for (int j = 0; j < lines.length; j++) {
          final line = lines[j];
          if (j > 0) buffer.write('\n');

          if (line.isEmpty && j < lines.length - 1) {
            // Empty line between blocks
            continue;
          }

          if (line.isNotEmpty) {
            buffer.write(_applyInlineFormatting(line, attrs));
          }
        }

        i++;
      }

      return buffer.toString().trimRight();
    } catch (_) {
      return deltaJson;
    }
  }

  static String _applyInlineFormatting(String text, Map<String, dynamic>? attrs) {
    if (attrs == null) return text;

    String result = text;

    // Code (inline)
    if (attrs.containsKey('code') && attrs['code'] == true) {
      return '`$result`';
    }

    // Bold
    if (attrs.containsKey('bold') && attrs['bold'] == true) {
      result = '**$result**';
    }

    // Italic
    if (attrs.containsKey('italic') && attrs['italic'] == true) {
      result = '*$result*';
    }

    // Strikethrough
    if (attrs.containsKey('strike') && attrs['strike'] == true) {
      result = '~~$result~~';
    }

    // Underline (Markdown doesn't have native underline, use HTML)
    if (attrs.containsKey('underline') && attrs['underline'] == true) {
      result = '<u>$result</u>';
    }

    // Link
    if (attrs.containsKey('link')) {
      result = '[$result](${attrs['link']})';
    }

    return result;
  }

  static String _handleEmbed(Map<String, dynamic> embed) {
    if (embed.containsKey('image')) {
      final url = embed['image'].toString();
      return '![]($url)';
    }
    if (embed.containsKey('video')) {
      final url = embed['video'].toString();
      return '[Video]($url)';
    }
    if (embed.containsKey('attachment')) {
      final name = embed['attachment'].toString();
      return '[📎 $name]($name)';
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Markdown → Delta
  // ---------------------------------------------------------------------------

  /// 将 Markdown 字符串转换为 Quill Delta JSON
  static String markdownToDelta(String markdown) {
    final lines = markdown.split('\n');
    final ops = <Map<String, dynamic>>[];

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Code block
      if (line.trimLeft().startsWith('```')) {
        final lang = line.trimLeft().substring(3).trim();
        final codeBuffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          if (codeBuffer.isNotEmpty) codeBuffer.write('\n');
          codeBuffer.write(lines[i]);
          i++;
        }
        ops.add({
          'insert': codeBuffer.toString(),
          'attributes': {'code-block': true, if (lang.isNotEmpty) 'language': lang},
        });
        ops.add({'insert': '\n'});
        i++; // skip closing ```
        continue;
      }

      // Heading
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        ops.add({
          'insert': headingMatch.group(2)!,
          'attributes': {'header': level},
        });
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Horizontal rule
      if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(line)) {
        ops.add({'insert': '\n', 'attributes': {'divider': true}});
        i++;
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        ops.add({
          'insert': line.substring(2),
          'attributes': {'blockquote': true},
        });
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Unordered list
      final ulMatch = RegExp(r'^(\s*)[-*+]\s+(.+)$').firstMatch(line);
      if (ulMatch != null) {
        final indent = (ulMatch.group(1)!.length / 2).floor();
        ops.add({
          'insert': ulMatch.group(2)!,
          'attributes': {'list': 'bullet', if (indent > 0) 'indent': indent},
        });
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Ordered list
      final olMatch = RegExp(r'^(\s*)\d+\.\s+(.+)$').firstMatch(line);
      if (olMatch != null) {
        final indent = (olMatch.group(1)!.length / 2).floor();
        ops.add({
          'insert': olMatch.group(2)!,
          'attributes': {'list': 'ordered', if (indent > 0) 'indent': indent},
        });
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Image
      final imgMatch = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(line);
      if (imgMatch != null) {
        ops.add({'insert': '\n', 'attributes': {}});
        // Image will be handled as embed
        ops.add({'insert': '\n'});
        i++;
        continue;
      }

      // Regular paragraph - parse inline formatting
      if (line.isNotEmpty) {
        _parseInlineMarkdown(line, ops);
        ops.add({'insert': '\n'});
      } else {
        ops.add({'insert': '\n'});
      }

      i++;
    }

    return jsonEncode(ops);
  }

  static void _parseInlineMarkdown(String text, List<Map<String, dynamic>> ops) {
    // Simple inline parsing: bold, italic, code, links
    final pattern = RegExp(
      r'(\*\*(.+?)\*\*)'       // bold
      r'|(\*(.+?)\*)'          // italic
      r'|(`(.+?)`)'            // inline code
      r'|(\[(.+?)\]\((.+?)\))' // link
      r'|(~~(.+?)~~)'          // strikethrough
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      // Text before this match
      if (match.start > lastEnd) {
        ops.add({'insert': text.substring(lastEnd, match.start)});
      }

      if (match.group(2) != null) {
        // Bold
        ops.add({'insert': match.group(2)!, 'attributes': {'bold': true}});
      } else if (match.group(4) != null) {
        // Italic
        ops.add({'insert': match.group(4)!, 'attributes': {'italic': true}});
      } else if (match.group(6) != null) {
        // Inline code
        ops.add({'insert': match.group(6)!, 'attributes': {'code': true}});
      } else if (match.group(8) != null) {
        // Link
        ops.add({'insert': match.group(8)!, 'attributes': {'link': match.group(9)}});
      } else if (match.group(11) != null) {
        // Strikethrough
        ops.add({'insert': match.group(11)!, 'attributes': {'strike': true}});
      }

      lastEnd = match.end;
    }

    // Remaining text after last match
    if (lastEnd < text.length) {
      ops.add({'insert': text.substring(lastEnd)});
    }

    // If no matches found, just add the whole text
    if (lastEnd == 0) {
      ops.add({'insert': text});
    }
  }
}
