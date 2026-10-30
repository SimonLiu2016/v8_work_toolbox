## Why

在“AI资讯与检索”或后台自动检索任务中，当系统开启全局代理并使用海外代理节点时，内置默认的 Bing 搜索后端硬编码访问 `https://cn.bing.com/search`。这导致了两个关键故障：
1. **TLS 握手截断**：微软边缘节点检测到海外 IP 访问大陆特化域名 `cn.bing.com`，频繁主动截断 TLS 握手，抛出 `HandshakeException: Connection terminated during handshake`。
2. **重定向丢失搜索结果**：海外访问 `cn.bing.com/search` 会被 301 重定向至 `https://www.bing.com/?q=...`（重定向至首页而非搜索页），页面不包含任何 `b_algo` 搜索结果块，导致解析结果数恒为 0。

此外，当前搜索降级链中，SearXNG 默认未启用且 Firecrawl MCP 经常离线，导致首个后端故障即直接抛出“执行受阻”异常给用户。因此需要增强搜索后端的自适应路由、主备容灾切换与兜底检索机制。

## What Changes

1. **BingSearchBackend 双域名自适应与主备容灾切换**：
   - 代理感知路由：开启代理时优先采用国际端点 `https://www.bing.com/search`，直连时优先采用国内端点 `https://cn.bing.com/search`。
   - 互备容灾探测：若首选域名发生握手异常（`HandshakeException`）、网络超时或解析为空，自动平滑切换至备用域名重试一次。
   - 客户端路由关联：创建 HTTP 客户端时显式声明 `toolId: 'ai-assistant'`，遵循代理工具级分流策略。
2. **新增零配置海外备用搜索源（DuckDuckGo Lite）**：
   - 实现轻量免密钥、零配置的 `DuckDuckGoSearchBackend`（`html.duckduckgo.com/html`），作为搜索后端链的第二兜底源。
3. **网络与握手瞬态重试韧性**：
   - 针对代理建立隧道初期的连接抖动，提供单次握手异常即时重试，提升弱网与代理环境下的可用性。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `ai-news-assistant`: 增强联网检索后端韧性，在开启代理与直连场景下均能自适应调度可用搜索引擎（Bing 国际/国内主备互切 + DuckDuckGo Lite 兜底），杜绝因单一域名阻断导致搜索链路中断。

## Impact
- 影响代码：
  - `lib/services/web_search_service.dart`: 增强 `BingSearchBackend` 支持多域名容灾与代理感知；新增 `DuckDuckGoSearchBackend`；优化 `_searchChain` 降级编排。
  - `test/services/web_search_service_test.dart`: 增加 Bing 双域名与 DuckDuckGo 解析与容灾测试用例。
- 外部依赖与系统影响：无外部新依赖引入，完全复用现有 `AppHttpClient` 与基础 Dart 库。
