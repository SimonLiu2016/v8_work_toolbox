import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class JenkinsConfig {
  final String url;
  final String username;
  final String token;

  const JenkinsConfig({
    required this.url,
    required this.username,
    required this.token,
  });

  factory JenkinsConfig.fromJson(Map<String, dynamic> json) => JenkinsConfig(
        url: json['url'] as String? ?? '',
        username: json['username'] as String? ?? '',
        token: json['token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'token': token,
      };
}

class BuildStatus {
  final bool building;
  final String result;
  final int number;
  final String url;

  const BuildStatus({
    required this.building,
    required this.result,
    required this.number,
    required this.url,
  });

  factory BuildStatus.fromJson(Map<String, dynamic> json) => BuildStatus(
        building: json['building'] as bool? ?? false,
        result: json['result'] as String? ?? 'UNKNOWN',
        number: json['number'] as int? ?? 0,
        url: json['url'] as String? ?? '',
      );
}

class JenkinsClient {
  final JenkinsConfig config;
  final http.Client _client;

  JenkinsClient(this.config)
      : _client = IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true,
        );

  String baseUrl() {
    var u = config.url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  String _basicAuth() {
    return 'Basic ${base64Encode(utf8.encode('${config.username}:${config.token}'))}';
  }

  Future<(String, String)?> getCrumb() async {
    final uri = Uri.parse('${baseUrl()}/crumbIssuer/api/json');
    try {
      final resp = await _client.get(uri, headers: {
        'Authorization': _basicAuth(),
      });
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final field = body['crumbRequestField'] as String? ?? body['crumbFieldName'] as String? ?? '';
        final crumb = body['crumb'] as String? ?? '';
        if (field.isNotEmpty && crumb.isNotEmpty) {
          return (field, crumb);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> testConnection() async {
    final uri = Uri.parse('${baseUrl()}/api/json');
    final resp = await _client.get(uri, headers: {
      'Authorization': _basicAuth(),
    });

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Jenkins 连接失败 (${resp.statusCode}): 请检查 URL 和认证信息');
    }
  }

  Future<bool> triggerBuild(String jobName, [Map<String, String>? params]) async {
    final crumb = await getCrumb();
    final urlStr = (params != null && params.isNotEmpty)
        ? '${baseUrl()}/job/$jobName/buildWithParameters'
        : '${baseUrl()}/job/$jobName/build';

    final uri = Uri.parse(urlStr);
    final headers = <String, String>{
      'Authorization': _basicAuth(),
    };

    if (crumb != null) {
      headers[crumb.$1] = crumb.$2;
    }

    http.Response resp;
    if (params != null && params.isNotEmpty) {
      resp = await _client.post(uri, headers: headers, body: params);
    } else {
      resp = await _client.post(uri, headers: headers);
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300 || resp.statusCode == 201) {
      return true;
    } else {
      throw Exception('Jenkins 触发构建失败 (${resp.statusCode}): ${resp.body}');
    }
  }

  Future<BuildStatus> getBuildStatus(String jobName) async {
    final uri = Uri.parse('${baseUrl()}/job/$jobName/lastBuild/api/json');
    final resp = await _client.get(uri, headers: {
      'Authorization': _basicAuth(),
    });

    if (resp.statusCode != 200) {
      throw Exception('Jenkins 查询构建状态失败 (${resp.statusCode})');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return BuildStatus.fromJson(body);
  }
}
