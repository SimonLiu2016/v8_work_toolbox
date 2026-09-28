import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_http_client.dart';
import 'mcp_service.dart';
import 'proxy_settings.dart';
import '../tools/tool_definition.dart';

// ---------------------------------------------------------------------------
// 数据类型
// ---------------------------------------------------------------------------

/// 单条搜索结果。后端 SHALL 至少填充标题、来源链接与摘要。
class SearchResult {
  final String title;
  final String url;
  final String snippet;

  const SearchResult({required this.title, required this.url, required this.snippet});

  @override
  String toString() => 'SearchResult($title <- $url)';
}

/// 抓取结果。区分「成功但页面为空」与「失败」：失败时 [isError] 为 true 且 [error] 非空。
class ScrapeResult {
  final String content;
  final bool isError;
  final String? error;

  const ScrapeResult.success(this.content)
      : isError = false,
        error = null;
  const ScrapeResult.failure(this.error)
      : isError = true,
        content = '';

  bool get isEmpty => !isError && content.trim().isEmpty;
}

/// 检索结果。失败时 [isError] 为 true 且 [error] 携带首个失败后端的具体原因，
/// 绝不返回空列表伪装成功。
class WebSearchResult {
  final List<SearchResult> results;
  final String? usedBackendName;
  final bool isError;
  final String? error;

  const WebSearchResult.success(this.results, this.usedBackendName)
      : isError = false,
        error = null;
  const WebSearchResult.failure(this.error)
      : isError = true,
        results = const [],
        usedBackendName = null;
}

// ---------------------------------------------------------------------------
// 后端接口
// ---------------------------------------------------------------------------

/// 检索后端接口。每个后端独立探活（[healthCheck]），失败后端在冷却期内跳过。
abstract class SearchBackend {
  /// 后端名称，用于结果溯源与诊断展示。
  String get name;

  /// 搜索。后端 SHALL 在自身不可用时抛异常或返回空结果（由编排层判定降级）。
  Future<List<SearchResult>> search(String query, {int limit = 5});

  /// 抓取单个 URL 的正文。不支持抓取的后端返回 [ScrapeResult.failure]。
  Future<ScrapeResult> scrape(String url) async =>
      ScrapeResult.failure('$name 不支持抓取');

  /// 真实远端探活。MUST 反映远端服务的真实连通性，而非本地组件可达。
  Future<bool> healthCheck();
}

// ---------------------------------------------------------------------------
// 健康缓存与冷却窗口（复用 AiService 的 ProviderHealthState 模式）
// ---------------------------------------------------------------------------

class _BackendHealthState {
  final bool isHealthy;
  final DateTime? lastCheckedAt;
  final int consecutiveFailures;

  const _BackendHealthState({
    this.isHealthy = true,
    this.lastCheckedAt,
    this.consecutiveFailures = 0,
  });

  _BackendHealthState markHealthy() => _BackendHealthState(
        isHealthy: true,
        lastCheckedAt: DateTime.now(),
        consecutiveFailures: 0,
      );

  _BackendHealthState markUnhealthy() => _BackendHealthState(
        isHealthy: false,
        lastCheckedAt: DateTime.now(),
        consecutiveFailures: consecutiveFailures + 1,
      );
}

/// 后端健康快照的不可变公开表示，供 UI 诊断展示。
class BackendHealthSnapshot {
  final bool isHealthy;
  final DateTime? lastCheckedAt;
  final int consecutiveFailures;

  const BackendHealthSnapshot({
    required this.isHealthy,
    required this.lastCheckedAt,
    required this.consecutiveFailures,
  });
}

// ---------------------------------------------------------------------------
// 编排服务
// ---------------------------------------------------------------------------

/// 联网检索与抓取的统一入口。两条后端链各自按优先级自动降级，每个后端独立
/// 探活。替代 [ScheduledNewsService] 与 [AiAssistantService] 中硬编码的
/// `'firecrawl_search'` 字面量。
class WebSearchService extends ChangeNotifier {
  WebSearchService._() {
    ProxySettings.instance.addListener(_onProxySettingsChanged);
  }
  static final WebSearchService instance = WebSearchService._();

