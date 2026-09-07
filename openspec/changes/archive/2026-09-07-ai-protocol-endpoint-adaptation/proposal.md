## Why

当前 AI 协议客户端实现存在路径拼接死板与鉴权头单一的硬编码缺陷：
1. **Anthropic 协议路径方言**：硬编码假定端点为 `$baseUrl/v1/messages`，而国内及主流云厂商大模型网关（如小米 MiMo、OneAPI、NewAPI、Cloudflare 等）通常挂载在 `/anthropic/v1/messages`；同时鉴权头部分网关使用 `api-key` 而非标准 `x-api-key`。这导致配置了 Anthropic 协议的供应商在探测模型时成功，但在实际对话时触发 404 错误。
2. **OpenAI 协议路径缺乏容错**：未对用户输入的 Base URL 进行 `/v1` 智能补齐，若用户输入不带 `/v1` 的域名，会导致模型探测与补全直接报 404。
3. **“测试连接”与真实对话脱节**：当前的连接测试仅检查 `GET /models`，无法验证实际对话端点（`POST /messages` 或 `POST /chat/completions`）与鉴权头的有效性。

本变更旨在提升 AI 基础设施层对多协议供应商与第三方反向代理网关的**自适应兼容能力**，让用户只需选择协议与输入基础域名，底层自动抹平路径与 Header 差异，开箱即用。

## What Changes

- **Anthropic 协议自适应端点探测与降级**：
  - 运行时支持自动探测并匹配 Anthropic 路由变体：`/anthropic/v1/messages`、`/v1/messages`、`/messages`。
  - 自动识别并缓存成功的端点子路径，避免后续重复试探。
- **双重鉴权头兼容注入**：
  - Anthropic 请求同时下发 `x-api-key` 与 `api-key` 头部，彻底解决网关因单头缺失拒绝请求的问题。
  - OpenAI 请求兼顾标准 `Authorization: Bearer` 与特定网关需要的 `api-key` 头。
- **OpenAI 协议 URL 智能规范化**：
  - 对用户填写的 Base URL 进行智能补全：当检测到路径缺少 `/v1` 且根路径探测 404 时，自动补充 `/v1` 访问 `/v1/models` 与 `/v1/chat/completions`。
- **端到端真机连通性验证（Ping 校验）**：
  - 配置页面的「测试连接」升级为两阶段验证：首先拉取模型列表，紧接着发送一次极小 token 消耗的实际对话 ping，确保用户在保存前即 100% 确认对话可用。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 增强供应商协议适配能力，支持智能 Base URL 规范化、双重鉴权头注入、Anthropic 网关路由自适应及真实对话 Ping 测试。

## Impact

- **`lib/services/ai_service.dart`**：重构 `_chatAnthropic`、`_discoverAnthropicModels`、`_chatOpenAi`、`_discoverOpenAiModels`，引入 URL 规范化与自适应路由探测重试；升级 `testConnection` 方法。
- **`lib/shell/ai_config_page.dart`**：优化「测试连接」UI 提示，展示模型探测与对话 Ping 的综合健康结果。
- **测试套件**：新增针对小米 MiMo、标准 Anthropic、无 `/v1` OpenAI 代理等网关方言的集成测试用例。
