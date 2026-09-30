import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'matrix.dart';
import 'translator.dart';

/// OOXML 原地回写：翻译 docx 内的文本，保留排版与图片。
class OoxmlRewriter {
  OoxmlRewriter._();

  static void register() {
    registerConverter(
      DocFormat.docx,
      DocFormat.docx,
      'ooxml_rewriter.docx_to_docx',
    );
  }

  /// 翻译 docx 字节，产出新的 docx 字节。
  ///
  /// 算法：
  /// 1. 解压 docx ZIP 包
  /// 2. 使用 XML DOM 解析 `word/document.xml`
  /// 3. 收集所有 `<w:p>` 段落的 `<w:t>` 文本节点并提取原文
  /// 4. 调用 [DocumentTranslator.translateStrings] 翻译文本列表
  /// 5. 将译文回写到对应段落的 `<w:t>` 节点（首个节点填入译文，其余节点清空），设置必要 space preserve 属性
  /// 6. 重新打包 ZIP（保留 `word/media/` 等全部其他文件与结构）
  static Future<Uint8List> rewrite(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) return bytes;

    final xmlContent = utf8.decode(docFile.content as List<int>);
    final xmlDoc = XmlDocument.parse(xmlContent);

    // 收集所有段落元素及其文本节点
    final paragraphs = xmlDoc.findAllElements('w:p').toList();
    final paraTextNodes = <List<XmlElement>>[];
    final paraOriginalTexts = <String>[];

    for (final p in paragraphs) {
      final tNodes = p.findAllElements('w:t').toList();
      paraTextNodes.add(tNodes);
      final text = tNodes.map((e) => e.innerText).join();
      paraOriginalTexts.add(text);
    }

    // 调用统一的 DocumentTranslator.translateStrings（双约束分批、重试及防冷却旁路）
    final translatedTexts = await DocumentTranslator.translateStrings(
      paraOriginalTexts,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );

    // 基于 DOM 节点精确回写
    for (var i = 0; i < paragraphs.length; i++) {
      final tNodes = paraTextNodes[i];
      if (tNodes.isEmpty) continue;

      final original = paraOriginalTexts[i];
      if (original.trim().isEmpty) continue;

      final translated = translatedTexts[i];

      // 首个 text 节点填入译文
      final firstNode = tNodes.first;
      firstNode.innerText = translated;

      // 若译文首尾包含空格，确保 xml:space="preserve"
      if (translated.startsWith(' ') || translated.endsWith(' ')) {
        if (firstNode.getAttribute('xml:space') == null) {
          firstNode.setAttribute('xml:space', 'preserve');
        }
      }

      // 后续同一段落内的 text 节点置空
      for (var j = 1; j < tNodes.length; j++) {
        tNodes[j].innerText = '';
      }
    }

    final newXml = xmlDoc.toXmlString();

    // 重新打包 ZIP
    final newArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        final newBytes = utf8.encode(newXml);
        newArchive.addFile(ArchiveFile.bytes('word/document.xml', newBytes));
      } else {
        newArchive.addFile(file);
      }
    }

    final encoded = ZipEncoder().encode(newArchive);
    return Uint8List.fromList(encoded);
  }
}
