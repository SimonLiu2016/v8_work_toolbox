import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/ops_models.dart';
import 'ops_gitlab_log.dart';

class GitlabConfig {
  final String url;
  final String username;
  final String password;
  final String? token;

  const GitlabConfig({
    required this.url,
    required this.username,
    required this.password,
    this.token,
  });

  factory GitlabConfig.fromJson(Map<String, dynamic> json) => GitlabConfig(
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    token: json['token'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
    'token': token,
  };
}

/// 仓库中的单个文件条目（Repository Tree API 单条记录）。
class RepoFile {
  final String name;
  final String path;
  final String type;

  const RepoFile({required this.name, required this.path, required this.type});
}

class GitLabClient {
  final GitlabConfig config;
  final http.Client _client;
  String? _token;

  GitLabClient(this.config)
    : _client = IOClient(
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true,
      );

  String hostUrl() {
    var u = config.url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final schemeIdx = u.indexOf('://');
    if (schemeIdx != -1) {
      final afterScheme = u.substring(schemeIdx + 3);
      final slashIdx = afterScheme.indexOf('/');
      if (slashIdx != -1) {
        return u.substring(0, schemeIdx + 3 + slashIdx);
      }
    }
    return u;
  }

  /// 取得访问令牌。
  ///
  /// 配了 Personal Access Token 就直接用它，绝不进入下面的 session 端点循环——
  /// 「配了 PAT 还去打 session」既是隐性性能损耗，也让认证路径分叉难以归因。
  Future<String> login() async {
    if (config.token != null && config.token!.trim().isNotEmpty) {
      _token = config.token!.trim();
      return _token!;
    }

    final endpoints = [
      '${hostUrl()}/api/v4/session',
      '${hostUrl()}/api/v3/session',
    ];

    for (final ep in endpoints) {
      try {
        final resp = await _client.post(
          Uri.parse(ep),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'login': config.username,
            'password': config.password,
          }),
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final pt = data['private_token'] as String?;
          if (pt != null) {
            _token = pt;
            return _token!;
          }
        }
      } catch (_) {}
    }

