/// 通用 Web 表单弱口令自动化探测服务。
///
/// 具备登录页面识别、表单结构提取（含 CSRF 字段）、
/// 内置常见弱口令基线喷洒以及多维度成功状态判定。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// Web 表单弱口令发现物。
class WebFormFinding {
  final String loginUrl;
  final String actionUrl;
  final String username;
  final String password;

  /// 可信度：'confirmed'（302 跳转或明确成功标志）或 'suspicious'（响应特征异常变化）
  final String confidence;

  const WebFormFinding({
    required this.loginUrl,
    required this.actionUrl,
    required this.username,
    required this.password,
    this.confidence = 'confirmed',
  });

  @override
  String toString() =>
      '$loginUrl -> $username : $password ($confidence)';
}

/// 解析出的表单结构。
class FormStructure {
  final String actionUrl;
  final String method;
  final String usernameField;
  final String passwordField;
  final String? csrfField;
  final String? csrfToken;

  const FormStructure({
    required this.actionUrl,
    required this.method,
    required this.usernameField,
    required this.passwordField,
    this.csrfField,
    this.csrfToken,
  });
}

/// Web 登录表单弱口令基线核查服务。
abstract final class WebFormCredentialService {
  /// 内置常见弱口令基线账户密码组合（40 对）。
  static const List<(String, String)> defaultCredentials = [
    ('admin', 'admin'),
    ('admin', '123456'),
    ('admin', 'admin123'),
    ('admin', 'password'),
    ('admin', 'admin888'),
    ('admin', 'admin@123'),
    ('admin', '12345678'),
    ('admin', 'root'),
    ('root', 'root'),
    ('root', '123456'),
    ('root', 'root123'),
    ('root', 'toor'),
    ('test', 'test'),
    ('test', '123456'),
    ('test', 'test123'),
    ('user', 'user'),
    ('user', '123456'),
    ('guest', 'guest'),
    ('guest', '123456'),
    ('administrator', 'administrator'),
    ('administrator', '123456'),
    ('administrator', 'admin'),
    ('manager', 'manager'),
    ('manager', '123456'),
    ('super', 'super'),
    ('superadmin', 'superadmin'),
    ('system', 'system'),
    ('demo', 'demo'),
    ('service', 'service'),
    ('webmaster', 'webmaster'),
    ('operator', 'operator'),
    ('support', 'support'),
    ('audit', 'audit'),
    ('app', 'app'),
    ('admin', '111111'),
    ('admin', '123123'),
    ('admin', 'password123'),
    ('admin', 'qwerty'),
    ('admin', '1234'),
    ('admin', '888888'),
  ];

  /// 常见登录页面 URL 关键词。
  static const List<String> loginKeywords = [
    'login',
    'signin',
    'admin',
    'auth',
    'portal',
    'manage',
    'console',
    'user/login',
    'account/login',
  ];

  /// 登录失败常见关键词（用于过滤误报）。
  static const List<String> errorKeywords = [
    '密码错误',
    '账号不存在',
    '用户名错误',
    '用户不存在',
    '密码不正确',
    '认证失败',
    '账号或密码',
    'invalid',
    'incorrect',
    'failed',
    'bad credential',
    'wrong password',
    'error',
    'captcha',
    '验证码',
  ];

  /// 登录成功常见标志关键词。
  static const List<String> successKeywords = [
    'dashboard',
    '控制台',
    '管理中心',
    '退出登录',
    '注销',
    'logout',
    '欢迎',
    'welcome',
    '个人中心',
    'auth_token',
    'access_token',
    '"code":0',
    '"code":200',
  ];

