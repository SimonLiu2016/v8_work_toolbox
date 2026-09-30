import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;
import 'markdown_converter.dart';

/// AppFlowy 自定义 Markdown 代码块解析器
class NotebookCodeBlockParser extends CustomMarkdownParser {
  const NotebookCodeBlockParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') {
      return [];
    }

    final ec = element.children;
    if (ec == null || ec.isEmpty) {
      return [];
    }

    final code = ec.first;
    if (code is! md.Element || code.tag != 'code') {
      return [];
    }

    String? language;
    if (code.attributes.containsKey('class')) {
      final classes = code.attributes['class']!.split(' ');
      final languageClass = classes.firstWhere(
        (c) => c.startsWith('language-'),
        orElse: () => '',
      );
      if (languageClass.length > 'language-'.length) {
        language = languageClass.substring('language-'.length);
      }
    }

    final codeText = code.textContent.trimRight();
    return [
      Node(
        type: 'code_block',
        attributes: {
          'code': codeText,
          'language': language ?? 'plaintext',
          'delta': (Delta()..insert(codeText)).toJson(),
        },
      ),
    ];
  }
}

/// AppFlowy 文档编解码与互转工具
class AppFlowyCodec {
  AppFlowyCodec._();

  /// 将存储的内容（JSON 或 Markdown 或旧版 Quill Delta）解析为 AppFlowy [Document]
  static Document parseToDocument(String? content) {
    if (content == null || content.trim().isEmpty) {
      return Document.blank(withInitialText: true);
    }
    final trimmed = content.trim();

    // 1. 如果是 AppFlowy Document JSON
    if (trimmed.startsWith('{') && trimmed.contains('"document"')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        _normalizeJsonNodeData(map);
        return Document.fromJson(map);
      } catch (_) {}
    }

    // 2. 如果是旧版 Quill Delta JSON (以 [ 开头)
    if (trimmed.startsWith('[')) {
      try {
        final md = MarkdownConverter.deltaToMarkdown(trimmed);
        if (md.trim().isNotEmpty) {
          return _parseMarkdownWithCustomBlocks(md);
        } else {
          return Document.blank(withInitialText: true);
        }
      } catch (_) {
        return Document.blank(withInitialText: true);
      }
    }

