## Context

当前联网检索通过 `WebSearchService` 统一调度。底层默认检索后端为 `BingSearchBackend`，硬编码访问 `https://cn.bing.com/search`，且在调用 `AppHttpClient.create()` 时未传递 `toolId: 'ai-assistant'`。
当用户启用代理（特别是海外代理节点）时，`cn.bing.com` 针对非大陆来源请求出现 TLS 握手主动切断（`HandshakeException`）以及 301 重定向到首页（导致无搜索结果）的现象。
同时，当前搜索降级链中，SearXNG 默认未启用，MCP Firecrawl 处于非必选/离线状态，导致首个后端故障直接上抛。

## Goals / Non-Goals

**Goals:**
- 实现 `BingSearchBackend` 的代理状态感知与端点自适应：开启代理优先 `www.bing.com`，直连优先 `cn.bing.com`。
- 实现 `BingSearchBackend` 内部的双域名自动容灾互切（A/B 端点失败自动尝试备用端点），并为握手异常提供单次快速重试。
- 规范 `AppHttpClient.create(toolId: 'ai-assistant')` 调用，确保工具级代理路由策略生效。
- 新增零配置、免密钥的 `DuckDuckGoSearchBackend`，作为主搜索引擎不可用时的二级自动兜底。
- 提供完备的单元测试，覆盖双域名切换逻辑与 DuckDuckGo HTML 解析。

**Non-Goals:**
- 不变更现有的 MCP 协议交互逻辑与 `SearXngSearchBackend` 用户自配置流程。
- 不引入重型浏览器无头渲染引擎（如 Puppeteer / Playwright）。

## Decisions

### 1. Bing 域名自适应与双向互备容灾
- **决策**：`BingSearchBackend` 保留作为默认首选搜索引擎，内部维护两个端点：`www.bing.com`（国际）与 `cn.bing.com`（国内）。
- **路由逻辑**：
  - 检测当前代理配置：若 `ProxySettings.instance.isConfigured && ProxySettings.instance.isToolEnabled('ai-assistant')` 为真，则主选 `www.bing.com`，备选 `cn.bing.com`；否则主选 `cn.bing.com`，备选 `www.bing.com`。
  - 请求时依次尝试候选端点。若遇到 `HandshakeException`、网络超时、HTTP 状态码异常或解析结果为空，记录警告并立即无缝切至备用端点重试。
  - 只有当两个端点均无法返回有效结果时，才抛出异常触发下一级搜索后端降级。
- **替代方案考虑**：完全弃用 `cn.bing.com` 仅使用 `www.bing.com`。被否决原因：国内直连环境下 `www.bing.com` 可用性较差，双向互备既保内又保外。

### 2. 引入 DuckDuckGo HTML Lite 作为第二兜底源
- **决策**：实现 `DuckDuckGoSearchBackend`，请求 `https://html.duckduckgo.com/html/`。解析其标准 `result__body` / `result__snippet` / `result__title` 结果。
- **编排顺序**：`_searchChain` 调整为 `[BingSearchBackend(), DuckDuckGoSearchBackend(), if (SearXngSearchBackend.isEnabled) SearXngSearchBackend(), McpSearchBackend()]`。
- **替代方案考虑**：使用 Google 搜索网页解析。被否决原因：Google 网页反爬策略极其严苛（频繁触发验证码人机检查），DuckDuckGo HTML Lite 是公认对轻量 API 请求最稳定的零配置搜索引擎。

### 3. 连接与握手瞬态异常重试
- **决策**：针对代理隧道初次握手可能出现的瞬时截断（`HandshakeException`），在单端点请求中捕获并支持 1 次即时重试（重建客户端重连）。

## Risks / Trade-offs

- **[Risk]** 微软 Bing 或 DuckDuckGo 网页结构调整可能导致解析失效。
  → **Mitigation**: 严格的 HTML 正则容错，若提取结果为空则主动抛出错误以激活下一级搜索后端降级；同时双引擎互备，单一引擎结构变动不影响整体搜索可用性。
- **[Risk]** 连续尝试多个端点可能增加搜索耗时。
  → **Mitigation**: 单次请求设置合理的超时时间（10s），主端点正常时零开销；备用端点仅在异常时触发。
