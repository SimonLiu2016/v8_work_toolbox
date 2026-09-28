import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/web_search_service.dart';

// 用本机实测抓取的 cn.bing.com HTML 样本验证解析器。样本存放在 test/fixtures。
final _bingSample = File('test/fixtures/bing_sample.html');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BingSearchBackend.parseHtml', () {
    test('extracts titles, urls, snippets from real sample', () {
      final html = _bingSample.readAsStringSync();
      final results = BingSearchBackend.parseHtml(html);
      expect(results, isNotEmpty, reason: 'real bing.html should yield results');
      expect(results.length, greaterThanOrEqualTo(5));
      for (final r in results) {
        expect(r.title, isNotEmpty);
        expect(r.url, startsWith('http'));
        expect(r.url, isNot(contains('bing.com/search')));
      }
    });

    test('returns empty on structure mismatch (no b_algo blocks)', () {
      final bogus = '<html><body><h1>nothing here</h1></body></html>';
      final results = BingSearchBackend.parseHtml(bogus);
      expect(results, isEmpty);
    });
  });

  group('BingSearchBackend.candidateHosts adaptive routing', () {
    test('prefers mainland host when proxy is not configured or disabled', () {
      // 模拟未开启代理环境
      final hosts = BingSearchBackend.candidateHosts;
      // 验证包含双域名
      expect(hosts, containsAll([BingSearchBackend.mainlandHost, BingSearchBackend.internationalHost]));
      expect(hosts.length, equals(2));
    });
  });

  group('DuckDuckGoSearchBackend.parseHtml', () {
    test('extracts results, extracts uddg url, and decodes html entities', () {
      const sampleHtml = '''
<!DOCTYPE html>
<html>
<body>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2F&amp;rut=1">Flutter &amp; Dart&#x27;s Official Site</a>
      </h2>
      <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2F">
        Build apps for any screen with <b>Flutter</b>. It&#039;s fast &amp; portable.
      </a>
    </div>
  </div>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://dart.dev">Dart Language</a>
      </h2>
      <a class="result__snippet" href="https://dart.dev">
        The client-optimized language for fast apps on any platform.
      </a>
    </div>
  </div>
</body>
</html>
''';
      final results = DuckDuckGoSearchBackend.parseHtml(sampleHtml);
      expect(results.length, equals(2));

      // 验证第 1 条结果：uddg 提取与字符解码
      expect(results[0].title, equals("Flutter & Dart's Official Site"));
      expect(results[0].url, equals("https://flutter.dev/"));
      expect(results[0].snippet, contains("It's fast & portable."));

      // 验证第 2 条结果
      expect(results[1].title, equals("Dart Language"));
      expect(results[1].url, equals("https://dart.dev"));
      expect(results[1].snippet, contains("The client-optimized language"));
    });

    test('returns empty when no results match', () {
      const emptyHtml = '<html><body><div>No matching results</div></body></html>';
      final results = DuckDuckGoSearchBackend.parseHtml(emptyHtml);
      expect(results, isEmpty);
    });
  });

  group('WebSearchService backend chain fallback', () {
    test('returns failure with first backend error when all backends fail', () async {
      // 全部后端都不可达时（无网络 / 后端全灭），search MUST 返回失败信号而非
      // 空列表伪装成功。失败信号携带首个失败后端的具体原因。
      WebSearchService.instance.clearHealth();
      final result = await WebSearchService.instance.search(
        '__nonexistent_query_xyz_plz_ignore__',
        limit: 2,
      );
      expect(result.isError, isTrue, reason: 'all backends failing must yield an error, not an empty success');
      expect(result.error, isNotNull);
      expect(result.error, isNot(contains('成功')));
      expect(result.results, isEmpty);
    });

    test('auto-recovers when all backends are in cooldown by probing primary backend', () async {
      // 模拟所有后端都进入冷却期的场景
      final service = WebSearchService.instance;
      // 触发一次全败搜索使得所有后端进入冷却
      await service.search('__nonexistent_query_xyz_plz_ignore__', limit: 1);

      // 再次搜索时，不应直接返回“全部搜索后端处于冷却期，无可用后端”，
      // 而是自愈解除 Bing 的冷却期并尝试探测
      final result2 = await service.search('__nonexistent_query_xyz_plz_ignore__', limit: 1);
      expect(result2.isError, isTrue);
      // 错误信息应来自于探测失败的具体报错，而不是直接的无后端错误
      expect(result2.error, isNot(contains('全部搜索后端处于冷却期，无可用后端')));
      expect(result2.error, contains('Bing 全部端点均不可用'));
    });
  });

  group('SearXngSearchBackend default-disabled', () {
    test('is disabled by default so queries do not leave the machine', () {
      // 第三方后端默认不参与检索——查询词不会发到陌生第三方实例。
      expect(SearXngSearchBackend.isEnabled, isFalse,
          reason: 'SearXNG must be opt-in to protect privacy');
    });
  });
}

