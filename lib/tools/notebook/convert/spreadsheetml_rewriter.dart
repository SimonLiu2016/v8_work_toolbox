import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'matrix.dart';
import 'translator.dart';

/// SpreadsheetML 原地回写：翻译 xlsx 中的共享字符串与内联字符串。
class SpreadsheetmlRewriter {
  SpreadsheetmlRewriter._();

  static void register() {
    registerConverter(
      DocFormat.xlsx,
      DocFormat.xlsx,
      'spreadsheetml_rewriter.xlsx_to_xlsx',
    );
  }

  /// 翻译 xlsx 字节，产出新的 xlsx 字节。
  ///
  /// 算法：
  /// 1. 解压 xlsx
  /// 2. 读取 `xl/sharedStrings.xml` 中的 `<t>` 文本
  /// 3. 翻译全部字符串
  /// 4. 回写 `xl/sharedStrings.xml`
  /// 5. 重新打包 ZIP（`xl/worksheets/` 原字节不变）
  static Future<Uint8List> rewrite(
    Uint8List bytes, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 读取共享字符串
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile == null) return bytes;

    final ssXml = utf8.decode(ssFile.content as List<int>);
    final doc = XmlDocument.parse(ssXml);

    // 提取所有字符串
    final strings = <String>[];
    for (final si in doc.findAllElements('si')) {
      final t = si.findElements('t').firstOrNull;
      if (t != null) {
        strings.add(t.innerText);
      } else {
        final buf = StringBuffer();
        for (final r in si.findElements('r')) {
          final rt = r.findElements('t').firstOrNull;
          if (rt != null) buf.write(rt.innerText);
        }
        strings.add(buf.toString());
      }
    }

    if (strings.isEmpty) return bytes;

    // 翻译（使用统一的双约束分批与重试机制）
    final translated = await DocumentTranslator.translateStrings(
      strings,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );

    // 回写 XML
    final newSsXml = _rewriteSharedStrings(ssXml, translated);

    // 重新打包
    final newArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'xl/sharedStrings.xml') {
        final newBytes = utf8.encode(newSsXml);
        newArchive.addFile(ArchiveFile.bytes('xl/sharedStrings.xml', newBytes));
      } else {
        newArchive.addFile(file);
      }
    }

    final encoded = ZipEncoder().encode(newArchive);
    return Uint8List.fromList(encoded);
  }

  static String _rewriteSharedStrings(
    String original,
    List<String> translated,
  ) {
    try {
      final doc = XmlDocument.parse(original);
      var idx = 0;
      for (final si in doc.findAllElements('si')) {
        if (idx >= translated.length) break;
        final newText = translated[idx++];
        final t = si.findElements('t').firstOrNull;
        if (t != null) {
          // 替换单个 <t> 节点
          final parent = t.parent;
          if (parent != null) {
            final newT = XmlElement(
              XmlName('t'),
              [
                if (newText.startsWith(' ') || newText.endsWith(' '))
                  XmlAttribute(XmlName('space', 'xml'), 'preserve'),
              ],
              [XmlText(newText)],
            );
            final tIdx = parent.children.indexOf(t);
            if (tIdx != -1) {
              parent.children[tIdx] = newT;
            }
          }
        } else {
          // 富文本：清除所有 <r> 子节点，新增一个简单 <t>
          si.children.clear();
          si.children.add(
            XmlElement(
              XmlName('t'),
              [
                if (newText.startsWith(' ') || newText.endsWith(' '))
                  XmlAttribute(XmlName('space', 'xml'), 'preserve'),
              ],
              [XmlText(newText)],
            ),
          );
        }
      }
      return doc.toXmlString();
    } catch (_) {
      // 解析异常，退化为正则实体替换
      return _manualReplace(original, translated);
    }
  }

  static String _manualReplace(String xml, List<String> translated) {
    var result = xml;
    var idx = 0;
    result = result.replaceAllMapped(
      RegExp(r'<t(?:[^>]*)>(.*?)</t>', dotAll: true),
      (m) {
        if (idx >= translated.length) return m.group(0)!;
        final escaped = _encodeEntities(translated[idx++]);
        return '<t>$escaped</t>';
      },
    );
    return result;
  }

  static String _encodeEntities(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
