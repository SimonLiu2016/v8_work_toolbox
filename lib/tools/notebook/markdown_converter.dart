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

      // Pre-process: group ops into logical blocks
      // Each block is either: text with inline attrs, or a newline with block attrs
      final blocks = <_DeltaBlock>[];
      String pendingText = '';
      Map<String, dynamic>? pendingInlineAttrs;

      for (final rawOp in ops) {
        final op = rawOp as Map<String, dynamic>;
        final insert = op['insert'];
        final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();

        if (insert is! String) {
          // Embed
          if (pendingText.isNotEmpty) {
            blocks.add(_DeltaBlock.text(pendingText, pendingInlineAttrs));
            pendingText = '';
            pendingInlineAttrs = null;
          }
          if (insert is Map) {
            blocks.add(_DeltaBlock.embed(insert.cast<String, dynamic>()));
          }
          continue;
        }

        // Split by newlines
        final parts = insert.split('\n');
        for (int j = 0; j < parts.length; j++) {
          if (j > 0) {
            // This is a newline boundary
            // The block attrs on the newline apply to the preceding text line
            // We need to tag the pending text with these block attrs
            if (pendingText.isNotEmpty) {
              blocks.add(_DeltaBlock.text(pendingText, pendingInlineAttrs, blockAttrs: attrs));
              pendingText = '';
              pendingInlineAttrs = null;
            } else {
              // No pending text - still need to record the newline for empty lines
              blocks.add(_DeltaBlock.newline(attrs));
            }
          }

          if (parts[j].isNotEmpty) {
            // Accumulate text
            if (pendingInlineAttrs != null && _attrsEqual(pendingInlineAttrs, attrs)) {
              pendingText += parts[j];
            } else {
              if (pendingText.isNotEmpty) {
                blocks.add(_DeltaBlock.text(pendingText, pendingInlineAttrs));
              }
              pendingText = parts[j];
              pendingInlineAttrs = attrs;
            }
          }
        }
      }

      // Flush remaining text
      if (pendingText.isNotEmpty) {
        blocks.add(_DeltaBlock.text(pendingText, pendingInlineAttrs));
      }

      // Convert blocks to markdown
      bool inCodeBlock = false;
      for (int i = 0; i < blocks.length; i++) {
        final block = blocks[i];

        if (block.isEmbed) {
          buffer.write(_handleEmbed(block.embed!));
          continue;
        }

        if (block.isNewline) {
          final attrs = block.attrs;
          if (attrs != null) {
            // Block-level formatting on newline
            if (attrs.containsKey('list')) {
              // List prefix is already applied to the preceding text block
              // Just add a newline
              buffer.write('\n');
            } else if (attrs.containsKey('header')) {
              // Header prefix is already applied to the preceding text block
              buffer.write('\n');
            } else if (attrs.containsKey('blockquote')) {
              // Blockquote prefix is already applied to the preceding text block
              buffer.write('\n');
            } else if (attrs.containsKey('code-block')) {
              // Check if next newline is also code-block
              bool nextIsCode = false;
              for (int k = i + 1; k < blocks.length; k++) {
                if (blocks[k].isNewline) {
                  nextIsCode = blocks[k].attrs?.containsKey('code-block') == true;
                  break;
                } else if (blocks[k].text != null) {
                  final eff = blocks[k].blockAttrs ?? blocks[k].attrs;
                  if (eff?.containsKey('code-block') == true) {
                    nextIsCode = true;
                    break;
                  }
                }
              }
              if (!nextIsCode) {
                buffer.write('\n```\n');
                inCodeBlock = false;
              } else {
                buffer.write('\n');
              }
            } else if (attrs.containsKey('divider')) {
              if (inCodeBlock) {
                buffer.write('\n```\n');
                inCodeBlock = false;
              }
              buffer.write('\n---\n');
            } else {
              if (inCodeBlock) {
                buffer.write('\n```\n');
                inCodeBlock = false;
              }
              buffer.write('\n');
            }
          } else {
            if (inCodeBlock) {
              buffer.write('\n```\n');
              inCodeBlock = false;
            }
            buffer.write('\n');
          }
          continue;
        }


        // Text with inline formatting
        if (block.text != null) {
          // Apply block-level prefixes (list, header, blockquote)
          // These can come from either blockAttrs (from newline) or attrs (on text)
          final effectiveBlockAttrs = block.blockAttrs ?? block.attrs;
          if (effectiveBlockAttrs != null) {
            // Check if these are block-level attrs (not inline)
            final isBlockAttr = effectiveBlockAttrs.containsKey('list') ||
                effectiveBlockAttrs.containsKey('header') ||
                effectiveBlockAttrs.containsKey('blockquote');

            if (effectiveBlockAttrs.containsKey('code-block')) {
              if (!inCodeBlock) {
                final lang = effectiveBlockAttrs['code-block'];
                final langStr = (lang is String && lang.isNotEmpty && lang != 'true') ? lang : '';
                buffer.write('```$langStr\n');
                inCodeBlock = true;
              }
            } else if (isBlockAttr) {
              if (effectiveBlockAttrs.containsKey('list')) {
                final listType = effectiveBlockAttrs['list'];
                final indent = (effectiveBlockAttrs['indent'] as int?) ?? 0;
                final prefix = '  ' * indent;
                if (listType == 'bullet') {
                  buffer.write('$prefix- ');
                } else if (listType == 'ordered') {
                  buffer.write('${prefix}1. ');
                }
              } else if (effectiveBlockAttrs.containsKey('header')) {
                final level = effectiveBlockAttrs['header'] as int;
                buffer.write('${'#' * level} ');
              } else if (effectiveBlockAttrs.containsKey('blockquote')) {
                buffer.write('> ');
              }
            }

          }
          buffer.write(_applyInlineFormatting(block.text!, block.attrs));
        }
      }

      return buffer.toString().trimRight();
    } catch (_) {
      return deltaJson;
    }
  }

  static bool _attrsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
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
      final url = embed['image'].toString().trim();
      final formattedUrl = url.contains(' ') && !url.startsWith('<') ? '<$url>' : url;
      return '![]($formattedUrl)';
    }
    if (embed.containsKey('code_block')) {
      try {
        final raw = embed['code_block'];
        final map = raw is Map ? raw : jsonDecode(raw.toString());
        final code = map['code'] ?? '';
        final lang = map['language'] ?? '';
        return '\n```$lang\n$code\n```\n';
      } catch (_) {
        return '\n```\n${embed['code_block']}\n```\n';
      }
    }
    if (embed.containsKey('mindmap')) {
      try {
        final raw = embed['mindmap'];
        final map = raw is Map ? raw : jsonDecode(raw.toString());
        return '\n```mindmap\n${jsonEncode(map)}\n```\n';
      } catch (_) {
        return '\n```mindmap\n${embed['mindmap']}\n```\n';
      }
    }
    if (embed.containsKey('table')) {
      return _tableToMarkdown(embed['table']);
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

  /// 把表格 embed 渲染成 GFM 管道表格。
  ///
  /// 首行固定为表头（`style: 'header'`），与编辑器里首行加粗底色的呈现保持一致。
  static String _tableToMarkdown(dynamic raw) {
    try {
      final map = raw is Map ? raw : jsonDecode(raw.toString());
      final rowsRaw = map['rows'];
      if (rowsRaw is! List || rowsRaw.isEmpty) return '';

      final rows = <List<String>>[];
      for (final r in rowsRaw) {
        if (r is! List) continue;
        rows.add(r.map(_tableCellText).toList());
      }
      if (rows.isEmpty) return '';

      final colCount = rows.fold(0, (max, r) => r.length > max ? r.length : max);
      final sb = StringBuffer();
      sb.write('|');
      for (int c = 0; c < colCount; c++) {
        sb.write(rows.isNotEmpty && c < rows[0].length ? _tableEscape(rows[0][c]) : '');
        sb.write(' |');
      }
      sb.write('\n|');
      for (int c = 0; c < colCount; c++) {
        sb.write(' --- |');
      }
      sb.write('\n');
      for (var r = 1; r < rows.length; r++) {
        sb.write('|');
        for (int c = 0; c < colCount; c++) {
          sb.write(c < rows[r].length ? _tableEscape(rows[r][c]) : '');
          sb.write(' |');
        }
        sb.write('\n');
      }
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  static String _tableCellText(dynamic cell) {
    if (cell is String) return cell;
    if (cell is Map) return (cell['text']?.toString() ?? '');
    return cell?.toString() ?? '';
  }

  static String _tableEscape(String s) => s.replaceAll('|', r'\|');

  /// GFM 分隔行：单元格只能是 `:---` 这种对齐标记。
  static bool _isMarkdownTableSeparator(String line) {
    final trimmed = line.trim();
    if (!trimmed.contains('|') || !RegExp(r'^[\s|:\-]+$').hasMatch(trimmed)) return false;
    final cells = _splitMarkdownTableRow(trimmed);
    if (cells.isEmpty) return false;
    return cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c.trim()));
  }

  static List<String> _splitMarkdownTableRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    // 按竖线拆列，跳过转义的 \|
    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length && s[i + 1] == '|') {
        buf.write('|');
        i++; // skip '|'
      } else if (s[i] == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(s[i]);
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  // ---------------------------------------------------------------------------
  // Markdown → Delta
  // ---------------------------------------------------------------------------

  /// 将 Markdown 字符串转换为 Quill Delta JSON
  static String markdownToDelta(String markdown) {
    final trimmed = markdown.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}') && trimmed.contains('"mode":"mindmap"')) {
      try {
        return jsonEncode([
          {'insert': {'mindmap': trimmed}},
          {'insert': '\n'},
        ]);
      } catch (_) {}
    }

    final lines = markdown.split('\n');
    final ops = <Map<String, dynamic>>[];

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // GFM 管道表格：表头行 + `| --- |` 分隔行。
      if (line.contains('|') &&
          i + 1 < lines.length &&
          _isMarkdownTableSeparator(lines[i + 1])) {
        final header = _splitMarkdownTableRow(line);
        i += 2;
        final rows = <List<String>>[header];
        while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
          rows.add(_splitMarkdownTableRow(lines[i]));
          i++;
        }
        final cells = <List<Map<String, dynamic>>>[];
        for (var r = 0; r < rows.length; r++) {
          cells.add(rows[r]
              .map((t) => {'text': t, 'style': r == 0 ? 'header' : ''})
              .toList());
        }
        ops.add({'insert': {'table': {'rows': cells}}});
        ops.add({'insert': '\n'});
        continue;
      }

      // Mind map block
      if (line.trimLeft().startsWith('```mindmap')) {
        final buffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buffer.write(lines[i]);
          i++;
        }
        ops.add({
          'insert': {
            'mindmap': buffer.toString(),
          },
        });
        ops.add({'insert': '\n'});
        if (i < lines.length) i++; // skip closing ```
        continue;
      }

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
          'insert': {
            'code_block': jsonEncode({
              'code': codeBuffer.toString(),
              'language': lang.isEmpty ? 'plaintext' : lang,
            }),
          },
        });
        ops.add({'insert': '\n'});
        if (i < lines.length) i++; // skip closing ```
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

/// Internal block representation for delta-to-markdown conversion
class _DeltaBlock {
  final String? text;
  final Map<String, dynamic>? embed;
  final Map<String, dynamic>? attrs;
  final Map<String, dynamic>? blockAttrs; // Block-level attrs from newline
  final bool isNewline;

  _DeltaBlock.text(this.text, this.attrs, {this.blockAttrs})
      : embed = null,
        isNewline = false;

  _DeltaBlock.newline(this.attrs)
      : text = null,
        embed = null,
        blockAttrs = null,
        isNewline = true;

  _DeltaBlock.embed(this.embed)
      : text = null,
        attrs = null,
        blockAttrs = null,
        isNewline = false;

  bool get isEmbed => embed != null;
}