  /// 判断 URL 是否可能为登录入口。
  static bool isCandidateLoginUrl(String url) {
    final lower = url.toLowerCase();
    for (final kw in loginKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  /// 从 HTML 源码解析登录表单。
  static FormStructure? parseLoginForm(String html, String pageUrl) {
    if (!html.contains('type="password"') && !html.contains("type='password'")) {
      return null;
    }

    // 寻找包含 password 的 <form>，若没有匹配到独立 form 标签则全页面匹配
    final formRegex = RegExp(r'<form\b[^>]*>(.*?)</form>', caseSensitive: false, dotAll: true);
    final forms = formRegex.allMatches(html).toList();

    String formHtml = html;
    String actionAttr = '';
    String methodAttr = 'POST';

    for (final m in forms) {
      final content = m.group(1) ?? '';
      if (content.contains('type="password"') || content.contains("type='password'")) {
        formHtml = m.group(0)!;
        final formTag = RegExp(r'<form\b([^>]*)>', caseSensitive: false).firstMatch(formHtml)?.group(1) ?? '';
        final actionMatch = RegExp(r'''action=["']([^"']*)["']''', caseSensitive: false).firstMatch(formTag);
        if (actionMatch != null) actionAttr = actionMatch.group(1) ?? '';
        final methodMatch = RegExp(r'''method=["']([^"']*)["']''', caseSensitive: false).firstMatch(formTag);
        if (methodMatch != null) methodAttr = methodMatch.group(1)?.toUpperCase() ?? 'POST';
        break;
      }
    }

    // 提取 password 字段名
    final passRegex = RegExp(
      r'''<input\b[^>]*\btype=["']password["'][^>]*\bname=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final passMatch = passRegex.firstMatch(formHtml) ??
        RegExp(r'''<input\b[^>]*\bname=["']([^"']+)["'][^>]*\btype=["']password["']''', caseSensitive: false)
            .firstMatch(formHtml);
    if (passMatch == null) return null;
    final passwordField = passMatch.group(1)!;

    // 提取 username 字段名（text/email 或 name 含有 user/account/login/name）
    String usernameField = 'username';
    final allInputs = RegExp(r'''<input\b[^>]*\bname=["']([^"']+)["'][^>]*>''', caseSensitive: false)
        .allMatches(formHtml);
    for (final inputMatch in allInputs) {
      final name = inputMatch.group(1)!;
      final fullTag = inputMatch.group(0)!.toLowerCase();
      if (name == passwordField) continue;
      if (fullTag.contains('hidden') || fullTag.contains('submit') || fullTag.contains('button')) continue;
      final nLower = name.toLowerCase();
      if (nLower.contains('user') ||
          nLower.contains('account') ||
          nLower.contains('login') ||
          nLower.contains('name') ||
          nLower.contains('email') ||
          nLower.contains('mail') ||
          nLower.contains('phone')) {
        usernameField = name;
        break;
      }
    }

    // 提取 CSRF 隐藏字段（如 _token, csrf_token, authenticity_token）
    String? csrfField;
    String? csrfToken;
    final hiddenMatches = RegExp(
      r'''<input\b[^>]*\btype=["']hidden["'][^>]*>''',
      caseSensitive: false,
    ).allMatches(formHtml);
    for (final h in hiddenMatches) {
      final tag = h.group(0)!;
      final nameMatch = RegExp(r'''name=["']([^"']+)["']''', caseSensitive: false).firstMatch(tag);
      final valueMatch = RegExp(r'''value=["']([^"']*)["']''', caseSensitive: false).firstMatch(tag);
      if (nameMatch != null) {
        final n = nameMatch.group(1)!;
        final nLower = n.toLowerCase();
        if (nLower.contains('csrf') ||
            nLower.contains('token') ||
            nLower.contains('xsrf') ||
            nLower == '_token') {
          csrfField = n;
          csrfToken = valueMatch?.group(1) ?? '';
          break;
        }
      }
    }

    // 组合完整的 action URL
    String resolvedAction = pageUrl;
    if (actionAttr.isNotEmpty) {
      final baseUri = Uri.tryParse(pageUrl);
      if (baseUri != null) {
        resolvedAction = baseUri.resolve(actionAttr).toString();
      }
    }

    return FormStructure(
      actionUrl: resolvedAction,
      method: methodAttr,
      usernameField: usernameField,
      passwordField: passwordField,
      csrfField: csrfField,
      csrfToken: csrfToken,
    );
  }

  /// 判定登录响应是否成功。
  static String? evaluateSuccess({
    required int statusCode,
    required String body,
    required Map<String, String> headers,
    required String originalUrl,
    int? baselineLength,
  }) {
    // 判定 1: 30x 跳转到其他页面（且不是重新跳回登录页）
    if (statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307) {
      final loc = headers['location'] ?? headers['Location'] ?? '';
      final locLower = loc.toLowerCase();
      if (loc.isNotEmpty && !locLower.contains('login') && !locLower.contains('signin') && !locLower.contains('error')) {
        return 'confirmed';
      }
    }

    final bodyLower = body.toLowerCase();

    // 必须没有明确报错词汇
    for (final err in errorKeywords) {
      if (bodyLower.contains(err.toLowerCase())) {
        return null;
      }
    }

    // 判定 2: 响应体命中明确成功词
    for (final s in successKeywords) {
      if (bodyLower.contains(s.toLowerCase())) {
        return 'confirmed';
      }
    }

    // 判定 3: 状态码 200 且响应长度出现较大差异且无报错
    if (statusCode == 200 && baselineLength != null && (body.length - baselineLength).abs() > 300) {
      return 'suspicious';
    }

    return null;
  }

  /// 对指定的一组候选 URL 执行弱口令探测。
  static Future<List<WebFormFinding>> scan({
    required List<String> candidateUrls,
    String? baseUrl,
    List<(String, String)>? credentials,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
    int maxRequestsPerUrl = 30,
    void Function(WebFormFinding finding)? onFinding,
    void Function(String log)? onLog,
  }) async {
    final client = httpClient ?? http.Client();
    final findings = <WebFormFinding>[];

    // 去重并提取候选列表
    final targets = <String>{};
    for (final u in candidateUrls) {
      if (isCandidateLoginUrl(u)) targets.add(u);
    }
    if (baseUrl != null && baseUrl.isNotEmpty) {
      targets.add(baseUrl);
    }

    if (targets.isEmpty) {
      onLog?.call('未发现明显的登录入口页面，跳过 Web 表单弱口令核查');
      if (httpClient == null) client.close();
      return [];
    }

    final creds = credentials ?? defaultCredentials;
    onLog?.call('正在核查 ${targets.length} 个候选 Web 登录页面的弱口令基线…');

    try {
      for (final url in targets.take(5)) { // 限制最多扫描 5 个登录页
        onLog?.call('探测登录页面表单: $url');
        http.Response getRes;
        try {
          getRes = await client.get(
            Uri.parse(url),
            headers: {'User-Agent': 'Mozilla/5.0 (V8WorkToolbox Security Scanner)'},
          ).timeout(timeout);
        } catch (e) {
          onLog?.call('访问 $url 失败: $e');
          continue;
        }

        final form = parseLoginForm(getRes.body, url);
        if (form == null) {
          onLog?.call('$url 未发现密码输入表单，跳过');
          continue;
        }

        onLog?.call(
          '识别到登录表单 [action: ${form.actionUrl}, user: ${form.usernameField}, pass: ${form.passwordField}]',
        );

        final baselineLength = getRes.body.length;
        var requestCount = 0;

        for (final (user, pass) in creds) {
          if (requestCount >= maxRequestsPerUrl) break;
          requestCount++;

          // 保持每次请求间适度延迟（500ms），避免高频打挂业务系统
          await Future.delayed(const Duration(milliseconds: 500));

          try {
            final postData = <String, String>{
              form.usernameField: user,
              form.passwordField: pass,
              if (form.csrfField != null && form.csrfToken != null)
                form.csrfField!: form.csrfToken!,
            };

            final postRes = await client.post(
              Uri.parse(form.actionUrl),
              headers: {
                'User-Agent': 'Mozilla/5.0 (V8WorkToolbox Security Scanner)',
                'Content-Type': 'application/x-www-form-urlencoded',
                'Referer': url,
              },
              body: postData,
            ).timeout(timeout);

            final confidence = evaluateSuccess(
              statusCode: postRes.statusCode,
              body: postRes.body,
              headers: postRes.headers,
              originalUrl: url,
              baselineLength: baselineLength,
            );

            if (confidence != null) {
              final finding = WebFormFinding(
                loginUrl: url,
                actionUrl: form.actionUrl,
                username: user,
                password: pass,
                confidence: confidence,
              );
              findings.add(finding);
              onFinding?.call(finding);
              onLog?.call('🚨 检出 Web 弱口令: $url -> $user : $pass (置信度: $confidence)');
              // 找到一个有效账号后退出该表单的继续尝试
              break;
            }
          } catch (_) {
            // 单个请求失败忽略并继续
          }
        }
      }
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }

    return findings;
  }
}
