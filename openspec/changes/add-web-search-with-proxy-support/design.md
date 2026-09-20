# Design: 内置联网检索 + 显式代理通道

## Context

现有联网能力单点依赖：`McpService`（stdio 子进程）→ 自部署 Firecrawl。该链路当前全部端点返回 `HTTP/2 502`（body 0 字节），且 `testConnection` 无法发现此事——它只跑 `initialize` + `tools/list`，两步都不发网络请求。

代码现状的关键约束：

- **5 处裸建 `http.Client()`**，无代理感知：
  - `lib/services/ai_service.dart:126` — AI 对话主通道，已有 `setMockHttpClient()` 测试缝（`ai_service.dart:156`）
  - `lib/tools/reader/services/document_parser.dart:327`
  - `lib/tools/reader/services/tts_engine.dart:195,460,573` — `OpenAiTtsEngine` 已支持 `clientFactory` 注入
- **`mcp_service.dart:249` `buildSanitizedEnv`** 从 `Platform.environment` 起底构造子进程环境，并 `env.addAll(customEnv)`。宿主无代理变量 ⇒ 子进程无代理变量。
- **已有基础设施可复用**：`AiService` 的供应商健康缓存与冷却窗口模式（`_healthCache`、`cooldownDuration`、`_isProviderHealthy`）是后端探活与降级的现成范式。`scheduled_news_service.dart` 已持久化任务与快报。
- **`http: ^1.2.2` 已在 pubspec**，不引入新依赖。

实测网络事实（2026-09-20，见 proposal）决定了后端排序：`cn.bing.com` 直连可用；SearXNG 需代理且仅 3/9 实例可用；`api.firecrawl.dev` 云端 keyless scrape 可用但 search 返回 500；自部署实例彻底不可用。

## Goals / Non-Goals

**Goals**
- 检索能力不依赖任何外部 MCP 进程，进程级故障不导致检索全灭。
- 代理策略单点定义、全局生效，且覆盖外部子进程。
- 连通性测试反映真实远端状态。
- 失败路径可诊断，且瞬时故障不被固化成静默窗口。

**Non-Goals**（详见 proposal 非目标章节）
- 不做应用内 VPN / TUN / 路由表操作。
- 不改造 `_runAgentLoop` 的正则协议为原生 function calling。
- 不重写 MCP 会话管理结构。

## Decisions

### D1: 代理作为 `http.Client` 的子类型，而非全局 monkeypatch

`dart:io` 的 `HttpOverrides` 可以全局注入 `HttpClient`，但它是进程级单点、无回滚粒度、且在 Flutter macOS 桌面端与 `package:http` 的交互有坑。

**选定**：新增 `AppHttpClient extends http.BaseClient`，内部委托 `IOClient` 并设置 `HttpClient.findProxy`。代理开关变化时重建实例。

**为什么**：调用方只依赖 `http.Client` 接口，`setMockHttpClient` 这类测试缝完全保留——测试仍然注入 fake client，生产走 `AppHttpClient`。分叉收敛在**构造点**一处，而非 5 个调用点。

**被否**：全局 `HttpOverrides`（无粒度、影响面不可控）；给 5 处调用方各自传 client（重复 5 遍、将来第 6 处又会漏）。

### D2: 代理配置存 `SettingsStore`，不存 `ai_config.json`

`SettingsStore`（`lib/services/settings_store.dart`）已有 `readToolConfig`/`writeToolConfig` 的原子写 + tmp 文件模式。

**选定**：存 `proxy.json`，字段 `{host, port, enabled}`。

**为什么**：代理是**应用基础设施**，不是 AI 配置项——`document_parser` 和 `tts_engine` 也消费它。放进 `ai_config.json` 会造成"配置归属在 AI 页、但影响全应用"的误导。UI 入口放在 AI 配置页只是因为那里已经是网络相关设置的聚集地。

**敏感性问题**：代理地址本身不是密钥（无 token、无密码），存明文配置文件可接受，与 `ai_config.json` 中 `baseUrl` 的处理一致。不写入 Keychain。

### D3: 两条链各自排序 = 零配置优先，代理依赖靠后

```
SEARCH 链:
  cn.bing 直连 (HTML 解析)  →  SearXNG (需代理, 用户显式启用)
                             →  自部署 firecrawl 实例 (firecrawl_search)

SCRAPE 链:
  自部署 firecrawl 实例 (firecrawl_scrape)  →  api.firecrawl.dev 官方云 keyless
```

**为什么这个顺序**：
- `cn.bing` 直连可用、零配置、零第三方、零密钥——是唯一在所有网络条件下都可能工作的后端，必须是第一位。
- SearXNG 返回结构化 JSON（比解析 HTML 稳），但依赖代理且可用率仅 3/9，且查询词出本机 ⇒ 必须用户显式启用。
- 自部署实例在 search 链排最后：用户明确配置过它，且修好后希望能被使用；但它是单点、无冗余。
- **官方云放在 scrape 链的第二位而非 search 链**：`/v1/search` 实测 500 不可用，但 `/v1/scrape` 实测**返回真实内容且可重复**（`example.com` → 167 字 markdown，`docs.flutter.dev` → 4843 字 markdown，两次独立请求均成功）。它 keyless、零配置，是抓取能力的免费兜底。

**抓取链为何自部署优先**：用户为自部署实例配置了 API key 与端点，那是明确的意图；官方云是免费兜底，不应抢占用户已付费/已配置的实例。与 search 链的排序理由不同——search 链按「可用率」排序，scrape 链按「用户意图优先级」排序。