  void _onProxySettingsChanged() {
    debugPrint('[WebSearchService] 检测到代理配置变更，清空搜索后端冷却状态');
    clearHealth();
  }

  /// 后端初次失败的冷却时长。短初始冷却支持快速自愈（15s）。
  static const Duration _initialCooldown = Duration(seconds: 15);
  /// 后端常规冷却时长（45s）。
  static const Duration _cooldown = Duration(seconds: 45);

  /// 连续失败达到此阈值后，后端进入延长退避（[_extendedBackoff]），
  /// 避免每 30s tick 都空转。
  static const int _extendedBackoffThreshold = 5;
  static const Duration _extendedBackoff = Duration(minutes: 10);

  final Map<String, _BackendHealthState> _health = {};

  /// 搜索后端链，按优先级排序。首位为零配置默认后端。
  List<SearchBackend> get _searchChain => [
        BingSearchBackend(),
        DuckDuckGoSearchBackend(),
        if (SearXngSearchBackend.isEnabled) SearXngSearchBackend(),
        McpSearchBackend(),
      ];

  /// 抓取后端链。自部署实例优先（用户意图），官方云 keyless 兜底。
  List<SearchBackend> get _scrapeChain => [
        McpScrapeBackend(),
        FirecrawlCloudScrapeBackend(),
      ];

  /// 搜索。首个可用后端返回结果；全部失败时返回携带首个失败原因的失败信号。
  /// 若全部后端处于冷却期，自动自愈重置首位默认后端并强制探测，避免用户陷入永久不可用死锁。
  Future<WebSearchResult> search(String query, {int limit = 5}) async {
    final chain = _searchChain;
    var available = chain.where((b) => !_isInCooldown(b.name)).toList();

    // 自愈恢复机制：若全部后端均在冷却期，自动解除主后端（Bing）的冷却锁并强制发起探测尝试
    if (available.isEmpty && chain.isNotEmpty) {
      final primary = chain.first;
      debugPrint('[WebSearchService] 全部搜索后端处于冷却期，触发自愈机制：重置 ${primary.name} 冷却并执行探测');
      _health.remove(primary.name);
      available = [primary];
    }

    final attempted = <String>[];
    final errors = <String>[];

    for (final backend in available) {
      final name = backend.name;
      attempted.add(name);
      try {
        final results = await backend.search(query, limit: limit);
        if (results.isNotEmpty) {
          _markHealthy(name);
          return WebSearchResult.success(results, name);
        }
        // 空结果视为该后端本轮不可用，降级到下一候选。
        _markUnhealthy(name);
        errors.add('$name 返回空结果');
      } catch (e) {
        _markUnhealthy(name);
        errors.add('$name: $e');
        debugPrint('[$name] 搜索失败: $e');
      }
    }

    if (attempted.isEmpty) {
      return const WebSearchResult.failure('搜索后端链为空，无可用后端');
    }
    return WebSearchResult.failure(errors.join('\n'));
  }

  /// 抓取单个 URL 的正文。
  Future<ScrapeResult> scrape(String url) async {
    String? firstError;
    for (final backend in _scrapeChain) {
      final name = backend.name;
      if (_isInCooldown(name)) continue;
      try {
        final result = await backend.scrape(url);
        if (!result.isError && !result.isEmpty) {
          _markHealthy(name);
          return result;
        }
        if (result.isError) {
          _markUnhealthy(name);
          firstError ??= '$name: ${result.error}';
        }
      } catch (e) {
        _markUnhealthy(name);
        firstError ??= '$name: $e';
      }
    }
    return ScrapeResult.failure(firstError ?? '所有抓取后端均不可用');
  }

  /// 探活指定后端（供 UI 调用）。返回值反映远端真实连通性。
  Future<bool> healthCheck(String backendName) async {
    final backend = [..._searchChain, ..._scrapeChain].firstWhere(
      (b) => b.name == backendName,
      orElse: () => throw ArgumentError('未找到后端: $backendName'),
    );
    final ok = await backend.healthCheck();
    if (ok) {
      _markHealthy(backendName);
    } else {
      _markUnhealthy(backendName);
    }
    return ok;
  }

