## Context

自主开发的 Web 系统没有与已知开源框架对应的 Nuclei 模板，无法通过模板扫描发现弱口令。需要通用的 Web 表单弱口令探测能力：HTTP 客户端 + HTML 解析 + 智能成功判断。项目中已有 `package:http` 依赖（`exploit_services.dart` 中已 `import 'package:http/http.dart' as http`），且 `package:html` 可用于 HTML 解析（需确认 pubspec.yaml）。

## Approach

### 核心引擎：`WebFormCredentialService`

新建 `lib/tools/security_toolbox/services/web_credential_service.dart`。

**登录页识别**：

```
输入：List<String> crawledUrls（来自 Katana 爬取结果 + ffuf 扫描结果）

过滤规则（满足其一即纳入候选）：
  1. URL 路径中包含关键词：login, signin, admin, auth, user, account, portal
  2. 向 URL 发 GET，响应 HTML 中含 <input type="password">
```

**表单结构解析**（对每个候选 URL）：

```
GET 请求 → 解析响应 HTML
查找 <form> 元素 → 从中提取：
  - username_field: name 含 user/email/account/login/name 的 text/email input
  - password_field: type="password" 的 input
  - csrf_field: type="hidden" 的 input（名称含 token/csrf/_token）
  - action_url: form 的 action 属性（相对路径转绝对）
  - method: form 的 method（默认 POST）
```

若找不到 password_field，跳过该候选页面。

**HTML 解析策略**：使用简单正则（不引入新依赖）：
```
RegExp(r'<input[^>]+type=["\']password["\'][^>]*>') → 确认是登录页
RegExp(r'<input[^>]+name=["\']([^"\']+)["\'][^>]*>') → 提取字段名
RegExp(r'<form[^>]+action=["\']([^"\']+)["\']') → 提取 action
```

**弱口令字典**（内置常量，共 40 对组合）：

```dart
static const List<(String, String)> _weakCredentials = [
  ('admin', 'admin'),
  ('admin', '123456'),
  ('admin', 'admin123'),
  ('admin', 'password'),
  ('root', 'root'),
  ('root', '123456'),
  ('test', 'test'),
  ('user', 'user'),
  ('guest', 'guest'),
  ('admin', ''),
  // ... 共 40 条
];
```

**POST 喷洒逻辑**：

```
for each (username, password) in _weakCredentials:
  若已达 150 次请求上限 → break
  若已发现成功 → break（避免重复记录）

  // 每次重新 GET 获取最新 CSRF token
  若 csrf_field 存在：GET 登录页 → 提取当前 token 值

  POST to action_url:
    body: {username_field: username, password_field: password, csrf_field: token}
    headers: {Cookie: ..., Referer: login_url}

  await Future.delayed(500ms)  // 速率限制

  判定成功：
    response.statusCode == 302 → success
    OR response.body.contains('dashboard' | '退出' | 'logout' | '欢迎') → success
    AND response.body NOT contains('密码错误' | '账号不存在' | 'invalid' | 'incorrect')
```

**成功判定补充**：维护第一次（空账号 GET）的响应长度为基准，若 POST 后响应长度差值 > 500 字符且没有错误关键词，也认定为可疑成功（以 medium 而非 critical 写入）。

### 流水线集成（Web 流水线）

在 `security_pipeline_service.dart` 的 `runWebPipeline` Katana 阶段之后（sqlmap 阶段之前）新增：

```dart
// 阶段 3.5: Web 表单弱口令探测
final crawledUrls = controller.assetList
    .expand((a) => (a.metadata['crawled_urls'] as List? ?? []).cast<String>())
    .toList();
await WebFormCredentialService.scan(
  candidateUrls: crawledUrls,
  baseUrl: 'https://$domain',
  onLog: controller.log,
  onFinding: (f) async {
    await controller.findings.add(
      sessionId: session.id,
      title: 'Web 表单弱口令: ${f.loginUrl}',
      severity: Severity.critical.key,
      evidence: 'username=${f.username} password=${f.password}',
      source: FindingSource.manual,
    );
  },
);
```

### Agent 工具注册

在 `SecurityAgentService.SecurityAgentTools.all` 新增：
```dart
AgentTool(
  name: 'check_web_credential',
  description: 'Web 登录表单弱口令基线核查（自动解析表单结构，探测常见弱密码组合）',
  inputSchema: {
    'type': 'object',
    'properties': {
      'login_url': {'type': 'string', 'description': '登录页 URL'},
    },
    'required': ['login_url'],
  },
),
```

在 `SecurityAgentExecutor` 新增 `case 'check_web_credential'` 分支，调用 `WebFormCredentialService`。

## Risks

- **CSRF 防护**：每次 POST 前重新 GET 获取 token，覆盖大多数简单 CSRF 实现；复杂的二次验证（图形验证码、短信验证码）无法绕过，此时工具自动跳过该表单
- **JSON API 登录接口**：部分现代框架的登录是 JSON API 而非 HTML 表单（`Content-Type: application/json`）。当前实现针对 HTML 表单，JSON API 暂不覆盖（纳入后续迭代）
- **同源策略/重定向**：使用 `http` 包的 `followRedirects: false` 捕获 302 跳转，避免跟随跳转后丢失判断时机
- **误判率控制**：使用多特征综合判定（状态码 + 关键词 + 响应长度），并要求"无错误关键词"作为必要条件，降低误判率
