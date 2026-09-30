import 'document_model.dart';
import 'matrix.dart';

/// T2 扁平 writer——将 DocumentModel 序列化为文本格式。
class Flatten {
  Flatten._();

  static void register() {
    // →md（4 格，跳过 md→md）
    registerConverter(DocFormat.docx, DocFormat.md,  'flatten.md');
    registerConverter(DocFormat.pdf,  DocFormat.md,  'flatten.md');
    registerConverter(DocFormat.xlsx, DocFormat.md,  'flatten.md');
    registerConverter(DocFormat.csv,  DocFormat.md,  'flatten.md');
    // →txt（5 格）
    registerConverter(DocFormat.docx, DocFormat.txt, 'flatten.txt');
    registerConverter(DocFormat.md,   DocFormat.txt, 'flatten.txt');
    registerConverter(DocFormat.pdf,  DocFormat.txt, 'flatten.txt');
    registerConverter(DocFormat.xlsx, DocFormat.txt, 'flatten.txt');
    registerConverter(DocFormat.csv,  DocFormat.txt, 'flatten.txt');
  }

  // ─── Markdown ─────────────────────────────────────────────────────────────

  /// DocumentModel → Markdown 文本。
  static String toMarkdown(DocumentModel doc) {
    final buf = StringBuffer();
    for (final block in doc.blocks) {
      switch (block) {
        case HeadingBlock h:
          buf.writeln('${'#' * h.level} ${h.text}');
          buf.writeln();
        case ParagraphBlock p:
          if (p.text.trim().isNotEmpty) {
            buf.writeln(p.text);
            buf.writeln();
          }
        case ListItemBlock li:
          if (li.ordered) {
            buf.writeln('1. ${li.text}');
          } else {
            buf.writeln('- ${li.text}');
          }
        case TableBlock t:
          if (t.rows.isEmpty) break;
          // 表头行
          buf.writeln('| ${t.rows.first.join(' | ')} |');
          // 分隔行
          buf.writeln('| ${t.rows.first.map((_) => '---').join(' | ')} |');
          // 数据行
          for (final row in t.rows.skip(1)) {
            buf.writeln('| ${row.join(' | ')} |');
          }
          buf.writeln();
        case CodeBlock c:
          buf.writeln('```${c.language ?? ''}');
          buf.writeln(c.code);
          buf.writeln('```');
          buf.writeln();
        case HorizontalRuleBlock _:
          buf.writeln('---');
          buf.writeln();
        case ImageBlock img:
          buf.writeln('![${img.altText}](${img.imageKey})');
          buf.writeln();
        case BlankBlock _:
          buf.writeln();
      }
    }
    return buf.toString().trim();
  }

  // ─── 纯文本 ───────────────────────────────────────────────────────────────

  /// DocumentModel → 纯文本（段落间空行分隔，图片跳过）。
  static String toText(DocumentModel doc) {
    final parts = <String>[];
    for (final block in doc.blocks) {
      switch (block) {
        case HeadingBlock h:
          parts.add(h.text);
        case ParagraphBlock p:
          if (p.text.trim().isNotEmpty) parts.add(p.text);
        case ListItemBlock li:
          parts.add(li.text);
        case TableBlock t:
          for (final row in t.rows) {
            parts.add(row.join('\t'));
          }
        case CodeBlock c:
          parts.add(c.code);
        case ImageBlock _:
          // 图片跳过
          break;
        case HorizontalRuleBlock _:
          parts.add('---');
        case BlankBlock _:
          parts.add('');
      }
    }
    return parts.join('\n\n').trim();
  }

  // ─── CSV ──────────────────────────────────────────────────────────────────

  /// DocumentModel → CSV（按 RFC 4180，只输出第一个 TableBlock）。
  /// 非表格文档返回空字符串。
  static String toCsv(DocumentModel doc) {
    for (final block in doc.blocks) {
      if (block is TableBlock) {
        return _renderCsv(block.rows);
      }
    }
    return '';
  }

  static String _renderCsv(List<List<String>> rows) {
    final buf = StringBuffer();
    for (final row in rows) {
      final cells = row.map((cell) => _csvCell(cell)).join(',');
      buf.writeln(cells);
    }
    return buf.toString();
  }

  static String _csvCell(String value) {
    // 按 RFC 4180：含逗号、双引号或换行的字段用双引号包裹，内部双引号转义为 ""
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }
}