  /// 所有后端的健康快照，供诊断界面呈现。
  Map<String, BackendHealthSnapshot> get healthSnapshot => _health.map(
        (k, v) => MapEntry(
          k,
          BackendHealthSnapshot(
            isHealthy: v.isHealthy,
            lastCheckedAt: v.lastCheckedAt,
            consecutiveFailures: v.consecutiveFailures,
          ),
        ),
      );

  bool _isInCooldown(String name) {
    final s = _health[name];
    if (s == null || s.isHealthy) return false;
    final elapsed = DateTime.now().difference(s.lastCheckedAt!);
    final Duration backoff;
    if (s.consecutiveFailures >= _extendedBackoffThreshold) {
      backoff = _extendedBackoff;
    } else if (s.consecutiveFailures <= 1) {
      backoff = _initialCooldown;
    } else {
      backoff = _cooldown;
    }
    return elapsed < backoff;
  }

  void _markHealthy(String name) {
    final prev = _health[name];
    _health[name] = (prev ?? const _BackendHealthState()).markHealthy();
    notifyListeners();
  }

  void _markUnhealthy(String name) {
    final prev = _health[name];
    _health[name] = (prev ?? const _BackendHealthState()).markUnhealthy();
    notifyListeners();
  }

  @visibleForTesting
  void clearHealth() {
    _health.clear();
  }
}

// ---------------------------------------------------------------------------
// 后端实现：Bing HTML 解析（双域名自适应与主备容灾互切）
// ---------------------------------------------------------------------------

/// 解析 Bing 的 HTML 结果页。零配置、零密钥、零第三方。
///
/// 具备双端点（`www.bing.com` 与 `cn.bing.com`）自适应探测：
/// 当代理开启时优先访问国际端点 `www.bing.com`，直连时优先访问国内端点 `cn.bing.com`。
/// 遇到握手截断、网络异常或空结果时自动平滑尝试备用端点。
class BingSearchBackend implements SearchBackend {
  @override
  String get name => 'Bing';

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

  static const String internationalHost = 'www.bing.com';
  static const String mainlandHost = 'cn.bing.com';

  /// 根据代理配置获取候选域名列表（首选在前，备选在后）
  static List<String> get candidateHosts {
    final proxy = ProxySettings.instance;
    final isProxyActive =
        proxy.isConfigured && proxy.isToolEnabled(kToolIdAiAssistant);
    if (isProxyActive) {
      return const [internationalHost, mainlandHost];
    } else {
      return const [mainlandHost, internationalHost];
    }
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final hosts = candidateHosts;
    final endpointErrors = <String, String>{};

    for (final host in hosts) {
      // 针对每个端点，支持 1 次瞬态网络/握手重试
      for (var attempt = 0; attempt < 2; attempt++) {
        final client = AppHttpClient.create(toolId: kToolIdAiAssistant);
        try {
          final queryParams = {
            'q': query,
            'count': '$limit',
            'setlang': 'zh-Hans',
            if (host == mainlandHost) 'cc': 'CN' else 'cc': 'US',
          };
          final uri = Uri.https(host, '/search', queryParams);
          final resp = await client.get(uri, headers: {
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Sec-Ch-Ua': '"Chromium";v="123", "Not:A-Brand";v="8"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"macOS"',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-User': '?1',
            'Upgrade-Insecure-Requests': '1',
          }).timeout(const Duration(seconds: 12));

          if (resp.statusCode != 200) {
            throw Exception('$host 返回 HTTP ${resp.statusCode}');
          }
          final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final results = parseHtml(html);
          if (results.isEmpty) {
            throw Exception('$host 结果页结构变更或发生重定向，未匹配到任何 b_algo 块');
          }
          return results.take(limit).toList();
        } catch (e) {
          final isRetryable = e is HandshakeException ||
              e is SocketException ||
              e.toString().contains('HandshakeException') ||
              e.toString().contains('Connection terminated during handshake');
          if (attempt == 0 && isRetryable) {
            await Future.delayed(const Duration(milliseconds: 300));
            continue;
          }
          endpointErrors[host] = e.toString();
          break; // 当前端点失败，尝试下一个候选端点
        } finally {
          client.close();
        }
      }
      debugPrint('[BingSearchBackend] 端点 $host 请求失败 (${endpointErrors[host]})，尝试备用端点');
    }

    final formattedErrors = endpointErrors.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('; ');
    throw Exception('Bing 全部端点均不可用 ($formattedErrors)');
  }