**被否**：SearXNG 优先（更快更干净，但依赖代理 + 第三方隐私 + 低可用率）；MCP 优先（等于保留现状的单点故障）；官方云放在 scrape 链首位（会掩盖用户自部署实例的故障，且云端有速率限制，不应作为主路径）。

### D4: 后端健康状态复用 `AiService` 的冷却窗口模式

`AiService` 已有 `ProviderHealthState` + `_healthCache` + `cooldownDuration` + `_isProviderHealthy()` 的完整范式（`ai_service.dart:141-163`）。

**选定**：`WebSearchService` 内部维护同构的 `Map<String, BackendHealthState>`，失败后端进入 60s 冷却，冷却期内直接跳过。

**为什么**：不新造健康模型，团队认知成本低，行为可预期（用户对 AI 供应商的降级已有心智模型）。冷却窗口使连续故障的后端不会阻塞每次检索的超时预算。

### D5: 定时任务的 `lastRunTime` 语义修正

当前 `scheduled_news_service.dart:270` 在搜索**之前**赋值。

**选定**：仅在检索**成功**时赋值。失败保持旧值，下个 30s tick 即重试。

**为什么**：间隔语义应该是"两次**成功**检索之间至少间隔 N 分钟"，而不是"两次**尝试**之间"。前者是运维上可预期的行为；后者把瞬时抖动放大成两小时静默。

**风险与缓解**：见下方 Risks——死循环防护。

### D6: 探活的"真实网络探测"用轻量工具调用实现

`ai-configuration` 规格要求测试必须强制一次真实网络请求。

**选定**：`testConnection` 在 `tools/list` 之后追加一次 `tools/call`，工具名与参数由后端注册表提供（对 Firecrawl 用 `firecrawl_scrape` + `https://example.com` + `onlyMainContent`）。该调用 15s 超时。

**为什么**：不能硬编码 `firecrawl_search`——官方云 `/v1/search` 返回 500，用它做探活会产生误报。`firecrawl_scrape` 是实测稳定的端点。同时用短超时把测试 UX 控制在可接受范围。

**被否**：直连远端 `/health`（绕开 MCP 层，测的不是用户实际走的通路）；跳过探活（等于不做）。

## Risks / Trade-offs

**[cn.bing HTML 解析脆弱]** → 这是最大的长期债务。Bing 改一次 DOM，默认后端就静默失效。
缓解：解析器严格失败 —— 匹配不到任何 `b_algo` 块时**显式抛错并标记后端不可用**，绝不静默返回空列表（规格已强制）；解析结果写入测试用例锁定当前结构；UI 上标注默认后端名称，让用户知道数据来源。
接受：这是"零配置"的必然代价。要稳定性就得有 key，而 key 就意味着配置成本。

**[D5 导致任务高频重试]** → 若检索永久失败，任务每 30s tick 都会重试一次，浪费资源。
缓解：加**连续失败计数**，连续失败 ≥ 5 次后进入 10 分钟退避（复用 D4 的冷却模式），期间不重试但也不消费窗口。这是"不消费窗口"与"不空转"的折中。

**[统一 HTTP 出口可能破坏测试]** → `AiService.setMockHttpClient` 与 `OpenAiTtsEngine.clientFactory` 是两个已存在的测试缝，改造时不能弄丢。
缓解：`AppHttpClient` 只是 `http.Client` 的一个实现，注入点不变。改造后必须跑 `test/ai_config_test.dart` 与 reader 相关测试确认无回归。

**[代理配置错误的连锁失败]** → 用户填错端口，AI 对话、TTS、文档解析、MCP 子进程同时挂掉。
缓解：配置界面提供"检测代理通道"按钮（`network-proxy` 规格要求），保存前即可验证；且所有失败必须有诊断信息而非静默。

**[SearXNG 第三方隐私]** → 查询词出本机，且该 app 内有 `privacy_security_service`。
缓解：规格强制用户显式启用 + 启用时显著提示；默认不启用。

**[官方云 keyless 有速率限制]** → 作为兜底可能很快被限流。
缓解：放在链尾，且失败进冷却。不作为主路径。

## Migration Plan

分三步落地，每步独立可验证，无需数据迁移（无既有持久化结构变更）：

1. **代理通道**（`network-proxy`）— 先做。它是其他两层的前提。无配置时行为与现状完全一致，因此可以独立合并。
2. **检索抽象 + 后端链**（`web-search`）— 替换 `scheduled_news_service.dart:274` 的硬编码 `'firecrawl_search'`。此时即使不做探活改造，定时任务也已在自部署实例挂掉的情况下可用。
3. **诊断修正**（`ai-configuration` / `ai-news-assistant` 的 MODIFIED 部分）— `testConnection` 追加真实探测；`lastRunTime` 语义修正；重试与退避。

**回滚**：三层各自独立。任一层出问题，回滚该层即可，不影响其他层。代理层回滚 = 忽略配置走直连，无状态残留。

## Open Questions

无。以下看似待决、实际已被决策关闭：

- ~~是否把官方云 keyless 放进本次范围？~~ → 不。官方云 search 实测 500，不可用；它的 scrape 能力属于下一阶段独立的 scrape 链（D3 已定）。
- ~~代理要不要存 Keychain？~~ → 不存，代理地址非密钥（D2 已定）。
- ~~探活用 search 还是 scrape？~~ → scrape，因为 search 端点实测 500（D6 已定）。
- ~~本次要不要做 scrape 链？~~ → 不。定时任务与聊天兜底只需要 search；scrape 是给「已知 URL 抓全文」用的，使用频率低得多。抽象预留位置，实现另起 change。