    // 3. 默认作为 Markdown 解析（包含从印象笔记导入的 Markdown）
    return _parseMarkdownWithCustomBlocks(content);
  }

  static void _normalizeJsonNodeData(dynamic obj) {
    if (obj is Map) {
      if (obj.containsKey('attributes') && !obj.containsKey('data')) {
        obj['data'] = obj['attributes'];
      }
      for (final value in obj.values) {
        _normalizeJsonNodeData(value);
      }
    } else if (obj is List) {
      for (final item in obj) {
        _normalizeJsonNodeData(item);
      }
    }
  }

  static String _normalizeMarkdown(String markdown) {
    return markdown.replaceAllMapped(RegExp(r'!\[(.*?)\]\((.*?)\)'), (match) {
      final alt = match.group(1) ?? '';
      final url = (match.group(2) ?? '').trim();
      if (url.isEmpty) return match.group(0)!;
      if (url.startsWith('<') && url.endsWith('>')) {
        return match.group(0)!;
      }
      if (url.contains(' ')) {
        return '![$alt](<$url>)';
      }
      return match.group(0)!;
    });
  }

  static void _postProcessNodes(List<Node> nodes) {
    final imgRegex = RegExp(r'^!\[(.*?)\]\(<?(.*?)>?\)$');
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.type == ImageBlockKeys.type) {
        final rawUrl = (node.attributes[ImageBlockKeys.url] ?? node.attributes['src'] ?? node.attributes['url'] ?? '').toString();
        final decodedUrl = rawUrl.contains('%20') ? Uri.decodeFull(rawUrl) : rawUrl;
        final newAttrs = Map<String, dynamic>.from(node.attributes);
        newAttrs[ImageBlockKeys.url] = decodedUrl;
        newAttrs['url'] = decodedUrl;
        newAttrs['src'] = decodedUrl;
        nodes[i] = Node(
          type: ImageBlockKeys.type,
          attributes: newAttrs,
        );
      } else if (node.type == ParagraphBlockKeys.type) {
        final text = node.delta?.toPlainText().trim() ?? '';
        final match = imgRegex.firstMatch(text);
        if (match != null) {
          final rawUrl = match.group(2)!.trim();
          final url = rawUrl.contains('%20') ? Uri.decodeFull(rawUrl) : rawUrl;
          nodes[i] = imageNode(url: url);
        }
      }
    }
  }

  static Document _parseMarkdownWithCustomBlocks(String markdown) {
    final normalized = _normalizeMarkdown(markdown);

    // 检查是否有 ```mindmap 块
    final mindmapRegex = RegExp(r'```mindmap\s*([\s\S]*?)\s*```', multiLine: true);
    final mindmapMatches = mindmapRegex.allMatches(normalized).toList();

    if (mindmapMatches.isEmpty) {
      try {
        final doc = markdownToDocument(
          normalized,
          markdownParsers: const [NotebookCodeBlockParser()],
        );
        if (doc.root.children.isNotEmpty) {
          final children = List<Node>.from(doc.root.children);
          _postProcessNodes(children);
          return Document(root: pageNode(children: children));
        }
      } catch (_) {}
      return Document.blank(withInitialText: true);
    }

    // 若含有 mindmap，切分段落分别解析并组装
    final children = <Node>[];
    int lastIndex = 0;
    for (final match in mindmapMatches) {
      if (match.start > lastIndex) {
        final subMd = normalized.substring(lastIndex, match.start).trim();
        if (subMd.isNotEmpty) {
          try {
            final subDoc = markdownToDocument(
              subMd,
              markdownParsers: const [NotebookCodeBlockParser()],
            );
            children.addAll(subDoc.root.children);
          } catch (_) {}
        }
      }
      final mindmapData = match.group(1)?.trim() ?? '';
      children.add(Node(
        type: 'mindmap',
        attributes: {'data': mindmapData},
      ));
      lastIndex = match.end;
    }

    if (lastIndex < normalized.length) {
      final subMd = normalized.substring(lastIndex).trim();
      if (subMd.isNotEmpty) {
        try {
          final subDoc = markdownToDocument(
            subMd,
            markdownParsers: const [NotebookCodeBlockParser()],
          );
          children.addAll(subDoc.root.children);
        } catch (_) {}
      }
    }

    if (children.isEmpty) {
      return Document.blank(withInitialText: true);
    }
    _postProcessNodes(children);
    return Document(root: pageNode(children: children));
  }

  /// 在文档末尾追加一个附件块，返回序列化后的 JSON。
  ///
  /// 文档导入（"保留原文件为附件"）与编辑器插入共用此入口。
  /// 必须用 [Node.insert]：[parseToDocument] 返回的 `root.children` 是
  /// `growable: false` 的缓存快照，直接 `.add()` 会抛 UnsupportedError。
  static String appendAttachmentNode(
    String deltaJson, {
    required String attachmentId,
    required String filename,
    required int sizeBytes,
  }) {
    final doc = parseToDocument(deltaJson);
    doc.root.insert(Node(
      type: 'attachment',
      attributes: {
        'attachmentId': attachmentId,
        'filename': filename,
        'sizeBytes': sizeBytes,
      },
    ));
    return documentToJson(doc);
  }

  /// 把文档中的图片占位标记替换为 attachment 节点。
  ///
  /// 占位形如 `{{attachment:local:<key>}}`，由 docx/pdf 转换器写入。
  ///
  /// 为什么不要求"占位独占一个段落"：`markdownToDelta` 产出 quill delta 后，
  /// `parseToDocument` 会经 `deltaToMarkdown` 中转，而该步会把 `\n\n` 压成
  /// `\n`——原本以空行分隔的占位段落会与相邻文本合并。故此处改为**在节点内
  /// 按文本切片替换**：占位前的文本、attachment 节点、占位后的文本各就各位。
  static String replacePlaceholderWithAttachment(
    String deltaJson, {
    required String placeholder,
    required String attachmentId,
    required String filename,
    required int sizeBytes,
    String? mime,
  }) {
    final doc = parseToDocument(deltaJson);
    var replaced = false;

    for (final node in List.of(doc.root.children)) {
      if (replaced) break;
      final text = node.delta?.toPlainText() ?? '';
      final idx = text.indexOf(placeholder);
      if (idx < 0) continue;

      final before = text.substring(0, idx);
      final after = text.substring(idx + placeholder.length);

      // insertBefore 把新节点插到 node 之前，所以插入顺序必须是
      // before → attachment → after，这样最终相对次序才正确
      //（顺序写反会得到 [after, att, before]，实测踩过）。
      if (before.trim().isNotEmpty) {
        node.insertBefore(_paragraphNode(before));
      }
      node.insertBefore(Node(
        type: 'attachment',
        attributes: {
          'attachmentId': attachmentId,
          'filename': filename,
          'sizeBytes': sizeBytes,
          if (mime != null) 'mime': mime,
        },
      ));
      if (after.trim().isNotEmpty) {
        node.insertBefore(_paragraphNode(after));
      }
      node.unlink();
      replaced = true;
    }

    return documentToJson(doc);
  }

  /// 直接构造一个 attachment 节点的 document JSON——供测试与"纯附件"场景使用。
  static String placeholderToAttachmentJson({
    required String attachmentId,
    required String filename,
    required int sizeBytes,
    String? localPath,
    String? mime,
  }) {
    final doc = Document.blank(withInitialText: false);
    doc.root.insert(Node(
      type: 'attachment',
      attributes: {
        'attachmentId': attachmentId,
        'filename': filename,
        'sizeBytes': sizeBytes,
        if (localPath != null) 'localPath': localPath,
        if (mime != null) 'mime': mime,
      },
    ));
    return documentToJson(doc);
  }

  /// 由纯文本构造一个段落节点。
  ///
  /// 走 [Node.fromJson] 而非 `Node(type: ...)`——后者不接受 delta，
  /// 而 `TextNode(delta:)` 的 type 固定为 `text`，塞不进 root 的段落序列。
  static Node _paragraphNode(String text) {
    return Node.fromJson({
      'type': ParagraphBlockKeys.type,
      'data': {
        'delta': [
          {'insert': text.trim()},
        ],
      },
    });
  }

  /// 将 [Document] 序列化为 JSON 字符串以便落盘
  static String documentToJson(Document doc) {
    try {
      return jsonEncode(doc.toJson());
    } catch (_) {
      return jsonEncode(Document.blank(withInitialText: true).toJson());
    }
  }

  /// 将 [Document] 导出为干净标准的 Markdown 文本
  static String documentToMarkdownString(Document doc) {
    try {
      final sb = StringBuffer();
      for (final node in doc.root.children) {
        if (node.type == 'mindmap') {
          final data = node.attributes['data']?.toString() ?? '';
          sb.writeln('```mindmap');
          sb.writeln(data);
          sb.writeln('```');
          sb.writeln();
        } else if (node.type == 'code_block' || node.type == 'code') {
          final lang = node.attributes['language']?.toString() ?? '';
          final code = (node.attributes['code'] ?? node.delta?.toPlainText())?.toString() ?? '';
          sb.writeln('```$lang');
          sb.writeln(code.trimRight());
          sb.writeln('```');
          sb.writeln();
        } else {
          final tempDoc = Document(root: pageNode(children: [node]));
          final md = documentToMarkdown(tempDoc).trim();
          if (md.isNotEmpty) {
            sb.writeln(md);
            sb.writeln();
          }
        }
      }
      final result = sb.toString().trim();
      return result.isNotEmpty ? result : documentToMarkdown(doc);
    } catch (_) {
      try {
        return documentToMarkdown(doc);
      } catch (_) {
        return '';
      }
    }
  }

  /// 从 [Document] 提取全部纯文本
  /// 从笔记存储的 JSON 提取纯文本的**唯一入口**。
  ///
  /// 笔记字段名为 `deltaJson`（历史遗留），但 AppFlowy 迁移后实际存的是
  /// `{"document":{...}}` 对象。任何用 `jsonDecode(...) as List` 的 Quill Delta
  /// 解析器（如 `MarkdownConverter.deltaToMarkdown`）对它都会抛异常并静默返回
  /// 空串——曾导致 FTS 正文全空、RAG 片段全空。调用方一律走此方法，避免再次
  /// 分叉出错误的解析假设。
  static String jsonToPlainText(String? deltaJson) {
    if (deltaJson == null || deltaJson.trim().isEmpty) return '';
    try {
      return documentToPlainText(parseToDocument(deltaJson));
    } catch (e) {
      debugPrint('笔记正文提取失败: $e');
      return '';
    }
  }

  static String documentToPlainText(Document doc) {
    final sb = StringBuffer();
    for (final node in doc.root.children) {
      _extractAllTextFromNode(node, sb);
      sb.writeln();
    }
    return sb.toString().trim();
  }

  static void _extractAllTextFromNode(Node node, StringBuffer sb) {
    final delta = node.delta;
    if (delta != null) {
      final text = delta.toPlainText();
      if (text.isNotEmpty) {
        sb.write(text);
      }
    }
    for (final child in node.children) {
      _extractAllTextFromNode(child, sb);
    }
  }

  /// 从 [Document] 提取前 120 字作为纯文本摘要
  static String documentToSummary(Document doc, {int maxLength = 120}) {
    final sb = StringBuffer();
    for (final node in doc.root.children) {
      _extractTextFromNode(node, sb, maxLength);
      if (sb.length >= maxLength) break;
    }
    final text = sb.toString().trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  static void _extractTextFromNode(Node node, StringBuffer sb, int maxLen) {
    if (sb.length >= maxLen) return;
    final delta = node.delta;
    if (delta != null) {
      final text = delta.toPlainText().replaceAll('\n', ' ').trim();
      if (text.isNotEmpty) {
        if (sb.isNotEmpty) sb.write(' ');
        sb.write(text);
      }
    }
    for (final child in node.children) {
      _extractTextFromNode(child, sb, maxLen);
      if (sb.length >= maxLen) break;
    }
  }
}

/// 从笔记存储的 JSON 提取纯文本的**唯一入口**。
///
/// 笔记字段名为 `deltaJson`（历史遗留），但 AppFlowy 迁移后实际存的是
/// `{"document":{...}}` 对象。任何用 `jsonDecode(...) as List` 的 Quill Delta
/// 解析器（如 `MarkdownConverter.deltaToMarkdown`）对它都会抛异常并静默返回
/// 空串——曾导致 FTS 正文全空、RAG 片段全空。
///
/// 调用方一律走此方法，避免再次分叉出错误的解析假设。