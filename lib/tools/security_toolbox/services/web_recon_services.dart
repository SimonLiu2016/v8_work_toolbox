/// Web 资产侦察：subfinder / httpx / gau / ffuf / katana / shodan。
///
/// 每个服务都是「拼参数 → 跑进程 → 解析 JSON/JSONL → 返回结构化对象」的同构形状，
/// 所以共用一个 `_runJson` 帮手；差异只在参数和解析函数。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/security_enums.dart';
import 'lan_recon_services.dart' show parseJsonLines;
import 'security_process_runner.dart';

/// subfinder 发现的一个子域名。
class SubdomainResult {
  final String host;
  final String? source;
  final String? ip;

  const SubdomainResult({required this.host, this.source, this.ip});

  static List<SubdomainResult> parseJson(String text) {
    final out = <SubdomainResult>[];
    for (final row in parseJsonLines(text)) {
      final host = row['host'] as String?;
      if (host == null || host.isEmpty) continue;
      out.add(
        SubdomainResult(
          host: host,
          source: row['source'] as String?,
          ip: row['ip'] as String?,
        ),
      );
    }
    return out;
  }
}

/// httpx 探测到的一个存活 HTTP 资产。
class HttpxResult {
  final String url;
  final int? statusCode;
  final String? title;
  final String? webServer;
  final String? contentLength;
  final List<String> tech;
  final String? host;
  final String? ip;

  const HttpxResult({
    required this.url,
    this.statusCode,
    this.title,
    this.webServer,
    this.contentLength,
    this.tech = const [],
    this.host,
    this.ip,
  });

  static List<HttpxResult> parseJson(String text) {
    final out = <HttpxResult>[];
    for (final row in parseJsonLines(text)) {
      final url = row['url'] as String?;
      if (url == null || url.isEmpty) continue;
      final techRaw = row['tech'];
      out.add(
        HttpxResult(
          url: url,
          statusCode: (row['status_code'] as num?)?.toInt(),
          title: row['title'] as String?,
          webServer: row['webserver'] as String?,
          contentLength: row['content_length']?.toString(),
          tech: techRaw is List ? techRaw.map((e) => e.toString()).toList() : const [],
          host: row['host'] as String?,
          ip: row['a'] is List ? (row['a'] as List).firstOrNull?.toString() : null,
        ),
      );
    }
    return out;
  }

  Map<String, dynamic> toMetadata() => {
    'status_code': statusCode,
    'title': title,
    'webserver': webServer,
    'content_length': contentLength,
    'tech_stack': tech,
    'ip': ip,
  };
}

/// gau 产出的一个历史 URL。
class GauResult {
  final String url;
  const GauResult(this.url);

  static List<GauResult> parse(String text) {
    final out = <GauResult>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        out.add(GauResult(trimmed));
      }
    }
    return out;
  }
}

/// ffuf 发现的一个路径。
class FfufFinding {
  final String url;
  final int? status;
  final int? length;
  final String? words;

  const FfufFinding({required this.url, this.status, this.length, this.words});

  static List<FfufFinding> parseJson(String text) {
    final out = <FfufFinding>[];
    for (final row in parseJsonLines(text)) {
      final url = row['url'] as String?;
      if (url == null || url.isEmpty) continue;
      out.add(
        FfufFinding(
          url: url,
          status: (row['status'] as num?)?.toInt(),
          length: (row['length'] as num?)?.toInt(),
          words: row['words']?.toString(),
        ),
      );
    }
    return out;
  }
}

/// katana 爬出的一个端点。
class KatanaResult {
  final String url;
  final String? source;
  final String? tag;

  const KatanaResult({required this.url, this.source, this.tag});

  static List<KatanaResult> parseJson(String text) {
    final out = <KatanaResult>[];
    for (final row in parseJsonLines(text)) {
      final url = row['request']?['endpoint'] ?? row['url'];
      if (url is! String || url.isEmpty) continue;
      out.add(
        KatanaResult(
          url: url,
          source: row['source'] as String?,
          tag: row['tag'] as String?,
        ),
      );
    }
    return out;
  }
}

