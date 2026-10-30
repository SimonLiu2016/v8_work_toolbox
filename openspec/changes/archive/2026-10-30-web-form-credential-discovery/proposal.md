## Why

对于自主研发的 Web 系统（如 `sct.v8en.com`），现有工具链无法发现最基础的弱口令问题：Nuclei 的默认凭据模板仅覆盖已知开源组件，而对自定义登录界面束手无策。要实现真正的主动漏洞挖掘，必须具备通用 Web 表单弱口令探测能力——自动找到登录入口、解析表单结构、用常见弱密码组合探测，并智能判断是否登录成功。

## What Changes

- **新增 `WebFormCredentialService`**：通用 Web 表单弱口令探测引擎，覆盖以下流程：
  1. **登录页发现**：从 Katana/ffuf 爬取结果中自动识别含 `login/signin/admin/auth/user` 关键词的 URL，补充 ffuf 字典扫描（`login.php`, `/admin`, `/wp-login.php` 等）
  2. **表单解析**：向候选 URL 发 HTTP GET，解析 HTML `<form>` 找到 username / email 字段与 password 字段；支持识别 CSRF token 字段并在 POST 时携带
  3. **弱口令喷洒**：内置安全基线弱口令字典（Top 50 组合：`admin/admin`, `admin/123456`, `root/root`, `test/test`, `guest/guest` 等），以合理时间间隔依次 POST
  4. **成功判定**：对比响应状态码（302 跳转）、响应长度变化、页面关键词（`退出登录/logout/dashboard/欢迎`）综合判定登录是否成功
  5. **发现物入库**：发现弱口令时以 `critical` 严重度写入 findings，记录命中的账号密码对、登录 URL
- **注册 `check_web_credential` Agent 工具**：AI 研判层可主动调度此工具，在发现 Web 登录界面时自动核查弱口令
- **集成进全量评估流水线**：`AdaptiveAgentPipeline` 的 Web 基础阶段在 Katana 完成后自动触发一次弱口令探测
- **速率限制与安全基线约束**：每个目标最多发送 100 次请求，单次请求间隔 ≥ 500ms，防止对目标造成拒绝服务

## Capabilities

### New Capabilities

- `security/web-form-credential-discovery`：通用 Web 登录表单弱口令探测能力，含登录页自动识别、表单结构解析、弱口令喷洒、智能成功判定、CSRF token 支持

### Modified Capabilities

- `security/adaptive-agent-pipeline`：全量评估 Web 流水线在 Katana 阶段后自动触发 `WebFormCredentialService`

## Impact

- 新增 `lib/tools/security_toolbox/services/web_credential_service.dart`：完整的弱口令探测引擎
- `lib/tools/security_toolbox/services/security_agent_executor.dart`：注册 `check_web_credential` 工具
- `lib/tools/security_toolbox/services/security_agent_service.dart`：AgentTools 列表新增 `check_web_credential` 工具定义
- `lib/tools/security_toolbox/services/security_pipeline_service.dart`：Web 流水线 Katana 后新增弱口令探测阶段
- 无新增第三方依赖（使用 Dart 原生 `http` 包，已在项目中）