  @visibleForTesting
  static List<SearchResult> parseHtml(String html) {
    final titlePattern = RegExp(
      r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
    );
    final snippetPattern = RegExp(
      r'<p class="b_lineclamp[01]"[^>]*>(.*?)</p>',
    );
    final blockPattern = RegExp(r'<li class="b_algo".*?</li>', dotAll: true);

    final results = <SearchResult>[];
    for (final block in blockPattern.allMatches(html)) {
      final blockText = block.group(0)!;
      final titleMatch = titlePattern.firstMatch(blockText);
      if (titleMatch == null) continue;
      final url = _decodeHtmlEntities(titleMatch.group(1)!);
      // 跳过 Bing 自家导航类链接。
      if (url.contains('bing.com/search') || url.contains('microsoft.com/')) {
        continue;
      }
      final titleRaw = titleMatch.group(2)!;
      final title = _stripTags(_decodeHtmlEntities(titleRaw)).trim();
      if (title.isEmpty) continue;

      final snippetMatch = snippetPattern.firstMatch(blockText);
      final snippet = snippetMatch == null
          ? ''
          : _stripTags(_decodeHtmlEntities(snippetMatch.group(1)!)).trim();
      results.add(SearchResult(title: title, url: url, snippet: snippet));
    }
    return results;
  }

  static String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

  static String _decodeHtmlEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  @override
  Future<bool> healthCheck() async {
    for (final host in candidateHosts) {
      final client = AppHttpClient.create(toolId: kToolIdAiAssistant);
      try {
        final resp = await client
            .get(Uri.parse('https://$host/search?q=test'),
                headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) return true;
      } catch (_) {
        // 继续探测下一个候选端点
      } finally {
        client.close();
      }
    }
    return false;
  }

  @override
  Future<ScrapeResult> scrape(String url) async =>
      ScrapeResult.failure('$name 不提供抓取');
}

// ---------------------------------------------------------------------------
// 后端实现：DuckDuckGo HTML Lite（免密钥二级兜底）
// ---------------------------------------------------------------------------

/// 解析 `html.duckduckgo.com/html` 的 HTML 结果页。零配置、零密钥、免第三方服务。
class DuckDuckGoSearchBackend implements SearchBackend {
  @override
  String get name => 'DuckDuckGo';

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final client = AppHttpClient.create(toolId: kToolIdAiAssistant);
    try {
      // 优先尝试 POST 请求（DuckDuckGo 经典表单搜索）
      var resp = await client.post(
        Uri.parse('https://html.duckduckgo.com/html/'),
        headers: {
          'User-Agent': _ua,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Origin': 'https://html.duckduckgo.com',
          'Referer': 'https://html.duckduckgo.com/',
        },
        body: {'q': query},
      ).timeout(const Duration(seconds: 12));

      // 若遇 HTTP 202（人机反爬拦截或中间态），尝试 GET 方式回退
      if (resp.statusCode == 202) {
        resp = await client.get(
          Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}'),
          headers: {
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Referer': 'https://duckduckgo.com/',
          },
        ).timeout(const Duration(seconds: 12));
      }

