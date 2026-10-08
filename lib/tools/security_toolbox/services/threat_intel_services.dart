/// 威胁情报：NVD / CISA KEV / GitHub PoC 同步、资产交叉比对、AI 日报。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/security_enums.dart';
import '../models/security_models.dart';

/// NVD / CISA / GitHub 三源同步结果。
class IntelSyncResult {
  final int nvdCount;
  final int kevCount;
  final int pocCount;
  final String? error;

  const IntelSyncResult({
    required this.nvdCount,
    required this.kevCount,
    required this.pocCount,
    this.error,
  });

  int get total => nvdCount + kevCount + pocCount;
}

/// 情报源配置（GitHub token 可选，无 token 时搜索 API 限流更紧）。
class IntelConfig {
  final String? githubToken;
  final int syncIntervalHours;

  const IntelConfig({this.githubToken, this.syncIntervalHours = 4});

  static const defaultHours = 4;
}

/// NVD CVE 2.0 API 的一条原始记录（只取需要的字段）。
class NvdCve {
  final String id;
  final String description;
  final double? cvssScore;
  final String severity;
  final DateTime? published;

  const NvdCve({
    required this.id,
    required this.description,
    this.cvssScore,
    required this.severity,
    this.published,
  });

  ThreatIntelEntry toEntry({
    required bool isKev,
    String? pocUrl,
    required DateTime syncedAt,
  }) {
    return ThreatIntelEntry(
      cveId: id,
      title: description.length > 120
          ? '${description.substring(0, 120)}…'
          : description,
      cvssScore: cvssScore,
      severity: severity,
      description: description,
      published: published,
      isKev: isKev,
      pocUrl: pocUrl,
      syncedAt: syncedAt,
    );
  }
}

/// NVD / CISA KEV / GitHub PoC 三个情报源的同步与解析。
///
/// 同步是纯 IO，写库交给调用方（[SecurityIntelligenceStore]）——这样单测可以
/// 只喂 JSON 文本验证解析，不碰数据库。
abstract final class ThreatIntelFeedService {
  static const String nvdBase =
      'https://services.nvd.nist.gov/rest/json/cves/2.0';
  static const String kevUrl =
      'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json';
  static const Duration httpTimeout = Duration(seconds: 30);

