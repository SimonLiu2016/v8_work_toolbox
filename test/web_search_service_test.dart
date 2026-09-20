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
  });

  group('SearXngSearchBackend default-disabled', () {
    test('is disabled by default so queries do not leave the machine', () {
      // 第三方后端默认不参与检索——查询词不会发到陌生第三方实例。
      expect(SearXngSearchBackend.isEnabled, isFalse,
          reason: 'SearXNG must be opt-in to protect privacy');
    });
  });
}
