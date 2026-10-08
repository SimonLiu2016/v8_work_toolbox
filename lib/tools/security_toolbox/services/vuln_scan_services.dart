/// 漏洞扫描：nuclei 模板扫描、sqlmap 注入检测、CVE/CVSS 补充查询。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/security_enums.dart';
import 'security_process_runner.dart';

/// nuclei 模板分类（spec 要求的 6 类）。
class NucleiCategory {
  final String key;
  final String label;
  final String tag;

  const NucleiCategory(this.key, this.label, this.tag);

  static const cves = NucleiCategory('cves', 'CVE 漏洞', 'cve');
  static const exposures = NucleiCategory('exposures', '信息泄露', 'exposure');
  static const misconfiguration = NucleiCategory('misconfiguration', '配置错误', 'misconfig');
  static const defaultLogins = NucleiCategory('default-logins', '默认凭证', 'default-login');
  static const network = NucleiCategory('network', '网络层', 'network');
  static const technologies = NucleiCategory('technologies', '技术识别', 'tech');

  static const values = [
    cves,
    exposures,
    misconfiguration,
    defaultLogins,
    network,
    technologies,
  ];
}

/// nuclei 的一条发现（JSONL 单行）。
class NucleiFinding {
  final String templateId;
  final String name;
  final String severity;
  final String matchedAt;
  final String? description;
  final String? cveId;
  final double? cvssScore;
  final Map<String, dynamic> raw;

  const NucleiFinding({
    required this.templateId,
    required this.name,
    required this.severity,
    required this.matchedAt,
    this.description,
    this.cveId,
    this.cvssScore,
    this.raw = const {},
  });

  static NucleiFinding? parseRow(Map<String, dynamic> row) {
    final info = row['info'];
    if (info is! Map) return null;
    final templateId = row['template-id'] as String? ?? '';
    final name = info['name'] as String? ?? templateId;
    if (templateId.isEmpty) return null;
    final severity = (info['severity'] as String? ?? 'info').toLowerCase();

    final classification = info['classification'];
    var cveId = _firstStringOf(classification, 'cve-id');
    var cvss = _firstNumOf(classification, 'cvss-score');
    var description = info['description'] as String?;

    // 有些模板把 CVE 写在 reference 里，metadata 只留 tags。
    if (cveId == null) {
      final tags = info['tags'];
      if (tags is String) {
        final match = RegExp(r'cve-\d{4}-\d+').firstMatch(tags.toLowerCase());
        if (match != null) cveId = match.group(0)!.toUpperCase();
      }
    }
    final metadata = info['metadata'];
    if (metadata is Map) {
      cvss ??= _firstNumOf(metadata, 'cvss-score');
      description ??= metadata['description'] as String?;
    }

    return NucleiFinding(
      templateId: templateId,
      name: name,
      severity: severity,
      matchedAt: row['matched-at'] as String? ?? '',
      description: description,
      cveId: cveId,
      cvssScore: cvss,
      raw: row,
    );
  }

  static String? _firstStringOf(dynamic container, String key) {
    if (container is! Map) return null;
    final v = container[key];
    if (v is String && v.isNotEmpty) return v;
    if (v is List && v.isNotEmpty) return v.first.toString();
    return null;
  }

  static double? _firstNumOf(dynamic container, String key) {
    if (container is! Map) return null;
    final v = container[key];
    // nuclei 的 cvss-score / cve-id 都是数组，且元素可能是字符串。
    if (v is List) {
      for (final item in v) {
        final parsed = _toDouble(item);
        if (parsed != null) return parsed;
      }
      return null;
    }
    return _toDouble(v);
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// 归一到枚举值。nuclei 的 severity 有 unknown/critical/high/medium/low/info。
  Severity get severityLevel => Severity.fromKey(severity);
}

/// sqlmap 的一条注入发现。
class SqlmapFinding {
  final String targetUrl;
  final String? parameter;
  final String? title;
  final String? dbms;
  final String? technique;

  const SqlmapFinding({
    required this.targetUrl,
    this.parameter,
    this.title,
    this.dbms,
    this.technique,
  });
}

/// nuclei 扫描（流式 JSONL）。
///
/// 逐行解析、每条发现立即经 [onFinding] 抛出——调用方直接写库，
/// nuclei 扫描（流式 JSONL 与周期统计）。
///
/// 逐行解析、每条发现立即经 [onFinding] 抛出——调用方直接写库，
/// 这样进程被 kill 时已发现的部分不丢（spec「扫描进度与中断」）。
abstract final class NucleiService {
  /// 从 URL、主机名或 host:port 中提取纯主机名或 IP。
  static String extractHost(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final host = Uri.tryParse(raw)?.host;
      if (host != null && host.isNotEmpty) return host;
    }
    if (raw.contains('://')) {
      final idx = raw.indexOf('://');
      raw = raw.substring(idx + 3);
    }
    if (raw.contains('/')) {
      raw = raw.split('/').first;
    }
    if (raw.contains(':')) {
      raw = raw.split(':').first;
    }
    return raw;
  }

