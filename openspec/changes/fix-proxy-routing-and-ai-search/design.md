## Context

详见 `proposal.md`。当前应用在配置系统代理（mihomo / clash）并勾选启用后，底层统一通过 `AppHttpClient` 和 `HttpClient.findProxy` 调度网络请求。然而存在两处架构断裂：
1. `ProxySettings.findProxyFor` 缺乏白名单判别逻辑，将私有部署国内 API 亦强行指向本地代理，导致外网代理节点回程国内被阻断返回 502。同时 `AiService` 单例在生命周期中未监听 `ProxySettings`，切换后旧 Client 与冷却缓存未重置。
2. `AiAssistantService` 仅以 MCP 作为工具提供方，未复用已在 `WebSearchService` 中构建完毕的免配置 Bing/SearXNG 搜索与统一正文抓取链路。

## Goals / Non-Goals

**Goals:**
- 实现 Dart `findProxyFor` 层的智能分流与绕过机制（对私网、localhost 以及国内直连配置的 IP 走 `DIRECT`）。
- 建立 `ProxySettings` → `AiService` 的响应式绑定，开关代理即时重建 HTTP 客户端并清空供应商不可用状态。
- 为 `AiAssistantService` 注入平台级 `web_search` 与 `web_scrape` 内置工具，重构 ReAct System Prompt 形成“免配置内置兜底 + MCP高级工具扩展”双轨机制。
- 确保 `WebSearchService` 发出的搜索/抓取请求能够正确继承当前工具代理配置（开启代理后可成功检索外网）。

**Non-Goals:**
- 不重写 Clash/Mihomo 的 PAC 规则或内核路由表（分流在应用层 HttpClient 实现）。
- 不废弃已有的 MCP 协议支持，MCP 依旧作为高质量扩展能力存在。

## Decisions

### 1. 代理智能绕过实现方式
- **方案选择**：在 `ProxySettings` 中增加 `shouldBypass(Uri? uri)` 判定。
  - 自动绕过：`localhost`, `127.0.0.1`, `::1`, RFC 1918 私网 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)。
  - 用户配置绕过：支持从配置项中读取 `noProxy` 列表（逗号分隔或集合）。对于用户在 AI 配置中配置的私有直连 IP（如公网服务器 `119.29.249.154`），如果用户希望直连或配置了白名单，`findProxyFor` 返回 `'DIRECT'`。
- **替代方案考虑**：完全依赖 Clash 规则分流。缺点是如果用户使用的是全局代理模式或海外节点默认阻断中国 IP，底层请求依然会失败；在应用层提前分流最为可靠。

### 2. AiService 代理监听与缓存清理
- **方案选择**：在 `AiService` 构造函数或初始化时挂载 `ProxySettings.instance.addListener`。
  - 当检测到代理配置发生变更（`enabled` 变化或 `host`/`port` 变化）时，自动触发 `rebuildHttpClient()`，并执行 `clearHealthCache()`，使之前被标记为 502 冷却的候选供应商能够立即恢复尝试。
- **替代方案考虑**：让 UI 层手动触发重建。缺点是容易遗漏（例如多处界面或定时后台任务均可能触发代理更新）。

### 3. AI 资讯助手 ReAct 工具重构
- **方案选择**：在 `AiAssistantService._runAgentLoop` 中，将工具集定义为联合集合：
  1. `web_search`: 由 `WebSearchService.instance.search` 提供，支持 Bing (cn.bing.com) 与 SearXNG 零配置搜索。
  2. `web_scrape`: 由 `WebSearchService.instance.scrape` 提供，直接抓取 URL 的 Clean Markdown 内容。
  3. `mcpTools`: 动态从 `McpService.instance.getAllTools()` 读取（如 `firecrawl_search` 等）。
- **执行调度**：当模型返回 `web_search` 或 `web_scrape` 时，直接路由至 `WebSearchService`；当调用其他名称时，路由至 `McpService`。
- **System Prompt 改进**：向模型明确说明同时具备内置网页搜索/抓取工具与 MCP 工具，当 MCP 异常或用户要求直接检索时，优先调用 `web_search` / `web_scrape`。

## Risks / Trade-offs

- **[Risk] 内置 Bing 抓取在某些极端海外代理下可能触发人机验证** → `WebSearchService` 已实现 Bing + SearXNG + MCP 降级链，一个后端不可用时自动尝试下一后端。
- **[Risk] 用户私网或国内 IP 未加入白名单** → 在设置或 AI 供应商中提供绕过指引，并在默认配置中保障局域网与回环绝对直连。
