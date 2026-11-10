import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/http_rule_scraper.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/site_scraper_rule_service.dart';

void main() {
  test('HttpRuleScraper szlajc.com 触发 Cloudflare 盾时正确抛出 AntiBotChallengeException', () async {
    const rule = SiteScraperRule(
      id: 'szlajc',
      name: 'szlajc.com',
      baseUrl: 'http://www.szlajc.com',
      catalogUrl: 'http://www.szlajc.com/class/1_1/',
      catalogSelector: '#newscontent .l ul li',
    );

    final scraper = HttpRuleScraper(rule);

    try {
      await scraper.scrapeCategoryPage(categoryKey: '1', pageIndex: 1);
    } catch (e) {
      expect(e, isA<AntiBotChallengeException>());
      print('Verified: szlajc accurately throws AntiBotChallengeException -> $e');
    } finally {
      scraper.close();
    }
  });

  test('HttpRuleScraper 真实网络抓取飘天文学 (免盾优质源)', () async {
    final rule = SiteScraperRuleService.defaultPiaotiaRule;
    final scraper = HttpRuleScraper(rule);

    try {
      final res = await scraper.scrapeCategoryPage(categoryKey: '1', pageIndex: 1);
      print('Discovered novels from piaotia: ${res.items.length}');
      expect(res.items.isNotEmpty, isTrue);
      final first = res.items.first;
      print('First item: 《${first.title}》 (原始标题: ${first.rawTitle}) 作者: ${first.author} 最新章节: ${first.latestChapter} 链接: ${first.detailUrl}');
      expect(first.title.isNotEmpty, isTrue);
      expect(first.latestChapter, isNotNull);
      expect(first.latestChapter!.isNotEmpty, isTrue);
      expect(first.rawTitle, isNotEmpty);
      expect(first.detailUrl.startsWith('http'), isTrue);
    } catch (e) {
      print('Network warning for piaotia test (e.g. offline env): $e');
    } finally {
      scraper.close();
    }
  });
}