    throw Exception(
      'GitLab 登录失败: Session API 不可用或凭据有误，请配置 Personal Access Token',
    );
  }

  Future<void> ensureToken() async {
    if (_token == null || _token!.isEmpty) {
      await login();
    }
  }

  /// 仅供测试：观测当前令牌，用于断言「配了 PAT 就不会去打 session API」。
  @visibleForTesting
  String? get debugToken => _token;

  Map<String, String> _headers() => {
    'PRIVATE-TOKEN': _token ?? '',
    'Content-Type': 'application/json',
  };

  /// 请求头的可观测形态：Key 打全、敏感值只打前 6 位与长度。
  /// 用于比对「同一 PAT 在 curl 与 app 中是否发出等价请求」——
  /// tree 列举退化为根目录的那次故障，怀疑过认证差异但无法证实。
  Map<String, String> _debugHeaders() => {
    for (final e in _headers().entries)
      e.key: e.key == 'PRIVATE-TOKEN'
          ? '${e.value.substring(0, e.value.length < 6 ? e.value.length : 6)}…'
                '(len=${e.value.length})'
          : e.value,
  };

  /// 记录一行 GitLab 请求日志到 [OpsGitLabLog]。
  ///
  /// 不用 `debugPrint` + `kDebugMode`：tree 列举曾出现「curl 同一 URL 得 100 条、
  /// app 得 4 条」的无法解释差异，需要 app 自己说出实情；而 `kDebugMode` 是编译期
  /// 常量，release 包里这些日志根本不存在——等于在最需要它们的场合失效。写文件
  /// 则不依赖构建模式，也不依赖 app 由谁启动（Dock / Finder / 命令行 stderr
  /// 各有去向，文件始终在同一个位置）。
  void _log(String message) => OpsGitLabLog.instance.write(message);

  Future<http.Response> apiGet(String path) async {
    await ensureToken();
    final base = hostUrl();
    final v4Uri = Uri.parse('$base/api/v4$path');
    final resp = await _client.get(v4Uri, headers: _headers());
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp;
    }

    if (resp.statusCode == 404 || resp.statusCode == 410) {
      final v3Uri = Uri.parse('$base/api/v3$path');
      final v3Resp = await _client.get(v3Uri, headers: _headers());
      if (v3Resp.statusCode >= 200 && v3Resp.statusCode < 300) {
        return v3Resp;
      }
      throw Exception(
        'GitLab API 失败 (v4: ${resp.statusCode}, v3: ${v3Resp.statusCode})',
      );
    }

    throw Exception('GitLab API GET 失败 (${resp.statusCode}): ${resp.body}');
  }

  Future<http.Response> apiPost(String path, Map<String, dynamic> body) async {
    await ensureToken();
    final base = hostUrl();
    final v4Uri = Uri.parse('$base/api/v4$path');
    final resp = await _client.post(
      v4Uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp;
    }

    if (resp.statusCode == 404 || resp.statusCode == 410) {
      final v3Uri = Uri.parse('$base/api/v3$path');
      final v3Resp = await _client.post(
        v3Uri,
        headers: _headers(),
        body: jsonEncode(body),
      );
      if (v3Resp.statusCode >= 200 && v3Resp.statusCode < 300) {
        return v3Resp;
      }
      throw Exception(
        'GitLab API 失败 (v4: ${resp.statusCode}, v3: ${v3Resp.statusCode})',
      );
    }

    throw Exception('GitLab API POST 失败 (${resp.statusCode}): ${resp.body}');
  }

  Future<http.Response> apiPut(String path, Map<String, dynamic> body) async {
    await ensureToken();
    final base = hostUrl();
    final v4Uri = Uri.parse('$base/api/v4$path');
    final resp = await _client.put(
      v4Uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp;
    }

    if (resp.statusCode == 404 || resp.statusCode == 410) {
      final v3Uri = Uri.parse('$base/api/v3$path');
      final v3Resp = await _client.put(
        v3Uri,
        headers: _headers(),
        body: jsonEncode(body),
      );
      if (v3Resp.statusCode >= 200 && v3Resp.statusCode < 300) {
        return v3Resp;
      }
      throw Exception(
        'GitLab API 失败 (v4: ${resp.statusCode}, v3: ${v3Resp.statusCode})',
      );
    }

    throw Exception('GitLab API PUT 失败 (${resp.statusCode}): ${resp.body}');
  }

  Future<void> testConnection() async {
    await login();
  }

  Future<List<ProjectInfo>> listGroupProjects(String group) async {
    await ensureToken();
    final List<ProjectInfo> allProjects = [];
    int page = 1;

    while (true) {
      final path =
          '/groups/${Uri.encodeComponent(group)}/projects?per_page=100&page=$page';
      final resp = await apiGet(path);
      final list = jsonDecode(resp.body) as List<dynamic>;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        allProjects.add(ProjectInfo.fromJson(m));
      }
      if (list.length < 100) break;
      page++;
    }

    return allProjects;
  }

  /// 按仓库路径（可含命名空间）查询项目 ID。
  Future<int> resolveProjectId(String repoPath) async {
    final path = '/projects/${Uri.encodeComponent(repoPath)}';
    final resp = await apiGet(path);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = data['id'];
    if (id == null) {
      throw Exception('无法获取项目 ID: $repoPath');
    }
    return id is int ? id : int.parse(id.toString());
  }

  /// 列出仓库文件（单目录），按 `Link: <url>; rel="next"` 响应头逐页遍历至末页。
  /// 相较原版单页 `per_page=100` 取数，此处修正了文件数超过上限时的静默截断。
  ///
  /// 非 2xx 响应、响应体非 JSON 数组、条目缺少 `name`/`path` 三种情形都会抛出
  /// 可归因异常——历史上「静默返回空列表」曾让整个配置仓的 117 个服务文件
  /// 一个都读不到时，界面只显示"刷出 1 个空 Tag"。
  Future<List<RepoFile>> listRepositoryFiles({
    required int projectId,
    String path = '',
    String ref = 'master',
    int perPage = 100,
  }) async {
    final result = <RepoFile>[];
    String? url;

    do {
      if (url == null) {
        // path 为空时不下发该参数：GitLab 对 `path=` 空值会返回仓库根目录，
        // 使上层把非目标目录的文件也当作服务条目。
        final query = Uri(
          queryParameters: {
            if (path.isNotEmpty) 'path': path,
            'ref': ref,
            'per_page': '$perPage',
          },
        ).toString();
        // `Uri(queryParameters:).toString()` 的结果已含前导 `?`——这里绝不能再补一个。
        // 曾因多拼一个 `?` 得到 `tree??path=...`：GitLab 把第二个 `?` 当参数名的一部分
        // （Link 头回写为 `?%3Fpath=`），于是 `path` 参数根本不存在，tree 列举退化为
        // 仓库根目录，117 个服务文件一个都没看见。
        url = '${hostUrl()}/api/v4/projects/$projectId/repository/tree$query';
      }

      final target = url;
      // 开发期自检：URL 里必须真的带上 path=。
      // 集合字面量中的条件条目（`if (path.isNotEmpty) 'path': path`）一旦在
      // 某次重构中改变求值时机，这里会立刻说出来——tree 列举曾因 path 静默
      // 丢失而退化为列举仓库根目录（100 条变 4 条），且从 UI 完全看不出来。
      // 只校验「我们构造的首屏 URL」。翻页 URL 来自 GitLab 的 Link 头
      // （形如 `?id=60&page=2&path=...`，参数顺序不由我们决定），不在此列。
      if (result.isEmpty) {
        if (path.isNotEmpty && !url.contains('?path=')) {
          _log('[自检失败] path 非空("$path")但 URL 未含 ?path= 段: $url');
        }
        if (url.contains('??')) {
          _log('[自检失败] URL 含两个问号（path 会变成 ?path 参数名）: $url');
        }
      }
      final resp = await _getWithFallback(target);
      final link = resp.headers['link'];
      _log('tree $target');
      _log('    → ${resp.statusCode}, headers: ${_debugHeaders()}');
      if (link != null && link.isNotEmpty) {
        _log('    link: ${link.length > 200 ? '${link.substring(0, 200)}…' : link}');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(resp.body);
      } catch (e) {
        throw Exception(
          'GitLab 目录列举响应不是合法 JSON (${resp.statusCode}): '
          '${resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body} ($e)',
        );
      }
      if (decoded is! List) {
        throw Exception(
          'GitLab 目录列举返回的不是数组 (${resp.statusCode}): '
          '${resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body}',
        );
      }

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          throw Exception('GitLab 目录列举条目不是对象: $item');
        }
        final name = item['name'] as String?;
        final itemPath = item['path'] as String?;
        if (name == null ||
            name.isEmpty ||
            itemPath == null ||
            itemPath.isEmpty) {
          throw Exception('GitLab 目录列举条目缺少 name/path: $item');
        }
        result.add(
          RepoFile(
            name: name,
            path: itemPath,
            type: item['type'] as String? ?? 'blob',
          ),
        );
      }
      // 本页不足一页即末页；否则按 Link 头找 next。两条件都判，避免把
      // 「不满页」当作唯一终止信号（GitLab 某版本会对空目录返回带 link 的响应）。
      final bool hasNext = decoded.length >= perPage;
      final String? nextUrl = hasNext
          ? linkNextUrl(resp.headers['link'])
          : null;
      _log(
        '    tree 本页 ${decoded.length} 条，'
        '${nextUrl == null ? '末页' : '有下一页'}，累计 ${result.length} 条',
      );
      if (nextUrl == null) return result;
      url = nextUrl;
    } while (true);
  }

  /// 从 `Link` 响应头中解析 `rel="next"` 的下一页 URL，不存在时返回 null。
  static String? linkNextUrl(String? header) {
    if (header == null || header.isEmpty) return null;
    for (final part in header.split(',')) {
      if (!part.toLowerCase().contains('rel="next"')) continue;
      final match = RegExp(r'<([^>]+)>').firstMatch(part);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// 直接 GET 指定 URL 并做 v4 → v3 回退（用于分页翻页时替换 URL 中的版本段）。
  Future<http.Response> _getWithFallback(String url) async {
    await ensureToken();
    final resp = await _client.get(Uri.parse(url), headers: _headers());
    if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;

    if (resp.statusCode == 404 || resp.statusCode == 410) {
      final v3 = url.replaceFirst('/api/v4', '/api/v3');
      _log('[回退] v4 返回 ${resp.statusCode}，改打 v3: $v3');
      final v3Resp = await _client.get(Uri.parse(v3), headers: _headers());
      if (v3Resp.statusCode >= 200 && v3Resp.statusCode < 300) return v3Resp;
      throw Exception(
        'GitLab API 失败 (v4: ${resp.statusCode}, v3: ${v3Resp.statusCode})',
      );
    }

    throw Exception('GitLab API GET 失败 (${resp.statusCode}): ${resp.body}');
  }

  Future<void> createBranch(
    int projectId,
    String branch,
    String refBranch,
  ) async {
    final path = '/projects/$projectId/repository/branches';
    await apiPost(path, {'branch': branch, 'ref': refBranch});
  }

  Future<String> readFile(
    int projectId,
    String filePath,
    String refBranch,
  ) async {
    final encodedPath = Uri.encodeComponent(filePath);
    final encodedRef = Uri.encodeComponent(refBranch);
    final path =
        '/projects/$projectId/repository/files/$encodedPath/raw?ref=$encodedRef';
    final resp = await apiGet(path);
    return resp.body;
  }

  Future<void> updateFile(
    int projectId,
    String filePath,
    String content,
    String branch,
    String commitMessage,
  ) async {
    final encodedPath = Uri.encodeComponent(filePath);
    final path = '/projects/$projectId/repository/files/$encodedPath';
    await apiPut(path, {
      'branch': branch,
      'content': content,
      'commit_message': commitMessage,
    });
  }

  Future<void> updatePomVersion(
    int projectId,
    String parentVersion,
    String childVersion,
    String branch,
  ) async {
    final content = await readFile(projectId, 'pom.xml', branch);
    final newContent = updatePomVersions(content, parentVersion, childVersion);
    final commitMsg =
        'chore: update version to parent=$parentVersion, child=$childVersion';
    await updateFile(projectId, 'pom.xml', newContent, branch, commitMsg);
  }

  static String updatePomVersions(
    String content,
    String parentVersion,
    String childVersion,
  ) {
    final lines = content.split('\n');
    final result = <String>[];
    bool inParentBlock = false;
    bool parentDone = false;
    bool childDone = false;
    int depth = 0;
    bool reachedProject = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('<project')) {
        reachedProject = true;
        depth = 1;
        result.add(line);
        continue;
      }

      if (!reachedProject) {
        result.add(line);
        continue;
      }

      if (trimmed.startsWith('</project>')) {
        result.add(line);
        continue;
      }

      if (trimmed.startsWith('<parent>') || trimmed.startsWith('<parent ')) {
        inParentBlock = true;
      }

      if (trimmed.startsWith('<version>') && trimmed.contains('</version>')) {
        if (inParentBlock && !parentDone && parentVersion.isNotEmpty) {
          final indent = line.substring(0, line.indexOf('<version>'));
          result.add('$indent<version>$parentVersion</version>');
          parentDone = true;
        } else if (!inParentBlock &&
            !childDone &&
            depth == 1 &&
            childVersion.isNotEmpty) {
          final indent = line.substring(0, line.indexOf('<version>'));
          result.add('$indent<version>$childVersion</version>');
          childDone = true;
        } else {
          result.add(line);
        }
      } else {
        result.add(line);
      }

      if (trimmed.startsWith('</parent>')) {
        inParentBlock = false;
      }

      // Track depth changes
      final opens = RegExp(
        r'<[a-zA-Z][a-zA-Z0-9_-]*(\s+[^>]*)?>',
      ).allMatches(trimmed);
      final closes = RegExp(r'</[a-zA-Z][a-zA-Z0-9_-]*>').allMatches(trimmed);
      final selfCloses = RegExp(
        r'<[a-zA-Z][a-zA-Z0-9_-]*(\s+[^>]*)?/>',
      ).allMatches(trimmed);

      final openCount = opens.length - selfCloses.length;
      final closeCount = closes.length;
      depth += (openCount - closeCount);
    }

    return result.join('\n');
  }
}