      if (resp.statusCode != 200) {
        if (resp.statusCode == 202) {
          throw Exception('DuckDuckGo 返回 HTTP 202 (触发反爬验证或代理节点拦截)');
        }
        throw Exception('DuckDuckGo 返回 HTTP ${resp.statusCode}');
      }
      final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final results = parseHtml(html);
      if (results.isEmpty) {
        throw Exception('DuckDuckGo 结果页未匹配到任何结果');
      }
      return results.take(limit).toList();
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  static List<SearchResult> parseHtml(String html) {
    final bodyPattern = RegExp(
      r'<div class="[^"]*result__body[^"]*".*?(?=<div class="[^"]*result__body|<!-- Web results are finished|$)',
      dotAll: true,
    );
    final titlePattern = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      r'<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    final results = <SearchResult>[];
    for (final block in bodyPattern.allMatches(html)) {
      final blockText = block.group(0)!;
      final titleMatch = titlePattern.firstMatch(blockText);
      if (titleMatch == null) continue;

      var url = _decodeHtmlEntities(titleMatch.group(1)!);
      if (url.contains('uddg=')) {
        final parsedUri =
            Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
        final uddg = parsedUri?.queryParameters['uddg'];
        if (uddg != null && uddg.isNotEmpty) {
          url = uddg;
        }
      } else if (url.startsWith('//')) {
        url = 'https:$url';
      }

      final titleRaw = titleMatch.group(2)!;
      final title = _stripTags(_decodeHtmlEntities(titleRaw)).trim();
      if (title.isEmpty) continue;

      final snippetMatch = snippetPattern.firstMatch(blockText);
      final snippet = snippetMatch == null
          ? ''
          : _stripTags(_decodeHtmlEntities(snippetMatch.group(1)!)).trim();

      results.add(SearchResult(title: title, url: url, snippet: snippet));
    }

    return results;
  }

