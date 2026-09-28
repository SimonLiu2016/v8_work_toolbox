import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class QueryResult {
  final List<String> headers;
  final List<List<String>> rows;

  const QueryResult({
    required this.headers,
    required this.rows,
  });

  Map<String, dynamic> toJson() => {
        'headers': headers,
        'rows': rows,
      };

  factory QueryResult.fromJson(Map<String, dynamic> json) => QueryResult(
        headers: (json['headers'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        rows: (json['rows'] as List<dynamic>? ?? [])
            .map((r) => (r as List<dynamic>).map((c) => c.toString()).toList())
            .toList(),
      );
}

// ============================================================================
// PhpMyAdmin & Database HTTP Query Client
// ============================================================================

class PhpMyAdminClient {
  final String url;
  final String? username;
  final String? password;
  final http.Client _client;
  String _csrfToken = '';

  PhpMyAdminClient({
    required this.url,
    this.username,
    this.password,
  }) : _client = IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true,
        );

  String baseUrl() {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<void> login() async {
    if (username == null || username!.isEmpty) {
      await _fetchToken();
      return;
    }

    final loginUrl = Uri.parse('${baseUrl()}/index.php');
    await _client.post(
      loginUrl,
      body: {
        'pma_username': username!,
        'pma_password': password ?? '',
      },
    );
    await _fetchToken();
  }

  Future<void> _fetchToken() async {
    try {
      final resp = await _client.get(Uri.parse('${baseUrl()}/index.php'));
      final body = resp.body;
      final m = RegExp(r'name="token"\s+value="([^"]+)"').firstMatch(body) ??
          RegExp(r'token=([a-f0-9]+)').firstMatch(body);
      if (m != null) {
        _csrfToken = m.group(1) ?? '';
      }
    } catch (_) {}
  }

  Future<QueryResult> executeQuery(String sqlQuery, {String db = ''}) async {
    final queryUrl = Uri.parse('${baseUrl()}/import.php');
    final resp = await _client.post(
      queryUrl,
      headers: {'Accept': 'application/json, text/html'},
      body: {
        'token': _csrfToken,
        'db': db,
        'sql_query': sqlQuery,
        'ajax_request': 'true',
      },
    );

    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data.containsKey('rows') && data.containsKey('columns')) {
          final cols = (data['columns'] as List<dynamic>).map((e) => e.toString()).toList();
          final rows = (data['rows'] as List<dynamic>)
              .map((r) => (r as List<dynamic>).map((c) => c.toString()).toList())
              .toList();
          return QueryResult(headers: cols, rows: rows);
        }
      } catch (_) {}
    }

    // Fallback: parse simple table HTML
    final body = resp.body;
    final headers = <String>[];
    final rows = <List<String>>[];

    final thMatches = RegExp(r'<th[^>]*>(.*?)<\/th>', dotAll: true).allMatches(body);
    for (final th in thMatches) {
      final text = (th.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (text.isNotEmpty && !text.toLowerCase().contains('action')) {
        headers.add(text);
      }
    }

    final trMatches = RegExp(r'<tr[^>]*>(.*?)<\/tr>', dotAll: true).allMatches(body);
    for (final tr in trMatches) {
      final trHtml = tr.group(1) ?? '';
      final tdMatches = RegExp(r'<td[^>]*>(.*?)<\/td>', dotAll: true).allMatches(trHtml);
      if (tdMatches.isNotEmpty) {
        final row = tdMatches
            .map((td) => (td.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim())
            .toList();
        if (row.isNotEmpty) rows.add(row);
      }
    }

    if (headers.isEmpty && rows.isEmpty) {
      return QueryResult(
        headers: ['Result'],
        rows: [
          [resp.statusCode == 200 ? 'Query executed successfully' : 'Execution returned ${resp.statusCode}']
        ],
      );
    }

    return QueryResult(headers: headers, rows: rows);
  }
}

// ============================================================================
// Grafana Client
// ============================================================================

class GrafanaClient {
  final String url;
  final String apiKey;
  final http.Client _client;

  GrafanaClient({
    required this.url,
    required this.apiKey,
  }) : _client = IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true,
        );

  String baseUrl() {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    for (final pattern in ['/api/dashboards/', '/api/dashboards', '/d/', '/dashboard/', '/dashboard']) {
      final idx = u.indexOf(pattern);
      if (idx != -1) {
        return u.substring(0, idx);
      }
    }
    return u;
  }

  Map<String, String> _headers() => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  Future<void> testConnection() async {
    final uri = Uri.parse('${baseUrl()}/api/org');
    final resp = await _client.get(uri, headers: _headers());
    if (resp.statusCode != 200) {
      throw Exception('Grafana 连接失败 (${resp.statusCode}): 请检查 URL 和 API Key');
    }
  }

  Future<List<Map<String, dynamic>>> listDatasources() async {
    final uri = Uri.parse('${baseUrl()}/api/datasources');
    final resp = await _client.get(uri, headers: _headers());
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    throw Exception('获取 Grafana 数据源失败 (${resp.statusCode})');
  }

  Future<List<Map<String, dynamic>>> listDashboards() async {
    final uri = Uri.parse('${baseUrl()}/api/search?type=dash-db');
    final resp = await _client.get(uri, headers: _headers());
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    throw Exception('获取 Grafana 看板失败 (${resp.statusCode})');
  }

  Future<QueryResult> executeQuery(String datasourceUid, Map<String, dynamic> queryPayload) async {
    final uri = Uri.parse('${baseUrl()}/api/ds/query');
    final resp = await _client.post(uri, headers: _headers(), body: jsonEncode(queryPayload));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as Map<String, dynamic>? ?? {};
      final List<String> headers = [];
      final List<List<String>> rows = [];

      for (final val in results.values) {
        final frames = val['frames'] as List<dynamic>?;
        if (frames != null && frames.isNotEmpty) {
          final firstFrame = frames.first as Map<String, dynamic>;
          final schema = firstFrame['schema'] as Map<String, dynamic>?;
          final fields = schema?['fields'] as List<dynamic>?;
          if (fields != null) {
            for (final f in fields) {
              headers.add(f['name']?.toString() ?? 'val');
            }
          }
          final valuesList = firstFrame['data']?['values'] as List<dynamic>?;
          if (valuesList != null && valuesList.isNotEmpty) {
            final rowCount = (valuesList.first as List<dynamic>).length;
            for (var r = 0; r < rowCount; r++) {
              final row = <String>[];
              for (var c = 0; c < valuesList.length; c++) {
                final colArr = valuesList[c] as List<dynamic>;
                row.add(r < colArr.length ? colArr[r]?.toString() ?? '' : '');
              }
              rows.add(row);
            }
          }
        }
      }
      return QueryResult(headers: headers, rows: rows);
    }
    throw Exception('执行 Grafana 查询失败 (${resp.statusCode}): ${resp.body}');
  }
}

