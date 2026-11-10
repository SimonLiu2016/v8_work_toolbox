import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/http_rule_scraper.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/site_scraper_rule_service.dart';

void main() {
  group('HttpRuleScraper 反爬挑战拦截检测', () {
    test('识别各类 Cloudflare Turnstile 与 5s 盾特征', () {
      expect(HttpRuleScraper.isAntiBotChallengeHtml(''), isFalse);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('<html><body><h1>Hello Novels</h1></body></html>'), isFalse);

      expect(HttpRuleScraper.isAntiBotChallengeHtml('<title>Just a moment...</title>'), isTrue);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('<div id="cf-chl-widget"></div>'), isTrue);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('<script src="https://challenges.cloudflare.com/turnstile"></script>'), isTrue);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('<title>Attention Required! | Cloudflare</title>'), isTrue);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('<span>Enable JavaScript and cookies to continue</span>'), isTrue);
      expect(HttpRuleScraper.isAntiBotChallengeHtml('Cloudflare Ray ID: 1234567890'), isTrue);
    });

    test('AntiBotChallengeException 包含 URL 与明确拦截说明', () {
      const ex = AntiBotChallengeException(
        url: 'http://www.szlajc.com/class/1_1/',
        reason: '触发源站反爬拦截验证 (Cloudflare Turnstile 挑战)',
      );
      expect(ex.toString(), contains('AntiBotChallengeException'));
      expect(ex.toString(), contains('http://www.szlajc.com/class/1_1/'));
      expect(ex.toString(), contains('Cloudflare Turnstile 挑战'));
    });
  });

  group('HttpRuleScraper 分类 URL 模板插值与兼容回退', () {
    test('正确解析带有 {category} 与 {page} 的模板', () {
      const rule = SiteScraperRule(
        id: 'tmpl_test',
        name: 'Template Test',
        baseUrl: 'https://example.com',
        catalogUrl: 'https://example.com/sort/{category}_{page}.html',
      );

      final url = HttpRuleScraper.resolveCategoryUrl(rule, '2', 5);
      expect(url, 'https://example.com/sort/2_5.html');
    });

    test('支持 {type} 与 {pageIndex} 变体占位符', () {
      const rule = SiteScraperRule(
        id: 'tmpl_variant_test',
        name: 'Variant Test',
        baseUrl: 'https://example.org',
        catalogUrl: 'https://example.org/list?type={type}&pageIndex={pageIndex}',
      );

      final url = HttpRuleScraper.resolveCategoryUrl(rule, 'fantasy', 3);
      expect(url, 'https://example.org/list?type=fantasy&pageIndex=3');
    });

    test('无占位符时平滑回退到默认 /class/{type}_{page}/ 路径', () {
      const rule = SiteScraperRule(
        id: 'legacy_test',
        name: 'Legacy Test',
        baseUrl: 'http://legacy-novel.com/',
        catalogUrl: '',
      );

      final url = HttpRuleScraper.resolveCategoryUrl(rule, '1', 2);
      expect(url, 'http://legacy-novel.com/class/1_2/');
    });

    test('飘天文学分类为 0 时自适应映射为 /booksort/0/{page}.html 全部文章', () {
      final piaotia = SiteScraperRuleService.defaultPiaotiaRule;

      final urlAll = HttpRuleScraper.resolveCategoryUrl(piaotia, '0', 1);
      expect(urlAll, 'https://www.piaotia.com/booksort/0/1.html');

      final urlCat1 = HttpRuleScraper.resolveCategoryUrl(piaotia, '1', 2);
      expect(urlCat1, 'https://www.piaotia.com/booksort1/0/2.html');
    });
  });

  group('HttpRuleScraper parseCatalogPageHtml 解析器与反爬拦截', () {
    test('遇到 Cloudflare 挑战页面时直接抛出 AntiBotChallengeException', () {
      const rule = SiteScraperRule(
        id: 'test_rule',
        name: 'Test Rule',
        baseUrl: 'http://example.com',
        catalogSelector: '.item',
      );

      const challengeHtml = '''
        <!DOCTYPE html>
        <html>
        <head><title>Just a moment...</title></head>
        <body><div id="cf-chl-widget">Verifying you are human</div></body>
        </html>
      ''';

      expect(
        () => HttpRuleScraper.parseCatalogPageHtml(
          html: challengeHtml,
          pageUrl: 'http://example.com/class/1_1/',
          rule: rule,
        ),
        throwsA(isA<AntiBotChallengeException>()),
      );
    });

    test('解析常规 li 列表式分类页面', () {
      const rule = SiteScraperRule(
        id: 'test_rule',
        name: 'Test Rule',
        baseUrl: 'http://www.szlajc.com',
        catalogSelector: '#newscontent .l ul li',
      );

      const html = '''
        <div id="newscontent">
          <div class="l">
            <ul>
              <li>
                <span class="s2"><a href="/jie/1001/">深空彼岸</a></span>
                <span class="s4">辰东</span>
                <span class="s5">连载中</span>
              </li>
              <li>
                <span class="s2"><a href="/jie/1002/">赤心巡天</a></span>
                <span class="s4">情何以甚</span>
                <span class="s5">完结</span>
              </li>
            </ul>
          </div>
        </div>
      ''';

      final result = HttpRuleScraper.parseCatalogPageHtml(
        html: html,
        pageUrl: 'http://www.szlajc.com/class/1_1/',
        rule: rule,
      );
      final books = result.items;
      expect(books.length, 2);
      expect(books[0].title, '深空彼岸');
      expect(books[0].author, '辰东');
      expect(books[0].detailUrl, 'http://www.szlajc.com/jie/1001/');
      expect(books[1].title, '赤心巡天');
      expect(books[1].author, '情何以甚');
      expect(books[1].detailUrl, 'http://www.szlajc.com/jie/1002/');
    });

    test('解析 table/tr 表格式分类页面 (飘天文学风格)', () {
      const rule = SiteScraperRule(
        id: 'piaotia',
        name: '飘天文学',
        baseUrl: 'https://www.piaotia.com',
        catalogSelector: 'table tr, #content tr',
      );

      const html = '''
        <table>
          <tr class="header"><th>文章名称</th><th>作者</th><th>字数</th></tr>
          <tr>
            <td class="odd"><a href="/book/123.html">凡人修仙之仙界篇</a></td>
            <td class="odd">忘语</td>
            <td class="even">450万字</td>
          </tr>
          <tr>
            <td class="odd"><a href="https://www.piaotia.com/book/456.html">剑来</a></td>
            <td class="odd">烽火戏诸侯</td>
            <td class="even">900万字</td>
          </tr>
        </table>
      ''';

      final result = HttpRuleScraper.parseCatalogPageHtml(
        html: html,
        pageUrl: 'https://www.piaotia.com/booksort1/0/1.html',
        rule: rule,
      );
      final books = result.items;
      expect(books.length, 2);
      expect(books[0].title, '凡人修仙之仙界篇');
      expect(books[0].author, '忘语');
      expect(books[0].detailUrl, 'https://www.piaotia.com/book/123.html');
      expect(books[1].title, '剑来');
      expect(books[1].author, '烽火戏诸侯');
      expect(books[1].detailUrl, 'https://www.piaotia.com/book/456.html');
    });

    test('空 HTML 或无匹配时返回空列表', () {
      const rule = SiteScraperRule(
        id: 'piaotia',
        name: '飘天文学',
        baseUrl: 'https://www.piaotia.com',
        catalogSelector: 'table tr, #content tr',
      );

      final res1 = HttpRuleScraper.parseCatalogPageHtml(
        html: '',
        pageUrl: 'https://www.piaotia.com',
        rule: rule,
      );
      expect(res1.items, isEmpty);

      final res2 = HttpRuleScraper.parseCatalogPageHtml(
        html: '<div>No books here</div>',
        pageUrl: 'https://www.piaotia.com',
        rule: rule,
      );
      expect(res2.items, isEmpty);
    });
  });

  group('SiteScraperRuleService 默认免盾源', () {
    test('包含飘天文学免盾源且配置完整', () {
      final piaotia = SiteScraperRuleService.defaultPiaotiaRule;

      expect(piaotia.name, contains('飘天文学'));
      expect(piaotia.baseUrl, 'https://www.piaotia.com');
      expect(piaotia.catalogUrl, contains('{category}'));
      expect(piaotia.catalogUrl, contains('{page}'));
      expect(piaotia.categoryMap.containsKey('0'), isTrue);
      expect(piaotia.categoryMap['0'], contains('全部文章'));
      expect(piaotia.categoryMap.length, greaterThanOrEqualTo(10));
      expect(piaotia.enableBypass, isFalse);
    });

    test('SiteScraperRule 基于 id 实现值相等性比较', () {
      const rule1 = SiteScraperRule(id: 'piaotia', name: '飘天1', baseUrl: 'https://piaotia.com');
      const rule2 = SiteScraperRule(id: 'piaotia', name: '飘天2', baseUrl: 'https://other.com');
      const rule3 = SiteScraperRule(id: 'szlajc', name: '笔趣阁', baseUrl: 'https://szlajc.com');

      expect(rule1 == rule2, isTrue);
      expect(rule1.hashCode == rule2.hashCode, isTrue);
      expect(rule1 == rule3, isFalse);
    });
  });
}
