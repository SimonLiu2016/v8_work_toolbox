import 'dart:io';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/http_rule_scraper.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/txt_parser.dart';

void main() {
  group('纯 Dart GBK 编解码测试', () {
    test('正确将 GBK 字节流无损还原为中文字符串', () {
      const originalText = '假太监：我乃大明九千岁 - 最新章节：第100章 奉天承运';
      final gbkBytes = gbk.encode(originalText);

      final decoded = gbk.decode(gbkBytes, allowMalformed: true);
      expect(decoded, originalText);
    });

    test('HttpRuleScraper.parseCatalogPageHtml 解析 GBK 解码后的表格无乱码', () {
      const rule = SiteScraperRule(
        id: 'piaotia',
        name: '飘天文学',
        baseUrl: 'https://www.piaotia.com',
        catalogSelector: 'table tr, #content tr',
      );

      const html = '''
        <table>
          <tr>
            <td class="odd"><a href="https://www.piaotia.com/bookinfo/1/100.html">凡人修仙传</a></td>
            <td class="even"><a href="/html/1/100/1.html">第一千三百八十一章 大结局</a></td>
            <td class="odd">忘语</td>
            <td class="even">800万字</td>
            <td class="odd">26-11-03</td>
            <td class="even">完结</td>
          </tr>
        </table>
      ''';

      final result = HttpRuleScraper.parseCatalogPageHtml(
        html: html,
        pageUrl: 'https://www.piaotia.com/booksort1/0/1.html',
        rule: rule,
      );

      expect(result.items.length, 1);
      final item = result.items.first;
      expect(item.title, '凡人修仙传');
      expect(item.rawTitle, '凡人修仙传');
      expect(item.author, '忘语');
      expect(item.latestChapter, '第一千三百八十一章 大结局');
    });

    test('TxtParser.readTextWithEncoding 支持 GBK 编码文本文件', () async {
      final tempDir = await Directory.systemTemp.createTemp('txt_gbk_test_');
      final file = File('${tempDir.path}/test_book.txt');

      const text = '第一章 穿越大明\n这是一个风起云涌的时代……';
      final bytes = gbk.encode(text);
      await file.writeAsBytes(bytes);

      final readText = await TxtParser.readTextWithEncoding(file);
      expect(readText, text);

      await tempDir.delete(recursive: true);
    });
  });
}