// ============================================================================
// PingCode Client
// ============================================================================

class PingcodeClient {
  final String baseUrl;
  final String ssoUrl;
  final String username;
  final String password;
  final http.Client _client;
  String? token;

  PingcodeClient({
    required this.baseUrl,
    required this.ssoUrl,
    required this.username,
    required this.password,
    this.token,
  }) : _client = IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true,
        );

  String cleanUrl(String u) {
    var s = u.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<String> login() async {
    if (token != null && token!.isNotEmpty) return token!;

    final uri = Uri.parse('${cleanUrl(ssoUrl)}/api/v1/auth/login');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final t = data['data']?['token'] as String? ?? data['token'] as String?;
      if (t != null) {
        token = t;
        return t;
      }
    }
    throw Exception('PingCode 登录失败 (${resp.statusCode}): 请核对账号密码或 SSO 地址');
  }

  Future<QueryResult> executeQuery(String apiPath, Map<String, dynamic> payload) async {
    final t = await login();
    final uri = Uri.parse('${cleanUrl(baseUrl)}$apiPath');
    final resp = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = data['values'] as List<dynamic>? ??
          data['data']?['values'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          [];

      final headers = <String>{'ID', 'Title', 'Status', 'Assignee'};
      final rows = <List<String>>[];

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final id = item['_id']?.toString() ?? item['identifier']?.toString() ?? '';
          final title = item['title']?.toString() ?? item['name']?.toString() ?? '';
          final status = item['status']?['name']?.toString() ?? item['status']?.toString() ?? '';
          final assignee = item['assignee']?['name']?.toString() ?? '';
          rows.add([id, title, status, assignee]);
        }
      }

      return QueryResult(headers: headers.toList(), rows: rows);
    }
    throw Exception('PingCode 查询失败 (${resp.statusCode}): ${resp.body}');
  }
}
