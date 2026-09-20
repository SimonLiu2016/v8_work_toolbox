# Proposal: 内置联网检索 + 显式代理通道

## 背景与问题

「AI 咨询与检索」当前只有一条联网路径：`McpService` → stdio 子进程 → 自部署 Firecrawl 实例。这条链路存在两层断裂，且**当前无法自我诊断**：

1. **外部依赖失效**：自部署实例（43.133.77.38.nip.io）的 Caddy 上游全灭——TLS 与鉴权层正常，但 `/health`、`/v1/search`、`/v1/scrape`、`/v1/map`、`/v1/crawl`、`/v1/extract` 全部返回 `HTTP/2 502` 且 body 为 0 字节。应用侧看到的只是工具返回 `isError: true`。
2. **连通性测试是假信号**：`McpService.testConnection` 只执行 `initialize` + `tools/list`，两步都不发任何网络请求（`tools/list` 是 `firecrawl-mcp` 本地硬编码的 26 个工具定义）。UI 因此报告「连通性正常、工具列表正常」，用户据此确信配置无误。实测结果：`initialize` 3.5s ✅、`tools/list` 26 个 ✅、`tools/call firecrawl_search` ❌。

由此产生的具体故障表现：

- 定时咨询任务「立即执行一次」显示「未检索到新的有效动态」。真实错误 `read ECONNRESET` 仅进 `debugPrint`，用户看到的是「我查过了，没新闻」而非「我没查到任何东西」——两种情况的处置方式完全不同。
- 聊天中每次工具调用都显示「执行受阻」。
- `scheduled_news_service.dart:270` 在搜索**之前**赋值 `lastRunTime = DateTime.now()`，一次失败就消耗掉整个执行窗口（默认 120 分钟），瞬时故障被固化为长时间静默。

此外发现一项隐形的网络前提：应用当前**完全没有代理感知能力**（`lib/` 下无任何 `HTTP_PROXY` / `HttpProxy` 处理），有 5 处裸建 `http.Client()`，`mcp_service.dart:249` 的 `buildSanitizedEnv` 从 `Platform.environment` 起底构造子进程环境——宿主进程没有代理变量，MCP 子进程也拿不到。当前连通性完全依赖 Clash Verge TUN 模式在系统层兜底，TUN 一关即全面断网，而用户无从察觉。

## 解决方案

三层结构，按依赖顺序落地：

**第一层：显式代理通道**
在 AI 配置页增加代理设置，统一封装为 `AppHttpClient` 替换 5 处裸 `http.Client()`，并经 `buildSanitizedEnv` 透传给 MCP 子进程。空值 = 直连，保持现有行为。

**第二层：可插拔检索与抓取后端**
新建 `WebSearchService` 抽象，统一 `search(query, limit)`、`scrape(url)` 与 `healthCheck()`。两条后端链各自按优先级自动降级，每个后端独立探活，替代现有硬编码的 `'firecrawl_search'` 字面量。

**第三层：诊断与降级体验**
`testConnection` 增加一次真实网络探测，UI 明确区分「MCP 子进程可达」与「远端 API 可达」；定时任务区分「无新动态」与「检索失败」，失败不推进执行窗口。

## 能力（Capabilities）

**新增**
- `web-search` — 内置可插拔联网检索能力，含后端链自动降级、独立探活与零配置默认后端。
- `network-proxy` — 应用级显式代理通道，统一 HTTP 客户端出口，并透传给外部子进程。

**变更**
- `ai-configuration` — MCP 连通性测试升级为真实网络探测，区分子进程可达与远端可达；代理配置进入设置界面。
- `ai-news-assistant` — 定时任务检索改走内置检索能力；失败语义与「无新动态」分离。

## 影响范围

- **新文件**：`lib/services/web_search_service.dart`（抽象 + 后端链）、`lib/services/app_http_client.dart`、`lib/services/proxy_settings.dart`
- **修改**：`lib/services/mcp_service.dart`（真实探活 + 代理透传）、`lib/services/scheduled_news_service.dart`（接入抽象 + 失败语义）、`lib/tools/ai_assistant/services/ai_assistant_service.dart`（退避重试）、`lib/shell/ai_config_page.dart`（代理 UI）
- **收敛**：`lib/services/ai_service.dart:126`、`lib/tools/reader/services/document_parser.dart:327`、`lib/tools/reader/services/tts_engine.dart:195,460,573` 改为使用 `AppHttpClient`
- **无新增依赖**：`http: ^1.2.2` 已在 pubspec 中
- **不受影响**：`_runAgentLoop` 的正则解析协议（```tool_call 代码块）保持现状；MCP 会话管理结构保持现状；密钥存储结构不变

## 非目标

- **不实现应用内 VPN**（TUN 设备、路由表操作、证书信任链注入）。本变更为「显式代理 URL 配置 + 全局生效 + 透传 MCP」，不是内核级网络重定向。后者需要 root 权限、系统扩展、防火墙规则，工量约一个月，且超出工具箱定位。
- **不重写 Agent 循环为原生 function calling**。`ai_assistant_service.dart:252` 用正则提取 ```tool_call 代码块的方式本次不动，那是独立的协议升级。
- **不修改自部署实例**。远端 502 需 SSH 登服务器排查 docker compose 编排，本变更只做应用侧降级。
- **把官方云 keyless 放入 scrape 链兜底**。实测 `api.firecrawl.dev/v1/scrape` 可 keyless 工作（200，返回真实 markdown，多次请求可重复），但 `/v1/search` 返回 500。因此官方云**只进 scrape 链**（自部署实例不可用时的抓取兜底），**不进 search 链**。

## 已验证的网络事实

以下为本机实测（2026-09-20），作为后端选择的依据：

| 后端 | 直连 | 经代理 |
|---|---|---|
| cn.bing.com/search | ✅ 200 / 0.38s，10 条结构化结果 | ✅ |
| public SearXNG（9 实例） | ❌ 全部失败 | ✅ 3/9 返回真实 JSON，4/9 返回 429 |
| api.duckduckgo.com | ❌ | ✅ 202 |
| wikipedia API | ❌ | ✅ 200，带 snippet |
| api.firecrawl.dev/v1/scrape | ❌ | ✅ 200 |
| api.firecrawl.dev/v1/search | ❌ | 500 |
| 自部署实例（全部端点） | ❌ TLS 层被干扰 | ❌ `HTTP/2 502`，body 0 字节 |

SearXNG 为第三方托管实例，查询词会发送到陌生服务器，且可用率仅 3/9。因此设为**用户显式开启**的后端，默认不启用。

## 成功判据

1. 自部署实例彻底不可用时，「立即执行一次」仍能返回真实检索结果或明确的失败说明。
2. 聊天中的工具调用能在代理可用的环境下成功返回内容。
3. 「连接测试」不再对失效的后端报告连通。
4. 关闭系统 TUN 时，配置了代理的应用仍可通过代理完成检索；未配置代理时行为与现状一致。
