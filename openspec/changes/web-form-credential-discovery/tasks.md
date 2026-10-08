## 1. WebFormCredentialService 核心引擎

- [x] 1.1 新建 `lib/tools/security_toolbox/services/web_credential_service.dart`，定义 `WebFormFinding` 数据类（loginUrl, username, password, confidence）和 `WebFormCredentialService` 抽象类
- [x] 1.2 实现登录页识别逻辑：遍历候选 URL 列表，过滤 URL 路径含登录关键词（login/signin/admin/auth）的条目；对剩余条目发 GET 请求，检测响应 HTML 中是否含 `<input type="password">`
- [x] 1.3 实现表单结构解析：用正则提取 `<form>` 的 action、method，username 字段名（含 user/email/account/login/name 的 input），password 字段名，CSRF hidden 字段名与初始值
- [x] 1.4 实现弱口令喷洒循环：内置 40 对常见弱密码组合，每次 POST 前若存在 CSRF 字段则重新 GET 获取最新 token，携带 Referer / Cookie 头；每次请求后 await 500ms 速率限制；达到 150 次上限强制退出
- [x] 1.5 实现多维度成功判定：302 跳转判定、响应体成功关键词判定、响应体错误关键词排除（需同时通过两个条件才判定成功）；以 `critical` 写入 finding，响应长度异常但无明确成功标志时以 `medium` 写入

## 2. Agent 工具注册

- [x] 2.1 在 `security_agent_service.dart` 的 `SecurityAgentTools.all` 列表中新增 `check_web_credential` AgentTool 定义，描述使用合规框架语言
- [x] 2.2 在 `security_agent_executor.dart` 的 switch 中新增 `case 'check_web_credential'`，从 args 中提取 `login_url`，调用 `WebFormCredentialService`，发现物写库，返回 ≤500 字符摘要

## 3. 流水线集成

- [x] 3.1 在 `security_pipeline_service.dart` `runWebPipeline` 的 Katana 阶段之后新增"Web 表单弱口令探测"阶段，从 assetList 提取 `crawled_urls`，追加 `baseUrl` 本身作为候选，调用 `WebFormCredentialService.scan()`，onFinding 写库

## 4. 测试与部署

- [x] 4.1 在 `test/security_gaps_test.dart` 新增 WebFormCredentialService 测试组：验证登录页识别逻辑（关键词过滤）、表单字段解析、成功判定逻辑（mock HTTP 响应）
- [x] 4.2 运行 `flutter analyze`，确保 No issues found
- [x] 4.3 运行 `flutter test test/security_gaps_test.dart`，全部通过
- [x] 4.4 运行 `./scripts/deploy_local.sh` 完成本地部署