  /// 拉取 NVD 最近 [days] 天的 CVE（增量同步）。
  static Future<List<NvdCve>> fetchNvd({
    int days = 7,
    IntelConfig config = const IntelConfig(),
    Duration timeout = httpTimeout,
  }) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: days));
    String iso(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}'
        'T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.000';
    final uri = Uri.parse(
      '$nvdBase?pubStartDate=${iso(from)}&pubEndDate=${iso(now)}&resultsPerPage=2000',
    );
    final body = await _get(uri, timeout: timeout);
    return parseNvd(body);
  }

  /// 解析 NVD 响应体（测试直接喂 JSON）。
  static List<NvdCve> parseNvd(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final list = decoded['vulnerabilities'];
      if (list is! List) return const [];
      final out = <NvdCve>[];
      for (final item in list) {
        if (item is! Map) continue;
        final cve = item['cve'];
        if (cve is! Map) continue;
        final id = cve['id'] as String?;
        if (id == null) continue;

        String description = '';
        final descriptions = cve['descriptions'];
        if (descriptions is List) {
          for (final d in descriptions) {
            if (d is Map && d['lang'] == 'en') {
              description = d['value']?.toString() ?? '';
              break;
            }
          }
        }
        double? score;
        var severity = 'info';
        final metrics = cve['metrics'];
        if (metrics is Map) {
          for (final key in ['cvssMetricV31', 'cvssMetricV30', 'cvssMetricV2']) {
            final arr = metrics[key];
            if (arr is List && arr.isNotEmpty) {
              final data = (arr.first as Map)['cvssData'];
              if (data is Map) {
                score = (data['baseScore'] as num?)?.toDouble();
                severity = (data['baseSeverity'] as String? ?? '')
                    .toLowerCase();
              }
              break;
            }
          }
        }
        DateTime? published;
        final rawPublished = cve['published'] as String?;
        if (rawPublished != null) {
          published = DateTime.tryParse(rawPublished);
        }
        out.add(
          NvdCve(
            id: id,
            description: description,
            cvssScore: score,
            severity: severity.isEmpty
                ? Severity.fromCvss(score).key
                : severity,
            published: published,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 拉取 CISA KEV 目录。
  static Future<Set<String>> fetchKev({
    Duration timeout = httpTimeout,
  }) async {
    final body = await _get(Uri.parse(kevUrl), timeout: timeout);
    return parseKev(body);
  }

  /// 解析 KEV（返回 CVE 编号集合）。
  static Set<String> parseKev(String body) {
    final ids = <String>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return ids;
      final vulnerabilities = decoded['vulnerabilities'];
      if (vulnerabilities is! List) return ids;
      for (final v in vulnerabilities) {
        if (v is! Map) continue;
        final id = v['cveID'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    } catch (_) {
      // KEV 源不可用时返回空集合：同步照常完成，只是没有 KEV 标记。
    }
    return ids;
  }

  /// GitHub 搜索新 PoC 仓库。
  ///
  /// 关键词是 CVE 编号；返回 cveId → 仓库 URL 的映射。
  static Future<Map<String, String>> searchPocs(
    List<String> cveIds, {
    IntelConfig config = const IntelConfig(),
    Duration timeout = httpTimeout,
  }) async {
    if (cveIds.isEmpty) return const {};
    final results = <String, String>{};
    for (final cve in cveIds.takes(20)) {
      final uri = Uri.parse(
        'https://api.github.com/search/repositories?q=${Uri.encodeComponent(cve)}+in:name,description,readme&sort=updated&order=desc&per_page=3',
      );
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        if (config.githubToken != null)
          'Authorization': 'Bearer ${config.githubToken}',
      };
      try {
        final client = HttpClient();
        final request = await client.getUrl(uri).timeout(timeout);
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(timeout);
        if (response.statusCode != 200) {
          client.close();
          continue;
        }
        final body = await response.transform(utf8.decoder).join();
        client.close();
        final decoded = jsonDecode(body);
        final items = decoded is Map ? decoded['items'] : null;
        if (items is List && items.isNotEmpty) {
          final first = items.first;
          if (first is Map) {
            results[cve] = first['html_url']?.toString() ?? '';
          }
        }
      } catch (_) {
        // 单个 CVE 搜索失败不该中断整轮同步。
      }
    }
    return results;
  }

  /// 执行一次完整同步（NVD + KEV + PoC），返回计数。
  static Future<IntelSyncResult> syncAll({
    int days = 7,
    IntelConfig config = const IntelConfig(),
    void Function(String line)? onLog,
  }) async {
    try {
      onLog?.call('正在同步 NVD（最近 $days 天）…');
      final cves = await fetchNvd(days: days, config: config);
      onLog?.call('NVD 返回 ${cves.length} 条');

      onLog?.call('正在同步 CISA KEV…');
      final kev = await fetchKev();
      onLog?.call('KEV 共 ${kev.length} 条');

      // 只对高危以上的 CVE 查 PoC——全量查询会把 GitHub 限流打满。
      final criticals = cves
          .where((c) => c.severity == 'critical' || c.severity == 'high')
          .take(20)
          .map((c) => c.id)
          .toList();
      onLog?.call('正在检索 GitHub PoC（${criticals.length} 个高危 CVE）…');
      final pocs = await searchPocs(criticals, config: config);
      onLog?.call('发现 ${pocs.length} 个可用 PoC');

      return IntelSyncResult(
        nvdCount: cves.length,
        kevCount: kev.length,
        pocCount: pocs.length,
      );
    } catch (e) {
      return IntelSyncResult(
        nvdCount: 0,
        kevCount: 0,
        pocCount: 0,
        error: e.toString(),
      );
    }
  }

  static Future<String> _get(
    Uri uri, {
    Duration timeout = httpTimeout,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return '';
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }
}

/// 一次情报交叉比对的结论。
class IntelMatch {
  final String cveId;
  final String assetAddress;
  final String matchedService;
  final ThreatIntelEntry entry;

  const IntelMatch({
    required this.cveId,
    required this.assetAddress,
    required this.matchedService,
    required this.entry,
  });
}

/// 资产与情报库的交叉比对。
///
/// 目前做「产品名 + 版本前缀」的宽松匹配：CVE 描述里出现 "Apache 2.4.x" 而资产
/// 是 "Apache httpd 2.4.51" 时算命中。宽松意味着可能误报——所以生成的 Finding
/// 一律是「待验证」状态，由人确认（spec 的 Scenario 也正是这样要求的）。
abstract final class IntelCrossMatcher {
  static List<IntelMatch> match(
    List<PentestAsset> assets,
    List<ThreatIntelEntry> entries,
  ) {
    if (assets.isEmpty || entries.isEmpty) return const [];
    final matches = <IntelMatch>[];
    for (final entry in entries) {
      final keywords = _keywordsFrom(entry.description);
      if (keywords.isEmpty) continue;
      for (final asset in assets) {
        final text = '${asset.address} ${asset.metadataJson}'.toLowerCase();
        for (final kw in keywords) {
          if (text.contains(kw.toLowerCase())) {
            matches.add(
              IntelMatch(
                cveId: entry.cveId,
                assetAddress: asset.address,
                matchedService: kw,
                entry: entry,
              ),
            );
            break;
          }
        }
      }
    }
    return matches;
  }

  /// 从 CVE 描述里抽取可匹配的产品关键词。
  ///
  /// 经验规则：取 "X before/through Y" 前面的产品名，或形如 "Apache 2.4" 的两段词。
  /// 中文/无版本号的描述抽不出东西就跳过，宁可漏报也不乱命中。
  static List<String> _keywordsFrom(String description) {
    final out = <String>[];
    final match = RegExp(
      r'([A-Za-z][A-Za-z0-9_.\- ]{2,40}?) (?:before|through|up to|versions?) ',
      caseSensitive: false,
    ).firstMatch(description);
    if (match != null) {
      final product = match.group(1)!.trim();
      if (product.length >= 3) out.add(product);
    }
    final versioned = RegExp(
      r'\b([A-Za-z][A-Za-z0-9_\-]{2,20}) (\d+\.\d+(?:\.\d+)?)',
    ).allMatches(description);
    for (final m in versioned) {
      out.add('${m.group(1)} ${m.group(2)}');
    }
    return out.toSet().take(6).toList();
  }
}

/// 待同步的人工日报草稿输入。
class DailyDigestInput {
  final List<ThreatIntelEntry> last24h;
  final List<IntelMatch> matches;

  const DailyDigestInput({required this.last24h, required this.matches});
}

/// 生成喂给 AI 的日报 prompt（AI 产出由调用方写回）。
String buildDailyDigestPrompt(DailyDigestInput input) {
  final buf = StringBuffer()
    ..writeln('请基于以下过去 24 小时的漏洞情报生成一份中文安全日报，')
    ..writeln('要求 500 字以内，包含：新增 Critical/High 漏洞摘要、')
    ..writeln('CISA KEV 新增条目、与本地资产相关的漏洞提示、优先关注建议。')
    ..writeln()
    ..writeln('【新增漏洞】');
  for (final e in input.last24h.take(20)) {
    buf.writeln(
      '- ${e.cveId} (CVSS ${e.cvssScore?.toStringAsFixed(1) ?? "未知"})'
      '${e.isKev ? " [KEV]" : ""}: ${e.title}',
    );
  }
  if (input.matches.isNotEmpty) {
    buf.writeln('【资产命中】');
    for (final m in input.matches.take(10)) {
      buf.writeln('- ${m.assetAddress} 命中 ${m.cveId}（${m.matchedService}）');
    }
  }
  return buf.toString();
}

/// 判断一条情报是否在最近 24 小时内。
bool isWithin24h(ThreatIntelEntry entry) {
  return entry.syncedAt.isAfter(
    DateTime.now().subtract(const Duration(hours: 24)),
  );
}

extension _TakeExtension<T> on List<T> {
  List<T> takes(int n) => length <= n ? this : sublist(0, n);
}