/// 跑一次 web recon 工具并拿回原始输出（流式日志可选）。
Future<String> _run(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(minutes: 5),
  void Function(String line)? onLog,
}) async {
  if (resolveExecutable(executable) == null) {
    return '';
  }
  // 用 runCaptured 收集全量输出；子域名/URL 的量级在万行内，增量流式解析的
  // 复杂度不划算——这也是扫描结束一次性写入资产库的原因。
  final result = await runCaptured(executable, args, timeout: timeout);
  if (onLog != null) {
    for (final line in result.stdout.split('\n')) {
      if (line.trim().isNotEmpty) onLog(line);
    }
  }
  return result.stdout;
}

/// 解析后的 Web 目标信息（支持清洗协议、提取端口、识别 IP/内网）。
class WebTargetInfo {
  final String raw;
  final String host;
  final int? port;
  final String? scheme;
  final bool isIp;
  final bool isLocalOrPrivate;

  const WebTargetInfo({
    required this.raw,
    required this.host,
    this.port,
    this.scheme,
    required this.isIp,
    required this.isLocalOrPrivate,
  });

  /// 是否应跳过子域名枚举（IP 或内网/localhost 目标无真实子域名可言）。
  bool get shouldSkipSubdomainEnumeration => isIp || isLocalOrPrivate;

  /// 用于存活探测的主机或 URL 格式表示。
  String get probeTarget {
    if (scheme != null && port != null) {
      return '$scheme://$host:$port';
    } else if (scheme != null) {
      return '$scheme://$host';
    } else if (port != null) {
      return '$host:$port';
    }
    return host;
  }

  /// 归一化展示地址（用于资产列表展示或作为 asset.address）。
  String get displayAddress {
    if (port != null && port != 80 && port != 443) {
      return '$host:$port';
    }
    return host;
  }

  /// 从单行文本中解析目标。
  static WebTargetInfo? parse(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;

    String? scheme;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final idx = raw.indexOf('://');
      scheme = raw.substring(0, idx).toLowerCase();
      raw = raw.substring(idx + 3);
    }

    // 剥离可能存在的路径、查询参数和 fragment
    final slashIdx = raw.indexOf('/');
    if (slashIdx != -1) {
      raw = raw.substring(0, slashIdx);
    }
    final qIdx = raw.indexOf('?');
    if (qIdx != -1) {
      raw = raw.substring(0, qIdx);
    }
    final hashIdx = raw.indexOf('#');
    if (hashIdx != -1) {
      raw = raw.substring(0, hashIdx);
    }

    raw = raw.trim();
    if (raw.isEmpty) return null;

    String hostPart;
    int? portPart;

    if (raw.startsWith('[') && raw.contains(']')) {
      // IPv6: [::1]:8080
      final end = raw.indexOf(']');
      hostPart = raw.substring(1, end);
      final rest = raw.substring(end + 1);
      if (rest.startsWith(':')) {
        portPart = int.tryParse(rest.substring(1));
      }
    } else if (raw.contains(':')) {
      final parts = raw.split(':');
      hostPart = parts[0];
      portPart = int.tryParse(parts[1]);
    } else {
      hostPart = raw;
    }

    final ip = InternetAddress.tryParse(hostPart);
    final isIp = ip != null;
    final isLocal = hostPart.toLowerCase() == 'localhost' ||
        hostPart.toLowerCase().endsWith('.local') ||
        (ip != null && (ip.isLoopback || _isPrivateIp(ip)));

