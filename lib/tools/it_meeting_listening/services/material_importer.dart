/// 会议材料导入（MD / HTML → 结构化纯文本）。
///
/// **为什么只有两种格式**：用户约定材料就是 MD 或 HTML（proposal 非目标：
/// PDF/Word 走既有的「文档语音朗读」工具）。多支持一种格式就多一条解析分支
/// 要维护，而这两种已经覆盖了用户的实际产出。
///
/// **复用既有解析**：MD 走 `DocumentParser._parseMarkdown`（它已经处理了图片、
/// 超链接与修饰语法的清洗），HTML 先经 `htmlToMarkdown` 转成 Markdown 再走同
/// 一条路——避免为同一种产出维护两套清洗规则。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import '../../../services/html_to_markdown.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/document_parser.dart';
import '../models/rehearsal_models.dart';

/// 材料导入失败（带具体原因）。
class MaterialImportException implements Exception {
  MaterialImportException(this.message);
  final String message;
  @override
  String toString() => 'MaterialImportException: $message';
}

/// 材料导入器。
class MaterialImporter {
  /// 支持的扩展名。
  static const supportedExtensions = ['.md', '.markdown', '.html', '.htm'];

  /// 从本地文件导入一份材料。
  ///
  /// 失败时抛出 [MaterialImportException]，消息是**具体原因**（格式不支持 /
  /// 文件不存在 / 内容为空）——用户需要知道该换文件还是该补内容。
  static Future<RehearsalMaterial> importFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MaterialImportException('文件不存在：$filePath');
    }

    final ext = p.extension(filePath).toLowerCase();
    final fileName = p.basename(filePath);
    final title = p.basenameWithoutExtension(filePath);

    if (!supportedExtensions.contains(ext)) {
      throw MaterialImportException('仅支持 MD 与 HTML 材料（收到 .$ext）');
    }

    String markdown;
    if (ext == '.html' || ext == '.htm') {
      final bytes = await file.readAsBytes();
      // HTML 站点常缺 charset 头，按 UTF-8 解码失败时退回 latin1——和
      // CoderSlingo 抓取踩的是同一个坑（mojibake）。
      String html;
      try {
        html = utf8.decode(bytes);
      } catch (_) {
        html = latin1.decode(bytes);
      }
      markdown = htmlToMarkdown(html);
    } else {
      markdown = await file.readAsString();
    }

    // 走既有的 MD 清洗（剥图片/超链接/修饰语法），拿到干净的结构化文本。
    final cleaned = _cleanMarkdown(markdown);
    if (cleaned.trim().isEmpty) {
      throw MaterialImportException('材料内容为空：$fileName');
    }

    return RehearsalMaterial(
      id: _materialId(filePath, cleaned),
      title: title,
      sourcePath: filePath,
      fileName: fileName,
      text: cleaned,
      importedAt: DateTime.now(),
    );
  }

  /// MD 清洗。
  ///
  /// [DocumentParser.cleanMarkdownFormatting] 已经处理了图片、超链接与修饰
  /// 语法。这里不直接用 [DocumentParser.parseFile]，因为它同时接 PDF/Word 等
  /// 格式并返回带分块结构的 [ReadingDocument]——材料导入要的是"干净纯文本"，
  /// 不需要那层分块。
  static String _cleanMarkdown(String raw) =>
      DocumentParser.cleanMarkdownFormatting(raw);

  /// 材料 id：原始路径 + 内容哈希。
  ///
  /// 同一份文件重复导入得到同一 id（不会在磁盘上堆副本）；文件改了内容则得到
  /// 新 id（讲稿与剧本按 materialId 关联，不会串到旧内容上）。
  static String _materialId(String sourcePath, String content) {
    final digest = sha256
        .convert(utf8.encode('$sourcePath:$content'))
        .toString();
    return 'mat_${digest.substring(0, 16)}';
  }

  /// 给 LLM 的材料摘要输入。
  ///
  /// 材料可能有几万字，全送会超 context。这里按 token 预算截断（1 个中文字符
  /// 约 1 token，英文约 0.3 token/字符，取保守值 1 token/字符），并在截断时
  /// **明确告知用户**——静默丢内容会让讲稿漏掉后面的议题。
  static String truncateForPrompt(String text, {int maxChars = 24000}) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}\n\n'
        '[材料过长，仅分析前 $maxChars 字符]';
  }
}
