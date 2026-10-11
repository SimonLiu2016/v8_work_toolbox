## 1. 代理绕过与分流机制 (Proxy Bypass & Direct Routing)

- [x] 1.1 在 `ProxySettings` 中增加 `bypassList` 支持并实现 `shouldBypass(Uri? uri)`，排除 `localhost`、`127.0.0.1`、私有网段以及用户配置的绕过名单
- [x] 1.2 更新 `ProxySettings.findProxyFor`，当目标匹配绕过规则时返回 `'DIRECT'`
- [x] 1.3 编写 `test/proxy_bypass_test.dart` 验证局域网与指定 IP（如 `119.29.249.154`）成功返回 `DIRECT`

## 2. 响应式代理通道同步与健康状态清理

- [x] 2.1 在 `AiService` 中实现对 `ProxySettings.instance` 的监听，在代理开启/关闭/配置变更时自动调用 `rebuildHttpClient()`
- [x] 2.2 在 `AiService` 中增加 `clearHealthCache()`，并在代理变更时重置供应商健康状态与失败冷却，避免 502/连接失败错误长期驻留
- [x] 2.3 确保 `WebSearchService` 与 `AppHttpClient` 能够在代理变更后即时生效新通道

## 3. AI 资讯助手多级检索与抓取工具集成

- [x] 3.1 在 `AiAssistantService` 中将 `WebSearchService` 封装为 `web_search` 和 `web_scrape` 工具并注入到 `AgentLoop` 工具集
- [x] 3.2 在 `AiAssistantService.execute` 回调中支持内置工具与 MCP 工具的无缝分流调度
- [x] 3.3 升级 `_buildSystemPrompt` 提示词，向模型明确说明内置免配置检索工具（`web_search`/`web_scrape`）与 MCP 工具的定位，在无需 MCP 或 MCP 故障时自主使用内置工具联网
- [x] 3.4 在 AI 资讯助手中确保网络调用受该工具的“代理开关”控制，使搜索请求能够利用配置的代理访问外网

## 4. 验证与构建部署

- [x] 4.1 运行单元测试（`flutter test`）确保代理绕过、AiService 同步与搜索工具链逻辑全绿
- [x] 4.2 执行 macOS Release 构建并更新安装至 `/Applications/V8WorkToolbox.app`
- [x] 4.3 验证在启用代理后，向 AI 助手提问 Google 最新动态能够顺畅通过内置工具检索并生成回答，且直连的 AI 供应商不报 502