    return WebTargetInfo(
      raw: input,
      host: hostPart,
      port: portPart,
      scheme: scheme,
      isIp: isIp,
      isLocalOrPrivate: isLocal,
    );
  }

  static bool _isPrivateIp(InternetAddress ip) {
    if (ip.isLoopback) return true;
    if (ip.type == InternetAddressType.IPv4) {
      final raw = ip.rawAddress;
      // 10.0.0.0/8
      if (raw[0] == 10) return true;
      // 172.16.0.0/12 (172.16 - 172.31)
      if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return true;
      // 192.168.0.0/16
      if (raw[0] == 192 && raw[1] == 168) return true;
      // 127.0.0.0/8
      if (raw[0] == 127) return true;
      // 169.254.0.0/16 (link local)
      if (raw[0] == 169 && raw[1] == 254) return true;
    } else if (ip.type == InternetAddressType.IPv6) {
      if (ip.isLinkLocal) return true;
      final raw = ip.rawAddress;
      // fc00::/7 (Unique Local Address)
      if ((raw[0] & 0xfe) == 0xfc) return true;
    }
    return false;
  }

  /// 从多行输入或逗号/分号/空白分隔文本中解析目标列表。
  static List<WebTargetInfo> parseList(String text) {
    final tokens = text.split(RegExp(r'[\n,;\s]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    final out = <WebTargetInfo>[];
    for (final t in tokens) {
      final parsed = parse(t);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

abstract final class SubfinderService {
  static Future<List<SubdomainResult>> run(
    List<String> domains, {
    Duration timeout = const Duration(minutes: 5),
    void Function(String line)? onLog,
  }) async {
    if (domains.isEmpty) return const [];
    final out = await _run(
      'subfinder',
      ['-all', '-silent', '-json', '-d', domains.join(',')],
      timeout: timeout,
      onLog: onLog,
    );
    return SubdomainResult.parseJson(out);
  }
}

abstract final class HttpxService {
  /// 校验本机 httpx 是否为 ProjectDiscovery 二进制（非 Python 同名库）。
  static Future<bool> isPdHttpxAvailable() async {
    final exe = resolveExecutable('httpx');
    if (exe == null) return false;
    try {
      final res = await runCaptured('httpx', ['-version'], timeout: const Duration(seconds: 3));
      // ProjectDiscovery 的 httpx -version 输出包含 "ProjectDiscovery" 或 "httpx" 版本号如 v1.x.x
      final out = '${res.stdout} ${res.stderr}'.toLowerCase();
      if (out.contains('projectdiscovery') || out.contains('current version')) {
        return true;
      }
      // Python 的 httpx 会提示 "No such option: -e" 或 "Usage: httpx"
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<HttpxResult>> run(
    List<String> targets, {
    Duration timeout = const Duration(minutes: 5),
    void Function(String line)? onLog,
  }) async {
    if (targets.isEmpty) return const [];

    final hasPdHttpx = await isPdHttpxAvailable();
    if (hasPdHttpx) {
      // 目标走 stdin：子域名列表动辄上万条，塞进 argv 会撞 ARG_MAX。
      final out = await _runWithStdin(
        'httpx',
        const [
          '-json',
          '-silent',
          '-tech-detect',
          '-title',
          '-status-code',
          '-web-server',
          '-content-length',
          '-ip',
          '-no-color',
        ],
        targets.join('\n'),
        timeout: timeout,
        onLog: onLog,
      );
      final results = HttpxResult.parseJson(out);
      if (results.isNotEmpty) {
        return results;
      }
    }

    // CLI 不可用或未能返回存活结果时，执行 Dart 原生并发测活兜底
    onLog?.call('使用内置 HTTP 并发探活引擎进行存活与指纹探测…');
    return runNativeProbe(targets, timeout: const Duration(seconds: 10), onLog: onLog);
  }

  /// 基于 Dart 原生 HttpClient 的轻量探活与指纹识别引擎。
  static Future<List<HttpxResult>> runNativeProbe(
    List<String> targets, {
    Duration timeout = const Duration(seconds: 8),
    void Function(String line)? onLog,
  }) async {
    final results = <HttpxResult>[];
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = timeout;

    try {
      for (final rawTarget in targets) {
        final probeResult = await _probeSingleTarget(client, rawTarget, timeout: timeout);
        if (probeResult != null) {
          results.add(probeResult);
          final titleStr = probeResult.title != null && probeResult.title!.isNotEmpty ? ' [${probeResult.title}]' : '';
          final serverStr = probeResult.webServer != null && probeResult.webServer!.isNotEmpty ? ' [${probeResult.webServer}]' : '';
          onLog?.call('${probeResult.url} [${probeResult.statusCode}]$titleStr$serverStr');
        }
      }
    } finally {
      client.close(force: true);
    }
    return results;
  }

  static Future<HttpxResult?> _probeSingleTarget(
    HttpClient client,
    String raw, {
    required Duration timeout,
  }) async {
    final parsed = WebTargetInfo.parse(raw);
    final host = parsed?.host ?? raw;
    final port = parsed?.port;
    final explicitScheme = parsed?.scheme;

    // 确定探测候选方案：若指定了 http/https 则只测该协议，否则优先尝试 http 然后尝试 https
    final schemes = explicitScheme != null ? [explicitScheme] : ['http', 'https'];

    for (final scheme in schemes) {
      final effectivePort = port ?? (scheme == 'https' ? 443 : 80);
      final portSuffix = (scheme == 'http' && effectivePort == 80) || (scheme == 'https' && effectivePort == 443)
          ? ''
          : ':$effectivePort';
      final urlStr = '$scheme://$host$portSuffix/';

      try {
        final uri = Uri.parse(urlStr);
        final request = await client.getUrl(uri).timeout(timeout);
        request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (V8WorkToolbox Security Recon)');
        request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        request.followRedirects = true;
        request.maxRedirects = 3;

        final response = await request.close().timeout(timeout);
        final statusCode = response.statusCode;
        final server = response.headers.value(HttpHeaders.serverHeader);
        final contentLength = response.headers.value(HttpHeaders.contentLengthHeader) ??
            (response.contentLength != -1 ? response.contentLength.toString() : null);

        // 收集响应体前 64KB 用于提取 HTML Title
        String? title;
        final tech = <String>[];
        if (server != null && server.isNotEmpty) {
          tech.add(server);
        }
        final xPoweredBy = response.headers.value('x-powered-by');
        if (xPoweredBy != null && xPoweredBy.isNotEmpty) {
          tech.add(xPoweredBy);
        }

        try {
          final bodyBytes = await response
              .take(65536)
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
              .timeout(const Duration(seconds: 3));
          final bodyText = utf8.decode(bodyBytes, allowMalformed: true);
          title = _extractTitle(bodyText);
        } catch (_) {}

        return HttpxResult(
          url: urlStr,
          statusCode: statusCode,
          title: title,
          webServer: server,
          contentLength: contentLength,
          tech: tech,
          host: host,
          ip: parsed?.isIp == true ? host : null,
        );
      } catch (_) {
        // 当前 scheme 失败，尝试下一个 scheme
        continue;
      }
    }
    return null;
  }

  static String? _extractTitle(String html) {
    final match = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
    if (match != null) {
      final raw = match.group(1)?.trim();
      if (raw != null && raw.isNotEmpty) {
        return raw.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    return null;
  }

  static Future<String> _runWithStdin(
    String executable,
    List<String> args,
    String input, {
    Duration timeout = const Duration(minutes: 5),
    void Function(String line)? onLog,
  }) async {
    final resolved = resolveExecutable(executable);
    if (resolved == null) return '';
    try {
      final process = await Process.start(
        resolved,
        args,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      process.stdin.write(input);
      await process.stdin.close();
      final buf = StringBuffer();
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            buf.writeln(line);
            onLog?.call(line);
          });
      await process.exitCode.timeout(timeout, onTimeout: () => -1);
      return buf.toString();
    } catch (_) {
      return '';
    }
  }
}

abstract final class GauService {
  static Future<List<GauResult>> run(
    List<String> domains, {
    List<String> providers = const ['wayback', 'commoncrawl', 'otx', 'urlscan'],
    Duration timeout = const Duration(minutes: 5),
    void Function(String line)? onLog,
  }) async {
    if (domains.isEmpty) return const [];
    final out = await _run(
      'gau',
      ['--threads', '5', '--subs', ...domains],
      timeout: timeout,
      onLog: onLog,
    );
    return GauResult.parse(out);
  }
}

abstract final class FfufService {
  /// 选字典：显式指定 > 默认定位。都拿不到时明确报错并返回 null。
  ///
  /// 返回 null 表示不该启动 ffuf——带着空路径跑，ffuf 的报错是
  /// "no input files specified"，用户看不出是字典问题。
  static String? _resolveWordlist(
    String wordlist, {
    void Function(String line)? onLog,
  }) {
    if (wordlist.isNotEmpty) return wordlist;
    final found = resolveDefaultWordlist();
    if (found != null) return found;
    onLog?.call(
      '未找到默认字典（已查找 /opt/homebrew/share 与 /usr/local/share 下的 '
      'seclists）。请安装 seclists 或在参数中手动指定字典路径。',
    );
    return null;
  }

  /// Homebrew seclists 的两个前缀（Apple Silicon / Intel）。
  ///
  /// 写死 `/opt/homebrew` 会让 Intel Mac 永远找不到字典——本机就是 Intel，
  /// 实测 ffuf 带着空字典路径启动只会静默返回空。
  static const List<String> _seclistsPrefixes = [
    '/opt/homebrew/share',
    '/usr/local/share',
  ];

  /// 定位默认字典；找不到返回 null。
  static String? resolveDefaultWordlist({
    List<String> prefixes = _seclistsPrefixes,
  }) {
    const rel = 'seclists/Discovery/Web-Content/common.txt';
    for (final prefix in prefixes) {
      final candidate = '$prefix/$rel';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static Future<List<FfufFinding>> run(
    String url, {
    String wordlist = '',
    List<String> extensions = const ['', '.php', '.bak', '.conf', '.json'],
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLog,
  }) async {
    if (resolveExecutable('ffuf') == null) return const [];
    final resolvedWordlist = _resolveWordlist(wordlist, onLog: onLog);
    if (resolvedWordlist == null) return const [];
    final args = <String>[
      '-json',
      '-s',
      '-u',
      url.replaceAll('FUZZ', 'FUZZ'),
      '-w',
      resolvedWordlist,
      '-mc',
      '200,204,301,302,307,401,403',
      '-t',
      '40',
    ];
    if (extensions.isNotEmpty) {
      args.addAll(['-e', extensions.join(',')]);
    }
    final out = await _run('ffuf', args, timeout: timeout, onLog: onLog);
    return FfufFinding.parseJson(out);
  }
}

abstract final class KatanaService {
  static Future<List<KatanaResult>> run(
    String url, {
    Duration timeout = const Duration(minutes: 5),
    void Function(String line)? onLog,
  }) async {
    final out = await _run(
      'katana',
      ['-jc', '-jsonl', '-silent', '-d', '3', '-u', url],
      timeout: timeout,
      onLog: onLog,
    );
    return KatanaResult.parseJson(out);
  }
}

/// Shodan API Key 与 CLI 查询。
///
/// Key 存放在设置里（settings_store 的工具配置），不放 secure_storage：
/// 它不是登录凭证，用户可能在多台机器间同步配置，且 shodan CLI 自己也从
/// `~/.config/shodan/api_key` 读同一把 key。
abstract final class ShodanService {
  static const String cli = 'shodan';
  static const String infoUrl = 'https://account.shodan.io';

  static Future<bool> isAvailable() async =>
      resolveExecutable(cli) != null;

  /// 查询单个 IP 的情报，返回原始 JSON。
  static Future<Map<String, dynamic>?> queryIp(
    String ip,
    String apiKey, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (apiKey.isEmpty) return null;
    final out = await _runWithKey(
      ['host', ip],
      apiKey,
      timeout: timeout,
    );
    try {
      final decoded = jsonDecode(out);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _runWithKey(
    List<String> args,
    String apiKey, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final resolved = resolveExecutable(cli);
    if (resolved == null) return '';
    try {
      final result = await runCaptured(
        resolved,
        args,
        timeout: timeout,
      );
      // shodan CLI 不接 --key 参数时读环境变量 SHODAN_API_KEY。
      return result.stdout;
    } catch (_) {
      return '';
    }
  }

  /// 把 Shodan 结果合并进资产 metadata。
  static Map<String, dynamic> mergeShodan(
    Map<String, dynamic> metadata,
    Map<String, dynamic> shodan,
  ) {
    final merged = Map<String, dynamic>.from(metadata);
    merged['shodan'] = {
      'organization': shodan['org'],
      'isp': shodan['isp'],
      'os': shodan['os'],
      'ports': shodan['ports'] is List
          ? (shodan['ports'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      'vulns': shodan['vulns'] is List
          ? (shodan['vulns'] as List).map((e) => e.toString()).toList()
          : const <String>[],
      'last_update': shodan['last_update'],
      'country': shodan['country_name'],
    };
    return merged;
  }
}

/// 从 URL 列表里挑出"可能有参数"的候选（sqlmap 目标筛选）。
bool hasQueryParameters(String url) {
  final q = Uri.tryParse(url);
  if (q == null) return false;
  return q.queryParameters.isNotEmpty;
}

/// 风险等级推断（Web 资产）：有 `X-Powered-By`/debug 标记、状态码异常的优先。
String riskLevelForWeb(HttpxResult r) {
  if (r.statusCode != null && r.statusCode! >= 500) return Severity.medium.key;
  final server = (r.webServer ?? '').toLowerCase();
  if (server.contains('debug') || server.contains('test')) {
    return Severity.medium.key;
  }
  if (r.tech.isNotEmpty) return Severity.info.key;
  return Severity.low.key;
}