  static String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '');

  static String _decodeHtmlEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  @override
  Future<bool> healthCheck() async {
    final client = AppHttpClient.create(toolId: kToolIdAiAssistant);
    try {
      final resp = await client.post(
        Uri.parse('https://html.duckduckgo.com/html/'),
        headers: {
          'User-Agent': _ua,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'q': 'test'},
      ).timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Future<ScrapeResult> scrape(String url) async =>
      ScrapeResult.failure('$name 不提供抓取');
}

// ---------------------------------------------------------------------------
// 后端实现：SearXNG（第三方托管，用户显式启用）
// ---------------------------------------------------------------------------

/// 第三方托管 SearXNG 实例。查询词会发送到第三方服务器，MUST 由用户显式启用，
/// 且启用时 UI SHALL 提示隐私风险。
class SearXngSearchBackend implements SearchBackend {
  @override
  String get name => 'SearXNG';

  /// 用户在设置中显式启用后参与搜索链。默认不启用。
  static bool isEnabled = false;

  /// 候选实例列表。可用率约 3/9，失败后由冷却窗口临时摘除。
  static const List<String> _instances = [
    'https://baresearch.org',
    'https://search.inetol.net',
    'https://searx.work',
    'https://searx.tiekoetter.com',
    'https://opnxng.com',
  ];

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final client = AppHttpClient.create();
    try {
      for (final base in _instances) {
        final uri = Uri.parse(
          '$base/search?q=${Uri.encodeQueryComponent(query)}&format=json',
        );
        try {
          final resp = await client.get(uri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) V8WorkToolbox',
            'Accept': 'application/json',
          }).timeout(const Duration(seconds: 12));
          if (resp.statusCode == 429) continue;
          if (resp.statusCode != 200) continue;
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final rawResults = (body['results'] as List?) ?? [];
          final out = <SearchResult>[];
          for (final r in rawResults.take(limit)) {
            if (r is! Map) continue;
            final title = (r['title'] as String?)?.trim() ?? '';
            final url = (r['url'] as String?)?.trim() ?? '';
            final content = (r['content'] as String?)?.trim() ?? '';
            if (title.isEmpty || url.isEmpty) continue;
            out.add(SearchResult(title: title, url: url, snippet: content));
          }
          if (out.isNotEmpty) return out;
        } catch (_) {
          continue;
        }
      }
      throw Exception('所有 SearXNG 实例均失败');
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final client = AppHttpClient.create();
      try {
        final resp = await client.get(
          Uri.parse('${_instances.first}/search?q=test&format=json'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        return resp.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ScrapeResult> scrape(String url) async =>
      ScrapeResult.failure('$name 不提供抓取');
}

// ---------------------------------------------------------------------------
// 后端实现：MCP 自部署 Firecrawl（搜索链末位 / 抓取链首位）
// ---------------------------------------------------------------------------

/// 封装对已配置自部署 Firecrawl 实例的 MCP 调用。作为搜索链末位兜底。
class McpSearchBackend implements SearchBackend {
  @override
  String get name => 'Firecrawl (自部署 MCP)';

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    final result = await McpService.instance.callTool(
      'firecrawl_search',
      {'query': query, 'limit': limit},
    );
    if (result.isError) {
      throw Exception(result.rawError ?? 'firecrawl_search 失败');
    }
    // MCP 返回的 firecrawl_search 结果是文本块，从中粗提取标题/链接。
    final text = result.text;
    if (text.isEmpty) return [];
    return _extractFromFirecrawlText(text, limit);
  }

  static List<SearchResult> _extractFromFirecrawlText(String text, int limit) {
    // Firecrawl 搜索结果通常以 markdown 链接列表形式返回。
    final linkPattern = RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)');
    final results = <SearchResult>[];
    for (final m in linkPattern.allMatches(text)) {
      results.add(SearchResult(
        title: m.group(1)!,
        url: m.group(2)!,
        snippet: '',
      ));
      if (results.length >= limit) break;
    }
    return results;
  }

  @override
  Future<bool> healthCheck() async {
    // 真实探活：调用 firecrawl_scrape example.com，强制一次远端网络请求。
    final result = await McpService.instance.callTool(
      'firecrawl_scrape',
      {'url': 'https://example.com', 'formats': ['markdown'], 'onlyMainContent': true},
    );
    return !result.isError && result.text.isNotEmpty;
  }

  @override
  Future<ScrapeResult> scrape(String url) async {
    final result = await McpService.instance.callTool(
      'firecrawl_scrape',
      {'url': url, 'formats': ['markdown'], 'onlyMainContent': true},
    );
    if (result.isError) {
      return ScrapeResult.failure(result.rawError ?? 'firecrawl_scrape 失败');
    }
    return ScrapeResult.success(result.text);
  }
}

/// 自部署 Firecrawl 实例的抓取后端。抓取链首位（用户意图优先）。
class McpScrapeBackend implements SearchBackend {
  @override
  String get name => 'Firecrawl 抓取 (自部署 MCP)';

  @override
  Future<ScrapeResult> scrape(String url) async {
    final result = await McpService.instance.callTool(
      'firecrawl_scrape',
      {'url': url, 'formats': ['markdown'], 'onlyMainContent': true},
    );
    if (result.isError) {
      return ScrapeResult.failure(result.rawError ?? 'firecrawl_scrape 失败');
    }
    final text = result.text;
    if (text.isEmpty) return const ScrapeResult.success('');
    return ScrapeResult.success(text);
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    throw UnsupportedError('$name 不提供搜索');
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final result = await scrape('https://example.com');
      return !result.isError;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// 后端实现：Firecrawl 官方云 keyless（抓取链兜底）
// ---------------------------------------------------------------------------

/// `api.firecrawl.dev/v1/scrape` 的 keyless 调用。实测 `/v1/scrape` 可用
/// （200，返回真实 markdown），`/v1/search` 返回 500，因此仅用于抓取链。
class FirecrawlCloudScrapeBackend implements SearchBackend {
  @override
  String get name => 'Firecrawl 官方云 (keyless)';

  static const _endpoint = 'https://api.firecrawl.dev/v1/scrape';

  @override
  Future<ScrapeResult> scrape(String url) async {
    final client = AppHttpClient.create();
    try {
      final resp = await client
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': url,
              'formats': ['markdown'],
              'onlyMainContent': true,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) {
        return ScrapeResult.failure('HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ?? false;
      if (!success) {
        return ScrapeResult.failure(body['error']?.toString() ?? '云端返回 success:false');
      }
      final data = (body['data'] as Map<String, dynamic>?) ?? {};
      final markdown = (data['markdown'] as String?) ?? '';
      return ScrapeResult.success(markdown);
    } catch (e) {
      return ScrapeResult.failure(e.toString());
    } finally {
      client.close();
    }
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 5}) async {
    throw UnsupportedError('$name 不提供搜索（官方云 /v1/search 实测 500）');
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final result = await scrape('https://example.com');
      return !result.isError && result.content.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