  /// 构建 nuclei 命令行参数（便于测试与统一管理）。
  static List<String> buildArgs(
    List<NucleiCategory> categories, {
    List<Severity>? severities,
    bool enableStats = true,
    int statsIntervalSeconds = 5,
  }) {
    final tags = categories.map((c) => c.tag).toSet().toList();
    final sevKeys = severities?.map((s) => s.key).toSet().toList();
    return [
      '-jsonl',
      '-no-color',
      if (enableStats) ...[
        '-stats',
        '-si',
        '$statsIntervalSeconds',
      ],
      if (tags.isNotEmpty) ...['-tags', tags.join(',')],
      if (sevKeys != null && sevKeys.isNotEmpty) ...['-s', sevKeys.join(',')],
    ];
  }

  /// 判断是否为 Nuclei 的统计 JSON，并格式化为友好的展示文本。
  static String? formatStatsLine(Map<String, dynamic> json) {
    if (!json.containsKey('percent') && !json.containsKey('requests')) {
      return null;
    }
    final percent = json['percent'] ?? '0';
    final requests = json['requests'] ?? '0';
    final total = json['total'] ?? '0';
    final rps = json['rps'] ?? '0';
    final matched = json['matched'] ?? '0';
    final duration = json['duration'] ?? '00:00';
    return '[扫描进度] $percent% | 请求: $requests/$total ($rps req/s) | 发现: $matched | 耗时: $duration';
  }

  static Future<void> scan({
    required List<String> targets,
    List<NucleiCategory> categories = const [NucleiCategory.cves],
    List<Severity>? severities,
    bool enableStats = true,
    Duration timeout = const Duration(minutes: 30),
    void Function(NucleiFinding finding)? onFinding,
    void Function(String line)? onLog,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (targets.isEmpty) return;
    final resolved = resolveExecutable('nuclei');
    if (resolved == null) {
      onLog?.call('未检测到 nuclei，请先在工具状态面板安装');
      return;
    }
    final args = buildArgs(
      categories,
      severities: severities,
      enableStats: enableStats,
    );
    try {
      final process = await Process.start(
        resolved,
        args,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      process.stdin.write(targets.join('\n'));
      await process.stdin.close();

      final done = <Future>[
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              if (!trimmed.startsWith('{')) {
                onLog?.call(trimmed);
                return;
              }
              try {
                final decoded = jsonDecode(trimmed);
                if (decoded is! Map) {
                  onLog?.call(trimmed);
                  return;
                }
                final map = Map<String, dynamic>.from(decoded);
                final stats = formatStatsLine(map);
                if (stats != null) {
                  onLog?.call(stats);
                  final req = int.tryParse(map['requests']?.toString() ?? '');
                  final tot = int.tryParse(map['total']?.toString() ?? '');
                  if (req != null && tot != null && tot > 0) {
                    onProgress?.call(req, tot);
                  }
                  return;
                }

                final finding = NucleiFinding.parseRow(map);
                if (finding != null) {
                  onFinding?.call(finding);
                }
              } catch (_) {
                onLog?.call(trimmed);
              }
            })
            .asFuture<void>(),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (line.trim().isNotEmpty) onLog?.call(line);
            })
            .asFuture<void>(),
      ];
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill(ProcessSignal.sigterm);
        return -1;
      });
      await Future.wait(done).timeout(
        const Duration(seconds: 3),
        onTimeout: () => <void>[],
      );
      if (exitCode != 0) {
        onLog?.call('nuclei 扫描结束（退出码: $exitCode）');
      }
    } catch (e) {
      onLog?.call('nuclei 启动失败: $e');
    }
  }
}

/// sqlmap 的一次结果文件定位结果。
class SqlmapResultFile {
  final File jsonFile;
  final List<SqlmapFinding> findings;

  const SqlmapResultFile({required this.jsonFile, required this.findings});
}

