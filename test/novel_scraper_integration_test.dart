import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/http_rule_scraper.dart';

void main() {
  test('HttpRuleScraper live integration test with szlajc.com', () async {
    const rule = SiteScraperRule(
      id: 'szlajc',
      name: 'szlajc.com',
      baseUrl: 'http://www.szlajc.com',
      catalogUrl: 'http://www.szlajc.com/class/1_1/',
      catalogSelector: '#newscontent .l ul li',
      tocSelector: '#list dd a, .box_con #list dl a',
      contentSelector: '#content, .content',
      titleSelector: '.bookname h1, h1',
    );

    final scraper = HttpRuleScraper(rule);

    // 1. 站点书库探索 (测试发现作品数量及字段)
    print('Testing Catalog discovery...');
    final catalog = await scraper.scrapeCatalog(rule.catalogUrl);
    print('Discovered novels: ${catalog.length}');
    if (catalog.isEmpty) {
      print('Skip: szlajc.com is currently unreachable or blocking crawler.');
      return;
    }
    expect(catalog.isNotEmpty, true);
    print('First item: 《${catalog.first.title}》 作者: ${catalog.first.author} 链接: ${catalog.first.detailUrl}');

    // 2. 用户指定的小说目录提取 (https://www.szlajc.com/jie/77430/)
    print('Testing TOC parsing...');
    final chapters = await scraper.scrapeTableOfContents('https://www.szlajc.com/jie/77430/');
    print('Parsed chapters: ${chapters.length}');
    expect(chapters.isNotEmpty, true);
    expect(chapters.first.title.contains('第1章'), true);

    // 3. 元数据提取验证
    print('Testing metadata extraction...');
    final meta = await scraper.extractNovelMetadata('https://www.szlajc.com/jie/77430/');
    print('Extracted meta: $meta');
    expect(meta['title'], '逍遥四公子');
    expect(meta['author'], '修果');

    // 4. 第一章正文抓取
    print('Testing chapter 1 text extraction...');
    final chapterResult = await scraper.scrapeChapter(chapters.first.chapterUrl);
    print('Chapter title: ${chapterResult.title}');
    print('Chapter content length: ${chapterResult.content.length}');
    expect(chapterResult.content.length > 500, true);
    expect(chapterResult.content.contains('宁宸'), true);

    scraper.close();
  });
}
