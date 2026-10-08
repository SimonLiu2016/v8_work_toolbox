## Purpose

通用 Web 登录表单弱口令探测引擎：自动发现目标网站的登录入口、解析表单结构、用内置基线弱口令字典探测，并智能判断是否成功认证，将发现物写入数据库。

## ADDED Requirements

### Requirement: 登录页自动发现
系统 SHALL 从 Katana 爬取结果和 ffuf 字典扫描结果中自动识别候选登录 URL，识别依据包括：URL 路径含 `login/signin/admin/auth/user` 关键词，或 HTTP 响应页面含登录表单标记（`<input type="password">`）。

#### Scenario: 从爬取结果识别登录页
- **WHEN** Katana 爬取到 URL `https://sct.v8en.com/user/login`，其路径含 `login`
- **THEN** 该 URL 被纳入登录页候选列表，作为后续表单解析目标

#### Scenario: 无登录页时安全跳过
- **WHEN** 爬取结果与 ffuf 字典扫描中均未发现含密码输入框的页面
- **THEN** 弱口令探测阶段跳过，不产生任何 finding，控制台记录"未发现登录入口"

### Requirement: 表单结构自动解析
系统 SHALL 向候选登录 URL 发送 GET 请求，解析响应 HTML 中的 `<form>` 元素，自动识别：用户名/邮箱输入字段、密码输入字段、CSRF token 隐藏字段、表单提交 action URL 和 method。

#### Scenario: 标准表单解析
- **WHEN** 登录页 HTML 含 `<input type="text" name="username">` 和 `<input type="password" name="password">` 及 `action="/api/login"`
- **THEN** 系统正确提取字段名 `username`、`password` 和提交端点 `/api/login`，后续 POST 使用这些字段名

#### Scenario: CSRF token 自动携带
- **WHEN** 登录表单含 `<input type="hidden" name="_token" value="abc123">`
- **THEN** 系统在每次 POST 请求中携带当前页面获取到的最新 token 值

### Requirement: 弱口令喷洒与成功判定
系统 SHALL 使用内置基线弱口令字典（≥ 30 条常见组合）依次向登录端点发送 POST 请求，并通过以下特征综合判定登录成功：HTTP 响应码为 302 跳转、响应体包含成功关键词（`dashboard/退出/logout/欢迎`）、响应 body 长度显著大于失败时。

#### Scenario: 弱口令命中 — 302 跳转判定
- **WHEN** POST `admin/admin123` 后服务器返回 `302 Location: /dashboard`
- **THEN** 系统判定登录成功，以 `critical` 严重度写入 finding，记录命中的账号密码对

#### Scenario: 弱口令命中 — 响应关键词判定
- **WHEN** POST `admin/123456` 后响应体含 `欢迎回来` 或 `退出登录`
- **THEN** 系统判定登录成功，以 `critical` 严重度写入 finding

#### Scenario: 全部失败时无误报
- **WHEN** 所有弱口令组合均返回含 `密码错误` 或 `账号不存在` 的响应且无跳转
- **THEN** 系统不产生 finding，返回"字典耗尽，未发现弱口令"

### Requirement: 执行安全速率限制
探测过程 SHALL 在每次请求之间保持 ≥ 500ms 间隔，每个目标最多发送 150 次请求，防止对目标服务造成过载。

#### Scenario: 达到请求上限自动停止
- **WHEN** 对某个登录端点的请求次数已达到 150 次上限
- **THEN** 探测自动终止，不再发送新请求，控制台记录已达上限
