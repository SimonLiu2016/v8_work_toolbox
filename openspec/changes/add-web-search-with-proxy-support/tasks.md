# Tasks: 内置联网检索 + 显式代理通道

## 1. 代理通道基础设施（network-proxy）

- [x] 1.1 新建 `lib/services/proxy_settings.dart`：`ProxySettings` 单例，字段 `{host, port, enabled}`，持久化到 `SettingsStore` 的 `proxy.json`，提供地址解析与格式校验（不可解析时抛错并保留旧配置）
- [x] 1.2 新建 `lib/services/app_http_client.dart`：`AppHttpClient extends http.BaseClient`，内部委托 `IOClient` 并设置 `HttpClient.findProxy`；提供静态工厂 `AppHttpClient.create()` 读取当前代理设置，代理未启用时保持直连语义
- [x] 1.3 收敛 `lib/services/ai_service.dart:126`：默认 client 改为 `AppHttpClient.create()`，**保留 `setMockHttpClient()` 测试缝不变**
- [x] 1.4 收敛 `lib/tools/reader/services/document_parser.dart:327` 与 `lib/tools/reader/services/tts_engine.dart:195,460,573`：改用 `AppHttpClient.create()`，`OpenAiTtsEngine` 的 `clientFactory` 注入能力保持可用
- [x] 1.5 验证：跑 `test/ai_config_test.dart` 与 reader 相关测试，确认 `setMockHttpClient` / `clientFactory` 注入路径无回归

## 2. 代理配置 UI 与通道检测

- [x] 2.1 在 `lib/shell/ai_config_page.dart` 增加代理设置区块（主机、端口、启用开关），持久化写入 `ProxySettings`
- [x] 2.2 实现「检测代理通道」按钮：探测代理可达性并区分三种失败原因——「代理未配置」「代理不可达」「远端服务故障」，而非笼统网络错误
- [x] 2.3 代理地址格式非法时阻止保存并提示格式要求，此前生效配置保持不变
- [x] 2.4 代理变更时重建已缓存的 HTTP client 实例，使新通道立即生效

## 3. 代理透传至外部子进程