/// sqlmap 注入检测。
///
/// 结论优先来自 `--output-dir` 下的结构化结果文件（design A 的原始决策）：
/// sqlmap 的 stdout 格式在版本间不稳定，刮正则是把当初规避的风险又请回来。
/// 结构文件找不到时才回退 stdout 正则，并在日志里标明用了回退路径。
abstract final class SqlmapService {
  static Future<List<SqlmapFinding>> scan(
    List<String> urls, {
    Duration timeout = const Duration(minutes: 20),
    void Function(String line)? onLog,
    String? outputDir,
  }) async {
    if (urls.isEmpty) return const [];
    final resolved = resolveExecutable('sqlmap');
    if (resolved == null) {
      onLog?.call('未检测到 sqlmap，请先在工具状态面板安装');
      return const [];
    }
    final dir = outputDir ?? Directory.systemTemp.createTempSync('sqlmap_').path;
    final runStart = DateTime.now();
    final findings = <SqlmapFinding>[];

    for (final url in urls) {
      if (resolveExecutable('sqlmap') == null) break;
      final args = <String>[
        '-u',
        url,
        '--batch',
        '--output-dir',
        dir,
        '--disable-coloring',
        '--flush-session',
      ];
      final result = await runCaptured(resolved, args, timeout: timeout);
      if (onLog != null) {
        for (final line in result.stdout.split('\n')) {
          if (line.trim().isNotEmpty) onLog(line);
        }
      }

      final parsed = _parseResultDir(
        dir,
        url: url,
        since: runStart,
        onLog: onLog,
      );
      if (parsed != null && parsed.isNotEmpty) {
        // 结构化来源：每个 Finding 的 dbms 在解析时就地确定，按 URL 归属，
        // 不再事后改 list.last（多参数 URL 场景下那会贴错条目）。
        findings.addAll(parsed);
        continue;
      }

      // 回退：stdout 关键行。只在结构化解析完全拿不到东西时走。
      onLog?.call('未解析到 sqlmap 结构结果文件，回退 stdout 提取（$url）');
      findings.addAll(_parseStdout(result.stdout, url));
    }
    return findings;
  }

