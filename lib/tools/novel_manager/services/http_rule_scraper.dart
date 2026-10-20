import 'dart:convert';
import 'dart:io';
import 'package:charset_converter/charset_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../../../services/app_http_client.dart';
import '../models/novel_models.dart';

/// 待抓取的章节条目（目录阶段获得）
class ScrapedChapterEntry {
  final int chapterIndex;
  final String title;
  final String chapterUrl;

  const ScrapedChapterEntry({
    required this.chapterIndex,
    required this.title,
    required this.chapterUrl,
  });
}

/// 抓取得到的单章正文结果
class ScrapedChapterResult {
  final String title;
  final String content;

  const ScrapedChapterResult({
    required this.title,
    required this.content,
  });
}

/// 探索分类列表的分页响应
class CatalogPageResult {
  final List<DiscoveredNovelItem> items;
  final int totalCount;
  final int totalPages;
  final int currentPage;

  const CatalogPageResult({
    required this.items,
    required this.totalCount,
    required this.totalPages,
    required this.currentPage,
  });
}

/// 轻量级 HTTP 规则抓取器
class HttpRuleScraper {
  final SiteScraperRule rule;
  final http.Client _client = AppHttpClient.create(toolId: 'novel_manager');

  HttpRuleScraper(this.rule);

  void close() {
    _client.close();
  }

