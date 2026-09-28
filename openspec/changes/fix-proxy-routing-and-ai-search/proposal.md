## Why

在开启应用内嵌网络代理后，用户在使用“AI资讯与检索”或涉及 AI 调用的功能时，面临两项严重阻碍：
1. **国内直连 AI 供应商误走代理导致不可用**：用户的私有或国内中转 API（如腾讯云 NewAPI 等中国大陆公网/局域网节点）在开启系统代理后，被底层 `HttpClient` 的全局 `PROXY` 规则强制转发至海外代理节点，引发节点回国连接被拒、网络重置或 `HTTP 502 Bad Gateway`；且 `AiService` 在代理开关切换后未重建客户端与清空健康状态冷却，导致临时错误长期驻留。
2. **AI 资讯助手过度绑定 MCP 工具导致无兜底检索能力**：当 MCP 外部服务（Firecrawl）未启动、崩溃或用户要求直接搜索时，AI 助手内部未集成既有的 `WebSearchService`（零配置免密钥 Bing 解析与网页抓取后端链），只能向用户返回“在当前环境下，我无法脱离 MCP 工具直接访问 Google”。

## What Changes

- **代理智能分流与白名单直连 (Bypass/No-Proxy)**：在 `ProxySettings.findProxyFor` 中实现智能地址判别。除原有私网网段（`localhost`、`127.0.0.1`、`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）直连（`DIRECT`）外，支持用户可配置直连白名单以及国内 IP / 域名智能绕过规则，避免国内模型服务器反向走海外代理出现 502。
- **动态代理通道响应机制**：`AiService` 与网络客户端模块主动监听 `ProxySettings.instance` 的配置变更事件，在代理开启/关闭或参数调整时，立即触发 `rebuildHttpClient()` 并清除旧的健康状态缓存（`_healthCache`）与端点缓存（`_resolvedChatEndpoint`），使网络通道切换即刻生效，无需重启应用。
- **AI 资讯助手多级检索与抓取工具整合**：在 `AiAssistantService` 中重构 ReAct 工具体系。将平台统一的 `WebSearchService`（包含 Bing HTML 零配置解析、SearXNG 多实例检索以及通用网页正文抓取能力）作为通用内置工具注入到 `AiAssistantService` 的 Agent 工具箱中（提供 `web_search` 和 `web_scrape`），与用户自定义的 MCP 外部工具（如 Firecrawl）形成“免配置内置兜底 + MCP高级工具扩展”的双轨互补。
- **Prompt 智能引导与脱离 MCP 自主检索能力**：更新系统提示词（System Prompt），当 MCP 不可用或用户指定不使用 MCP 时，助手能够自主无缝调用内置的 `web_search` / `web_scrape` 获取实时全网信息（可受 AI 助手的代理通道开关控制，通过代理直接访问 Google/Bing/外网公开资讯）。

## Capabilities

### Modified Capabilities
- `ai-news-assistant`: 扩充 AI 资讯助手的工具生态，在既有 MCP 工具的基础上无缝接入内置的免配置联网检索与网页抓取工具链（`web_search` / `web_scrape`），当 MCP 故障或用户显式要求免 MCP 时依然具备全网信息检索能力；支持在受控网络代理下检索外网与全球动态。
- `ai-routing`: 提升 AI 请求对代理状态切换与分流路由的健壮性。当全局或局部代理通道变更时自动重置客户端连接池与候选供应商健康冷却期；对直连/局域网/国内私有 API 执行绕过判定，避免海外代理转发导致 502。

## Impact

- 涉及文件：
  - `lib/services/proxy_settings.dart`: 增强 `findProxyFor(Uri? uri)`，支持 `NO_PROXY` 模式匹配与白名单分流。
  - `lib/services/ai_service.dart`: 注册 `ProxySettings` 监听，代理切换时调用 `rebuildHttpClient()` 并清理 `_healthCache`。
  - `lib/tools/ai_assistant/services/ai_assistant_service.dart`: 集成 `WebSearchService` 内置工具到 Agent 循环中，更新 ReAct System Prompt。
  - `openspec/specs/ai-news-assistant/spec.md`: 新增内置联网检索工具与降级规范。
  - `openspec/specs/ai-routing/spec.md`: 新增代理通道切换自适应与直连分流规范。