  /// 在 output-dir 下递归找本次写入的 `*.json`，解析为 [SqlmapFinding]。
  ///
  /// [since] 之前的文件不认——上一轮扫描的残留会污染本轮结论。
  static List<SqlmapFinding>? _parseResultDir(
    String dir, {
    required String url,
    required DateTime since,
    void Function(String line)? onLog,
  }) {
    try {
      final root = Directory(dir);
      if (!root.existsSync()) return null;
      final candidates = <File>[];
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.json')) continue;
        final modified = entity.statSync().modified;
        // sqlmap 写完结果文件几乎没有延迟，给 5 秒容差。
        if (modified.isBefore(since.subtract(const Duration(seconds: 5)))) {
          continue;
        }
        candidates.add(entity);
      }
      if (candidates.isEmpty) return null;
      final out = <SqlmapFinding>[];
      for (final file in candidates) {
        out.addAll(_parseResultFile(file, url));
      }
      return out;
    } catch (e) {
      onLog?.call('解析 sqlmap 结果目录失败: $e');
      return null;
    }
  }

  /// 仅供测试：解析单个结果文件。
  @visibleForTesting
  static List<SqlmapFinding> parseResultFileForTest(File file, String url) =>
      _parseResultFile(file, url);

  /// 仅供测试：stdout 回退解析。
  @visibleForTesting
  static List<SqlmapFinding> parseStdoutForTest(String stdout, String url) =>
      _parseStdout(stdout, url);

  /// 解析单个结果文件。布局跨版本差异大，所以只认两种已知形状：
  /// `{"data": [{...}]}` 与顶层数组。
  static List<SqlmapFinding> _parseResultFile(File file, String url) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final rows = decoded is Map ? decoded['data'] : decoded;
      if (rows is! List) return const [];
      final out = <SqlmapFinding>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final value = row['value'];
        final param = row['parameter'] ??
            (value is Map ? value['parameter'] : null);
        final place = row['place'] ?? (value is Map ? value['place'] : null);
        if (param == null && place == null) continue;
        final dbms = _extractDbms(row);
        out.add(
          SqlmapFinding(
            targetUrl: url,
            parameter: param?.toString() ?? place?.toString(),
            technique: place?.toString(),
            dbms: dbms,
            title: dbms == null
                ? '$url 疑似存在 SQL 注入'
                : '$url 疑似存在 SQL 注入（后端 $dbms）',
          ),
        );
      }
      return out;
    } catch (_) {
      // 单个文件畸形不影响其余文件。
      return const [];
    }
  }

  /// dbms 可能出现在 `dbms`、`dbms_fingerprint` 或嵌套的 `value` 里。
  static String? _extractDbms(Map row) {
    for (final key in ['dbms', 'dbms_fingerprint']) {
      final v = row[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final value = row['value'];
    if (value is Map) {
      final v = value['dbms'];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// stdout 回退解析（保留原实现作为兜底）。
  static List<SqlmapFinding> _parseStdout(String stdout, String url) {
    final out = <SqlmapFinding>[];
    final injectable = RegExp(
      r'Parameter: (\S+).*?(GET|POST|Cookie)',
      caseSensitive: false,
    );
    for (final match in injectable.allMatches(stdout)) {
      out.add(
        SqlmapFinding(
          targetUrl: url,
          parameter: match.group(1),
          technique: match.group(2),
          title: '$url 的参数 ${match.group(1)} 可注入',
        ),
      );
    }
    final dbmsMatch = RegExp(
      r'back-end DBMS: ([^\n]+)',
      caseSensitive: false,
    ).firstMatch(stdout);
    if (dbmsMatch != null) {
      final dbms = dbmsMatch.group(1)!.trim();
      // DBMS 是 URL 维度的结论：贴给该 URL 的每一条，而不是 list.last。
      for (var i = 0; i < out.length; i++) {
        final f = out[i];
        out[i] = SqlmapFinding(
          targetUrl: f.targetUrl,
          parameter: f.parameter,
          title: '${f.title}（后端 $dbms）',
          technique: f.technique,
          dbms: dbms,
        );
      }
    }
    return out;
  }
}

/// NVD CVE 详情（CVSS 补充查询的 fallback）。
class CveDetail {
  final String cveId;
  final double? cvssScore;
  final String severity;
  final String description;

  const CveDetail({
    required this.cveId,
    this.cvssScore,
    required this.severity,
    required this.description,
  });
}

/// CVE/CVSS 补充查询。
///
/// 优先用 nuclei 模板自带 metadata；拿不到才打 NVD API（有速率限制，
/// 无 key 时 5 秒 1 次请求，所以这里的查询是串行且带缓存的）。
class CveEnricher {
  CveEnricher._();
  static final CveEnricher instance = CveEnricher._();

  final Map<String, CveDetail> _cache = {};
  static const String _baseUrl =
      'https://services.nvd.nist.gov/rest/json/cves/2.0';

  /// 查询单个 CVE；网络失败返回 null（不抛）。
  Future<CveDetail?> lookup(
    String cveId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cached = _cache[cveId];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('$_baseUrl?cveId=$cveId');
      final client = HttpClient();
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final vulnerabilities = decoded['vulnerabilities'];
      if (vulnerabilities is! List || vulnerabilities.isEmpty) return null;
      final cve = (vulnerabilities.first as Map)['cve'];
      if (cve is! Map) return null;

      final descriptions = cve['descriptions'];
      String description = '';
      if (descriptions is List) {
        for (final d in descriptions) {
          if (d is Map && d['lang'] == 'en') {
            description = d['value']?.toString() ?? '';
            break;
          }
        }
      }
      final metrics = cve['metrics'];
      double? score;
      String severity = 'info';
      if (metrics is Map) {
        // CVSS 3.x 优先，其次 2.0
        for (final key in ['cvssMetricV31', 'cvssMetricV30', 'cvssMetricV2']) {
          final list = metrics[key];
          if (list is List && list.isNotEmpty) {
            final data = (list.first as Map)['cvssData'];
            if (data is Map) {
              score = (data['baseScore'] as num?)?.toDouble();
              severity = (data['baseSeverity'] as String? ?? '').toLowerCase();
            }
            break;
          }
        }
      }
      final detail = CveDetail(
        cveId: cveId,
        cvssScore: score,
        severity: severity.isEmpty ? Severity.fromCvss(score).key : severity,
        description: description,
      );
      _cache[cveId] = detail;
      return detail;
    } catch (_) {
      // 网络不可用时静默失败：CVSS 缺失不该让扫描结果丢失。
      return null;
    }
  }

  /// 批量补齐（串行，避免 NVD 限流；已缓存的跳过）。
  Future<Map<String, CveDetail>> lookupMany(List<String> cveIds) async {
    final result = <String, CveDetail>{};
    for (final id in cveIds) {
      final detail = await lookup(id);
      if (detail != null) result[id] = detail;
    }
    return result;
  }

  void clearCache() => _cache.clear();
}

/// nuclei 严重等级 → 枚举（nuclei 输出 unknown/info/low/medium/high/critical）。
Severity severityFromNuclei(String raw) => Severity.fromKey(raw.toLowerCase());

/// CVSS → 严重等级（spec 的 9/7/4 分档）。
Severity severityFromCvss(double score) => Severity.fromCvss(score);

/// 把 nuclei 发现转为 Finding 的 severity 字符串。
String severityKeyFromNuclei(String raw) => severityFromNuclei(raw).key;