  /// 发起请求并智能解码（若遇反爬防护拦截返回 403/Turnstile，则调用系统原生 curl 穿透）
  Future<String> _fetchHtml(String url) async {
    var targetUrl = url;
    if (targetUrl.contains('szlajc.com') && targetUrl.startsWith('https://')) {
      targetUrl = targetUrl.replaceFirst('https://', 'http://');
    }

    // 针对开启了反爬穿透或已知反爬站点（如 szlajc.com），直接使用原生 curl 快速穿透（注意勿带假桌面 UA，避免触发 Cloudflare Turnstile 挑战）
    if (rule.enableBypass || targetUrl.contains('szlajc.com')) {
      try {
        final result = await Process.run('curl', [
          '-s',
          '-L',
          '--max-time', '15',
          targetUrl,
        ], stdoutEncoding: systemEncoding);

        if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
          final out = result.stdout as String;
          if (!out.contains('Just a moment...') && !out.contains('cf-chl-widget')) {
            return out;
          }
        }
      } catch (e) {
        debugPrint('[HttpRuleScraper] curl process fetcher error: $e');
      }
    }

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      ...rule.customHeaders,
    };

    http.Response response;
    try {
      response = await _client.get(Uri.parse(targetUrl), headers: headers).timeout(const Duration(seconds: 15));
      if (response.statusCode == 403 && targetUrl.startsWith('https://')) {
        targetUrl = targetUrl.replaceFirst('https://', 'http://');
        final fallbackResp = await _client.get(Uri.parse(targetUrl), headers: headers).timeout(const Duration(seconds: 10));
        if (fallbackResp.statusCode < 400) {
          response = fallbackResp;
        }
      }
    } catch (e) {
      if (targetUrl.startsWith('https://')) {
        try {
          targetUrl = targetUrl.replaceFirst('https://', 'http://');
          response = await _client.get(Uri.parse(targetUrl), headers: headers).timeout(const Duration(seconds: 10));
        } catch (_) {
          // 降级使用 curl
          response = http.Response('', 500);
        }
      } else {
        response = http.Response('', 500);
      }
    }

    if (response.statusCode >= 400) {
      // 最终尝试 curl 降级救底
      try {
        final result = await Process.run('curl', [
          '-s',
          '-L',
          '--max-time', '15',
          '-H', 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
          targetUrl,
        ], stdoutEncoding: systemEncoding);
        if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
          return result.stdout as String;
        }
      } catch (_) {}

      throw HttpException('HTTP error ${response.statusCode}', uri: Uri.parse(targetUrl));
    }

    final bytes = response.bodyBytes;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';

    // 判断编码
    if (contentType.contains('gbk') || contentType.contains('gb2312')) {
      try {
        final decoded = await CharsetConverter.decode('gbk', bytes);
        return decoded;
      } catch (_) {}
    }

    // 默认尝试 utf-8，若抛出异常则尝试 gbk 降级
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return await CharsetConverter.decode('gbk', bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }

  /// 提取小说页面基本信息（如从目录页提取书名、作者、简介、封面）
  Future<Map<String, String>> extractNovelMetadata(String url) async {
    try {
      final html = await _fetchHtml(url);
      final document = html_parser.parse(html);
      final baseUri = Uri.parse(url);

      String title = '';
      String author = '';
      String description = '';
      String coverUrl = '';

      // 1. 尝试 OpenGraph meta 标签
      final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
      if (ogTitle != null && ogTitle.isNotEmpty) title = ogTitle.trim();

      final ogAuthor = document.querySelector('meta[property="og:novel:author"]')?.attributes['content'] ??
          document.querySelector('meta[name="author"]')?.attributes['content'];
      if (ogAuthor != null && ogAuthor.isNotEmpty) author = ogAuthor.trim();

      final ogDesc = document.querySelector('meta[property="og:description"]')?.attributes['content'] ??
          document.querySelector('meta[name="description"]')?.attributes['content'];
      if (ogDesc != null && ogDesc.isNotEmpty) description = ogDesc.trim();

      final ogImage = document.querySelector('meta[property="og:image"]')?.attributes['content'];
      if (ogImage != null && ogImage.isNotEmpty) {
        coverUrl = baseUri.resolve(ogImage.trim()).toString();
      }

      // 2. 降级为常规元素
      if (title.isEmpty) {
        final h1 = document.querySelector('#info h1, .bookname h1, h1');
        if (h1 != null) title = h1.text.trim();
      }
      if (author.isEmpty) {
        final authorEl = document.querySelector('#info p, .author');
        if (authorEl != null) {
          final raw = authorEl.text;
          if (raw.contains('作') && raw.contains('者')) {
            author = raw.replaceAll(RegExp(r'.*作\s*者[：:\s]*'), '').trim();
          }
        }
      }

      return {
        'title': title,
        'author': author,
        'description': description,
        'coverUrl': coverUrl,
      };
    } catch (e) {
      debugPrint('[HttpRuleScraper] extractNovelMetadata error: $e');
      return {};
    }
  }

  /// 探索抓取站点书库/目录，发现可采集的小说列表
  Future<List<DiscoveredNovelItem>> scrapeCatalog(String catalogUrl) async {
    final html = await _fetchHtml(catalogUrl);
    final document = html_parser.parse(html);
    final baseUri = Uri.parse(catalogUrl);

    final selector = rule.catalogSelector.isNotEmpty
        ? rule.catalogSelector
        : '#newscontent .l ul li, .novelslist2 ul li, .book-list li';
    final items = document.querySelectorAll(selector);

    final List<DiscoveredNovelItem> results = [];

    for (final el in items) {
      // 提取书名与小说详情链接
      final a = el.querySelector('span.s2 a, a[href*="/jie/"], a[href*="/book/"], a');
      if (a == null) continue;

      var title = a.text.trim();
      title = title.replaceAll(RegExp(r'^[《<\[(]|[\s》>\])]$'), '').trim();
      if (title.isEmpty) continue;

      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href.startsWith('javascript:')) continue;
      final detailUrl = baseUri.resolve(href.trim()).toString();

      // 提取作者
      String author = '';
      final authorEl = el.querySelector('span.s4, .author, span:nth-child(4)');
      if (authorEl != null) {
        author = authorEl.text.trim();
      }

      // 提取分类
      String category = '';
      final catEl = el.querySelector('span.s1, .type, .cat');
      if (catEl != null) {
        category = catEl.text.replaceAll(RegExp(r'[\[\]]'), '').trim();
      }

      // 提取最新章节
      String latestChapter = '';
      final chapterEl = el.querySelector('span.s3 a, .latest, span.s3');
      if (chapterEl != null) {
        latestChapter = chapterEl.text.trim();
      }

      // 提取更新时间
      String lastUpdated = '';
      final timeEl = el.querySelector('span.s5, .time, .date');
      if (timeEl != null) {
        lastUpdated = timeEl.text.trim();
      }

      results.add(DiscoveredNovelItem(
        title: title,
        rawTitle: title,
        author: author.isNotEmpty ? author : '佚名',
        detailUrl: detailUrl,
        category: category,
        latestChapter: latestChapter,
        lastUpdated: lastUpdated,
      ));
    }

    return results;
  }

  /// 抓取指定分类和页码的列表，并返回总作品数与总页数推导结果
  Future<CatalogPageResult> scrapeCategoryPage({
    required String categoryKey,
    required int pageIndex,
  }) async {
    // 构造 URL: http://www.szlajc.com/class/{type}_{page}/
    final url = '${rule.baseUrl.replaceAll(RegExp(r'/+$'), '')}/class/${categoryKey}_$pageIndex/';
    final html = await _fetchHtml(url);
    final document = html_parser.parse(html);
    final baseUri = Uri.parse(url);

    // 1. 尝试从 <h2>共有<span></span>相关作品<span>334025</span>部</h2> 提取总数
    int totalCount = 0;
    final totalMatch = RegExp(r'共有(?:<[^>]+>)*相关作品(?:<[^>]+>)*(\d+)(?:<[^>]+>)*部').firstMatch(html);
    if (totalMatch != null) {
      totalCount = int.tryParse(totalMatch.group(1) ?? '') ?? 0;
    }

    final selector = rule.catalogSelector.isNotEmpty
        ? rule.catalogSelector
        : '#newscontent .l ul li, .novelslist2 ul li, .book-list li';
    final items = document.querySelectorAll(selector);

    final List<DiscoveredNovelItem> list = [];
    for (final el in items) {
      final a = el.querySelector('span.s2 a, a[href*="/jie/"], a[href*="/book/"], a');
      if (a == null) continue;

      var title = a.text.trim();
      final raw = title;
      title = title.replaceAll(RegExp(r'^[《<\[(]|[\s》>\])]$'), '').trim();
      if (title.isEmpty) continue;

      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href.startsWith('javascript:')) continue;
      final detailUrl = baseUri.resolve(href.trim()).toString();

      String author = '';
      final authorEl = el.querySelector('span.s4, .author, span:nth-child(4)');
      if (authorEl != null) {
        author = authorEl.text.trim();
      }

      String category = '';
      final catEl = el.querySelector('span.s1, .type, .cat');
      if (catEl != null) {
        category = catEl.text.replaceAll(RegExp(r'[\[\]]'), '').trim();
      }

      String latestChapter = '';
      final chapterEl = el.querySelector('span.s3 a, .latest, span.s3');
      if (chapterEl != null) {
        latestChapter = chapterEl.text.trim();
      }

      String lastUpdated = '';
      final timeEl = el.querySelector('span.s5, .time, .date');
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
  }

  /// 提取小说目录章节列表
  Future<List<ScrapedChapterEntry>> scrapeTableOfContents(String tocUrl) async {
    final html = await _fetchHtml(tocUrl);
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

      // 规范化绝对路径
      final resolvedUrl = baseUri.resolve(href.trim()).toString();
      entries.add(ScrapedChapterEntry(
        chapterIndex: index++,
        title: title,
        chapterUrl: resolvedUrl,
      ));
    }

    return entries;
  }

  /// 抓取单章标题与正文
  Future<ScrapedChapterResult> scrapeChapter(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    final document = html_parser.parse(html);

    // 移除干扰广告选择器
    for (final selector in rule.removeSelectors) {
      if (selector.trim().isNotEmpty) {
        document.querySelectorAll(selector.trim()).forEach((e) => e.remove());
      }
    }

    // 提取标题
    String title = '';
    if (rule.titleSelector.isNotEmpty) {
      final titleEl = document.querySelector(rule.titleSelector);
      if (titleEl != null) title = titleEl.text.trim();
    }
    if (title.isEmpty) {
      final h1 = document.querySelector('h1');
      if (h1 != null) title = h1.text.trim();
    }

    // 提取正文
    String content = '';
    if (rule.contentSelector.isNotEmpty) {
      final contentEl = document.querySelector(rule.contentSelector);
      if (contentEl != null) {
        content = _cleanHtmlContent(contentEl);
      }
    }
    if (content.isEmpty) {
      final body = document.body;
      if (body != null) content = _cleanHtmlContent(body);
    }

    return ScrapedChapterResult(title: title, content: content);
  }

  /// 将 HTML 文本节点清洗为干净的段落纯文本
  String _cleanHtmlContent(Element element) {
    // 替换 <br> 与 <p> 为换行
    element.querySelectorAll('br').forEach((br) => br.replaceWith(Text('\n')));
    element.querySelectorAll('p').forEach((p) => p.append(Text('\n\n')));

    final raw = element.text;
    // 移除连续多余空行，每段前补两个空格或保持标准段落缩进
    final lines = raw.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => '    $l')
        .join('\n\n');

    return lines;
  }
}
