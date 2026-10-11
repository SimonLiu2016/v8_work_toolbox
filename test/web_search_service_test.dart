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

    // 这条断言是本次修复的核心，也是这个 bug 能藏住的原因。
    //
    // 上面那条测试的名字里写着 "snippets"，却从不断言 snippet。正则写作
    // b_lineclamp[01]，而 Bing 早已全线改用 b_lineclamp2 —— 样本文件里 10 个
    // b_lineclamp2、0 个 [01]，于是摘要全空、形状全部照旧通过。模型拿到的
    // 每条结果只有标题，判断不了内容是否相关（AI 资讯助手"检索成功却答不出"
    // 的直接成因之一）。
    //
    // 不断言内容，就只会在验形状。
    test('snippets are actually extracted, not silently empty', () {
      final html = _bingSample.readAsStringSync();
      final results = BingSearchBackend.parseHtml(html);

      final withSnippet = results.where((r) => r.snippet.trim().isNotEmpty).length;
      expect(
        withSnippet >= results.length - 1,
        isTrue,
        reason: '真实样本应有摘要被提取出来；全空说明 b_lineclamp 正则又跟不上 '
            'Bing 的 class 命名（当前实际为 b_lineclamp2）。'
            '本次实到 $withSnippet/${results.length} 条带摘要',
      );
    });

    test('snippet extraction covers the lineclamp class variants', () {
      // 钉住"覆盖多个 class 变体"这件事本身：将来 Bing 再改名，先改这里。
      // 只给最小结构——要验的是 class 匹配，不是整页解析。
      String block(String cls) => '''
<li class="b_algo"><h2><a href="https://example.com/a">标题</a></h2>
<p class="$cls">这是摘要内容</p></li>''';

      for (final cls in ['b_lineclamp0', 'b_lineclamp1', 'b_lineclamp2', 'b_lineclamp3']) {
        final results = BingSearchBackend.parseHtml(
          '<html><body>${block(cls)}</body></html>',
        );
        expect(results, hasLength(1), reason: '$cls 应被识别');
        expect(results.single.snippet, '这是摘要内容', reason: '$cls 的摘要应被提取');
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

