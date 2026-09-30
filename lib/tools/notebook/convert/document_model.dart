import 'dart:typed_data';

/// 文档内容模型——T2 转换路径的唯一中间表示。
///
/// T1 路径直接原地改写源文件字节，完全绕过此模型。
/// T2 路径走 parser → [DocumentModel] → translator（可选）→ writer 管线。
///
/// **设计原则：**
/// - 只保留「内容与图片」，不保留样式细节（字体大小、颜色、间距等）——
///   T2 的 spec 承诺是 best-effort 排版还原，不是样式零变化。
/// - 图片以「引用 + 字节」形式随模型流动，writer 负责落地。
/// - 块树结构：[DocumentModel.blocks] 是顶层块序列，块内可嵌套（列表项、表格行列）。

// ─── 图片引用 ──────────────────────────────────────────────────────────────────

/// 文档内嵌图片。
///
/// [key] 是文档内唯一标识（通常是 media 文件名或页内序号），[bytes] 是原始字节，
/// [mimeType] 是 MIME 类型（`image/png` / `image/jpeg` 等）。
class DocImage {
  const DocImage({
    required this.key,
    required this.bytes,
    required this.mimeType,
  });

  final String key;
  final Uint8List bytes;
  final String mimeType;

  String get extension {
    if (mimeType == 'image/jpeg') return 'jpg';
    if (mimeType == 'image/png') return 'png';
    if (mimeType == 'image/gif') return 'gif';
    if (mimeType == 'image/webp') return 'webp';
    return 'bin';
  }
}

// ─── 块类型 ───────────────────────────────────────────────────────────────────

/// 所有块的基类。
sealed class DocBlock {
  const DocBlock();
}

/// 段落——普通正文。
class ParagraphBlock extends DocBlock {
  const ParagraphBlock(this.text);
  final String text;
}

/// 标题。[level] 1–6，对应 H1–H6。
class HeadingBlock extends DocBlock {
  const HeadingBlock(this.text, {required this.level});
  final String text;
  final int level;
}

/// 有序或无序列表项。[ordered] 为 true 时是有序列表。[depth] 0 = 顶层。
class ListItemBlock extends DocBlock {
  const ListItemBlock(this.text, {required this.ordered, this.depth = 0});
  final String text;
  final bool ordered;
  final int depth;
}

/// 代码块。[language] 可为空。
class CodeBlock extends DocBlock {
  const CodeBlock(this.code, {this.language});
  final String code;
  final String? language;
}

/// 水平分隔线。
class HorizontalRuleBlock extends DocBlock {
  const HorizontalRuleBlock();
}

/// 图片引用块。[imageKey] 指向 [DocumentModel.images] 中的条目。
class ImageBlock extends DocBlock {
  const ImageBlock(this.imageKey, {this.altText = ''});
  final String imageKey;
  final String altText;
}

/// 表格。[rows] 的第一行通常是表头（由 parser 负责标记 [hasHeader]）。
class TableBlock extends DocBlock {
  const TableBlock(this.rows, {this.hasHeader = false});
  final List<List<String>> rows;
  final bool hasHeader;
}

/// 空行（排版分隔）。
class BlankBlock extends DocBlock {
  const BlankBlock();
}

// ─── 文档模型 ─────────────────────────────────────────────────────────────────

/// 文档内容模型。
///
/// [blocks] 是按文档顺序排列的块序列，[images] 是全部嵌入图片的字典。
/// 翻译层只修改文本块的 [text] / [rows] 字段，[images] 不参与翻译。
class DocumentModel {
  const DocumentModel({
    required this.blocks,
    this.images = const {},
    this.sourceFormat,
  });

  final List<DocBlock> blocks;

  /// 图片字典：key = [DocImage.key]，value = 图片数据。
  final Map<String, DocImage> images;

  /// 原始格式（可选，供 writer 参考）。
  final String? sourceFormat;

  /// 文档是否包含任何可提取的文字。
  bool get hasText => blocks.any((b) {
        return switch (b) {
          ParagraphBlock p => p.text.trim().isNotEmpty,
          HeadingBlock h => h.text.trim().isNotEmpty,
          ListItemBlock li => li.text.trim().isNotEmpty,
          CodeBlock c => c.code.trim().isNotEmpty,
          TableBlock t => t.rows.any((row) => row.any((c) => c.trim().isNotEmpty)),
          _ => false,
        };
      });

  /// 提取全部纯文本（供翻译器批量处理）。
  List<String> extractTexts() {
    final result = <String>[];
    for (final block in blocks) {
      switch (block) {
        case ParagraphBlock p:
          if (p.text.trim().isNotEmpty) result.add(p.text);
        case HeadingBlock h:
          if (h.text.trim().isNotEmpty) result.add(h.text);
        case ListItemBlock li:
          if (li.text.trim().isNotEmpty) result.add(li.text);
        case CodeBlock _:
          // 代码块不送翻译
          break;
        case TableBlock t:
          for (final row in t.rows) {
            for (final cell in row) {
              if (cell.trim().isNotEmpty) result.add(cell);
            }
          }
        case ImageBlock _:
        case HorizontalRuleBlock _:
        case BlankBlock _:
          break;
      }
    }
    return result;
  }

  /// 用翻译后的文本重建模型（按序替换，长度必须与 [extractTexts] 一致）。
  DocumentModel applyTranslations(List<String> translated) {
    var i = 0;
    String next() => i < translated.length ? translated[i++] : '';

    final newBlocks = <DocBlock>[];
    for (final block in blocks) {
      switch (block) {
        case ParagraphBlock p:
          newBlocks.add(
            p.text.trim().isNotEmpty ? ParagraphBlock(next()) : p,
          );
        case HeadingBlock h:
          newBlocks.add(
            h.text.trim().isNotEmpty
                ? HeadingBlock(next(), level: h.level)
                : h,
          );
        case ListItemBlock li:
          newBlocks.add(
            li.text.trim().isNotEmpty
                ? ListItemBlock(next(), ordered: li.ordered, depth: li.depth)
                : li,
          );
        case CodeBlock _:
          newBlocks.add(block);
        case TableBlock t:
          final newRows = <List<String>>[];
          for (final row in t.rows) {
            final newRow = <String>[];
            for (final cell in row) {
              newRow.add(cell.trim().isNotEmpty ? next() : cell);
            }
            newRows.add(newRow);
          }
          newBlocks.add(TableBlock(newRows, hasHeader: t.hasHeader));
        case ImageBlock _:
        case HorizontalRuleBlock _:
        case BlankBlock _:
          newBlocks.add(block);
      }
    }
    return DocumentModel(
      blocks: newBlocks,
      images: images,
      sourceFormat: sourceFormat,
    );
  }
}