- [x] 3.1 修改 `lib/services/mcp_service.dart` 的 `buildSanitizedEnv`：代理启用时注入 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`（并设置 `NO_PROXY` 为 localhost 与本机回环段），未启用时**不注入**任何代理变量且不覆盖用户环境原有设置
- [x] 3.2 回归验证：未配置代理时 MCP 子进程环境变量与改造前完全一致（可用现有 `test/mcp_assistant_test.dart` 扩展断言）

## 4. 检索抽象与后端模型（web-search）

- [x] 4.1 新建 `lib/services/web_search_service.dart`：定义 `SearchResult`（标题/链接/摘要）、`ScrapeResult`（正文内容）、`SearchBackend` 接口（`search` / `scrape` / `healthCheck` / `name`）
- [x] 4.2 实现后端健康缓存与冷却窗口，复用 `AiService` 的 `ProviderHealthState` + `cooldownDuration` 模式；连续失败后端在冷却期内直接跳过
- [x] 4.3 实现 `WebSearchService` 链编排：按顺序探测，首个成功者返回，并在结果中标注实际提供数据的后端名称；全部失败时返回携带首个失败原因的失败信号

## 5. 后端实现

- [x] 5.1 实现 `BingSearchBackend`：请求 `cn.bing.com/search`，解析 `<li class="b_algo">` → `<h2><a href>` 取标题与链接、`<p class="b_lineclamp…">` 取摘要。**解析器严格失败**：匹配不到任何结果块时显式抛错并标记后端不可用，绝不静默返回空列表
- [x] 5.2 实现 `SearXngSearchBackend`：用户显式启用后参与搜索链，请求 `/search?q=…&format=json`；429/实例下线时连续失败后从链中临时摘除避免每次检索都等其超时
- [x] 5.3 实现 `McpSearchBackend`：封装对已配置自部署 Firecrawl 实例的 `firecrawl_search` 调用，作为搜索链末位
- [x] 5.4 实现 `McpScrapeBackend`（自部署实例 `firecrawl_scrape`）与 `FirecrawlCloudScrapeBackend`（`api.firecrawl.dev/v1/scrape`，keyless）；抓取链顺序为「自部署 → 官方云」，按用户意图优先级而非可用率排序

## 6. 定时资讯任务接入

- [x] 6.1 修改 `lib/services/scheduled_news_service.dart:274`：检索改为走 `WebSearchService.search()`，移除硬编码的 `'firecrawl_search'` 字面量；把结果拼成供 AI 总结的文本
- [x] 6.2 修正 `scheduled_news_service.dart:270` 的 `lastRunTime` 语义：**仅在检索成功时赋值**；失败保持旧值，下个 30s tick 即重试
- [x] 6.3 分离失败语义：检索失败时明确报告「检索失败 + 首个后端的具体失败原因」，MUST NOT 显示「未检索到新的有效动态」这类暗示"查过了但没新闻"的文案；失败详情不只进 `debugPrint`
- [x] 6.4 增加连续失败退避：连续失败 ≥ 5 次后进入 10 分钟退避，期间不重试也不消费执行窗口，避免每 tick 空转

## 7. 聊天侧工具调用重试

- [x] 7.1 在 `lib/tools/ai_assistant/services/ai_assistant_service.dart` 的工具调用处增加有界重试：连接重置/超时等瞬时故障重试有限次数后再标记失败
- [x] 7.2 重试总耗时 MUST NOT 超过工具调用配置的超时预算；重试与最终失败都需在徽章上可见
- [x] 7.3 保留现有失败反馈路径（徽章展示诊断错误 + 基于已有知识作答），不改变 `_runAgentLoop` 的正则解析协议

## 8. MCP 连通性真实探测

- [x] 8.1 修改 `lib/services/mcp_service.dart` 的 `testConnection`：在 `tools/list` 之后追加一次轻量 `tools/call`（`firecrawl_scrape` + `https://example.com` + `onlyMainContent`），15s 超时，强制一次真实远端网络请求
- [x] 8.2 `McpServerStatus` 增加独立的远端可达字段，把「本地子进程状态」与「远端服务状态」分离呈现；远端不健康时 MUST NOT 报告整体 healthy
- [x] 8.3 更新 `lib/shell/ai_config_page.dart` 的连接测试 UI：分别展示两层状态，远端失败时显示具体传输层原因（超时/连接重置/HTTP 状态码）
- [x] 8.4 确认探活工具选型：使用 `firecrawl_scrape` 而非 `firecrawl_search`（后者实测官方云返回 500，会产生误报）

## 9. 隐私提示

- [x] 9.1 SearXNG 后端默认不启用；启用时在设置位置以显著文字提示「查询内容将发送至第三方实例，请自行评估隐私风险」
- [x] 9.2 验证：用户未做任何配置时第三方后端不参与检索，查询词不离开本机

## 10. 测试与验证

- [x] 10.1 `BingSearchBackend` 解析器单测：用实测抓取的 HTML 样本（含 10 个 `b_algo` 块）断言标题/链接/摘要提取正确；另加一个零匹配样本断言**显式抛错**而非返回空列表
- [x] 10.2 后端链降级单测：首位后端失败时自动尝试下一位，且结果标注实际后端名称
- [x] 10.3 代理透传单测：代理启用时子进程环境含代理变量，未启用时不含且不覆盖原有设置
- [x] 10.4 `lastRunTime` 语义单测：检索失败不推进时间戳，成功才推进；连续失败 ≥ 5 次进入 10 分钟退避
- [x] 10.5 失败语义单测：全部后端失败时返回明确失败信号与首个失败原因，不返回空列表伪装成功
- [x] 10.6 全量回归：`flutter test`，重点确认 5 处 HTTP client 收敛后无破坏

## 11. 手工验证（成功判据）

- [ ] 11.1 自部署实例彻底不可用时，定时任务「立即执行一次」能返回真实检索结果或明确失败说明
- [ ] 11.2 聊天中工具调用在代理可用环境下成功返回内容
- [ ] 11.3 「连接测试」不再对失效的后端报告连通（自部署实例当前应判为不健康）
- [ ] 11.4 关闭系统 TUN 时，配置了代理的应用仍可通过代理完成检索；未配置代理时行为与现状一致
