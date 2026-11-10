import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../../services/mcp_service.dart';
import '../models/novel_models.dart';
import 'http_rule_scraper.dart';

/// 具有反爬穿透能力的抓取器 (针对 Cloudflare Turnstile / 类似 szlajc.com 的站点)
class AntiBotBypassScraper {
  final SiteScraperRule rule;
  final McpService _mcpService = McpService.instance;

  AntiBotBypassScraper(this.rule);

  /// 利用 Firecrawl 服务穿透反爬抓取网页 HTML/Markdown
  Future<String> _scrapeWithFirecrawl(String url) async {
    try {
      final result = await _mcpService.callTool(
        'firecrawl_scrape',
        {
          'url': url,
          'formats': ['html', 'markdown'],
          'onlyMainContent': false,
        },
        targetServerId: 'firecrawl',
      );

      if (result.isError) {
        throw StateError('Firecrawl scrape error: ${result.rawError}');
      }

      return result.text;
    } catch (e) {
      debugPrint('[AntiBotBypassScraper] _scrapeWithFirecrawl error: $e');
      rethrow;
    }
  }

  /// 穿透抓取分类列表页面并解析
  Future<CatalogPageResult> scrapeCategoryPage({
    required String categoryKey,
    required int pageIndex,
  }) async {
    final url = HttpRuleScraper.resolveCategoryUrl(rule, categoryKey, pageIndex);

    try {
      final html = await _scrapeWithFirecrawl(url);
      final document = html_parser.parse(html);
      final baseUri = Uri.parse(url);

      int totalCount = 0;
      final totalMatch = RegExp(r'共有(?:<[^>]+>)*相关作品(?:<[^>]+>)*(\d+)(?:<[^>]+>)*部').firstMatch(html);
      if (totalMatch != null) {
        totalCount = int.tryParse(totalMatch.group(1) ?? '') ?? 0;
      }

      final selector = rule.catalogSelector.isNotEmpty
          ? rule.catalogSelector
          : '#newscontent .l ul li, .novelslist2 ul li, .book-list li, table.grid tr, #content tr';
      final items = document.querySelectorAll(selector);

      final List<DiscoveredNovelItem> list = [];
      for (final el in items) {
        final a = el.querySelector('span.s2 a, td:nth-child(1) a, a[href*="/jie/"], a[href*="/book/"], a[href*="/html/"], a');
        if (a == null) continue;

        var title = a.text.trim();
        final raw = title;
        title = title.replaceAll(RegExp(r'^[《<\[(]|[\s》>\])]$'), '').trim();
        if (title.isEmpty || title == '[0]' || title == '书名' || title == '文章名称') continue;

        final href = a.attributes['href'];
        if (href == null || href.isEmpty || href.startsWith('javascript:')) continue;
        final detailUrl = baseUri.resolve(href.trim()).toString();

        String author = '';
        final authorEl = el.querySelector('span.s4, .author, span:nth-child(4), td:nth-child(3)');
        if (authorEl != null) {
          author = authorEl.text.trim();
        }

        String category = '';
        final catEl = el.querySelector('span.s1, .type, .cat');
        if (catEl != null) {
          category = catEl.text.replaceAll(RegExp(r'[\[\]]'), '').trim();
        }

        String latestChapter = '';
        final chapterEl = el.querySelector('span.s3 a, .latest, span.s3, td:nth-child(2) a');
        if (chapterEl != null) {
          latestChapter = chapterEl.text.trim();
        }

        String lastUpdated = '';
        final timeEl = el.querySelector('span.s5, .time, .date, td:nth-child(5)');
        if (timeEl != null) {
          lastUpdated = timeEl.text.trim();
        }

        list.add(DiscoveredNovelItem(
          title: title,
          rawTitle: raw,
          author: author.isNotEmpty ? author : '佚名',
          detailUrl: detailUrl,
          category: category,
          latestChapter: latestChapter,
          lastUpdated: lastUpdated,
        ));
      }

      final pageSize = list.isNotEmpty ? list.length : 100;
      final totalPages = totalCount > 0 ? (totalCount / pageSize).ceil() : 1;

      return CatalogPageResult(
        items: list,
        totalCount: totalCount,
        totalPages: totalPages,
        currentPage: pageIndex,
      );
    } catch (e) {
      debugPrint('[AntiBotBypassScraper] scrapeCategoryPage failed: $e');
      rethrow;
    }
  }

  /// 抓取目录
  Future<List<ScrapedChapterEntry>> scrapeTableOfContents(String tocUrl) async {
    try {
      final html = await _scrapeWithFirecrawl(tocUrl);
      final document = html_parser.parse(html);

      final tocElements = document.querySelectorAll(rule.tocSelector.isNotEmpty ? rule.tocSelector : 'a');
      final List<ScrapedChapterEntry> entries = [];
      final Uri baseUri = Uri.parse(tocUrl);

      int index = 1;
      for (final el in tocElements) {
        final title = el.text.trim();
        final href = el.attributes['href'];
        if (href == null || href.trim().isEmpty || href.startsWith('javascript:')) continue;
        if (title.isEmpty) continue;

        final resolvedUrl = baseUri.resolve(href.trim()).toString();
        entries.add(ScrapedChapterEntry(
          chapterIndex: index++,
          title: title,
          chapterUrl: resolvedUrl,
        ));
      }

      return entries;
    } catch (e) {
      debugPrint('[AntiBotBypassScraper] fallback to standard http scraper for toc');
      // 降级使用规则 HTTP 尝试
      final fallback = HttpRuleScraper(rule);
      try {
        return await fallback.scrapeTableOfContents(tocUrl);
      } finally {
        fallback.close();
      }
    }
  }

  /// 抓取单章
  Future<ScrapedChapterResult> scrapeChapter(String chapterUrl) async {
    try {
      final raw = await _scrapeWithFirecrawl(chapterUrl);
      final document = html_parser.parse(raw);

      for (final selector in rule.removeSelectors) {
        if (selector.trim().isNotEmpty) {
          document.querySelectorAll(selector.trim()).forEach((e) => e.remove());
        }
      }

      String title = '';
      if (rule.titleSelector.isNotEmpty) {
        final titleEl = document.querySelector(rule.titleSelector);
        if (titleEl != null) title = titleEl.text.trim();
      }
      if (title.isEmpty) {
        final h1 = document.querySelector('h1');
        if (h1 != null) title = h1.text.trim();
      }

      String content = '';
      if (rule.contentSelector.isNotEmpty) {
        final contentEl = document.querySelector(rule.contentSelector);
        if (contentEl != null) {
          content = _cleanElement(contentEl);
        }
      }
      if (content.isEmpty) {
        final body = document.body;
        if (body != null) {
          content = _cleanElement(body);
        }
      }

      return ScrapedChapterResult(title: title, content: content);
    } catch (e) {
      debugPrint('[AntiBotBypassScraper] fallback to standard http scraper for chapter');
      final fallback = HttpRuleScraper(rule);
      try {
        return await fallback.scrapeChapter(chapterUrl);
      } finally {
        fallback.close();
      }
    }
  }

  String _cleanElement(Element element) {
    element.querySelectorAll('br').forEach((br) => br.replaceWith(Text('\n')));
    element.querySelectorAll('p').forEach((p) => p.append(Text('\n\n')));

    final raw = element.text;
    final lines = raw.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => '    $l')
        .join('\n\n');

    return lines;
  }
}
