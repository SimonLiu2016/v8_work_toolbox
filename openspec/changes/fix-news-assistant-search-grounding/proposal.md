## Why

AI 资讯与检索助手中问"今天股市为什么会大跌"，界面显示 `web_search 执行成功`，AI 却回答"我目前无法实时联网获取最新的股市数据和财经新闻"。

从实机历史记录取到实证：工具**真的执行成功了**，`args` 为 `{"query":"今天 股市 大跌 原因 A股 2024","limit":5}`，但回灌给模型的检索结果是：

```
### 日历网              https://www.rili.com.cn/
### 今日黄历宜忌查询     https://m.tthuangli.com/jinrihuangli/
### 万年历_日历网        https://www.rili.com...
```

—— 十条结果，全是日历/黄历类站点，与股市无关，且**每条都没有摘要**（只有标题和链接）。

三个缺陷叠加，按因果排序：

1. **Bing 摘要提取正则是坏的**（`web_search_service.dart:393`）：正则写作 `b_lineclamp[01]`，而 Bing 当前实际输出 `b_lineclamp2`。用真实页面实测：限 `[01]` → 10 个块全部 NO MATCH；放宽到 `[012]` → 全部 MATCH。`test/fixtures/bing_sample.html` 里也是 10 个 `b_lineclamp2`、0 个 `b_lineclamp[01]`——**样本一直是新的，只有正则没跟上**。更糟的是现有测试名为 "extracts titles, urls, snippets from real sample"，却从不断言 snippet 非空，所以这个缺陷长期不暴露。后果：模型拿到的每条结果只有标题，无法判断内容是否相关。
2. **搜索结果"非空即成功"**：`search()` 以 `results.isNotEmpty` 作为后端健康的判据。Bing 兴高采烈返回十条日历网，`_markHealthy` + 直接 return，降级链上的 DuckDuckGo 根本不被问。检索结果与 query 不相关这种最常见的失败，在现有设计里**无法表达**。
3. **当前日期没有注入 prompt**：模型不知道今天几号，于是在 query 里拼了 `2024`（今天是 2026-10-08）。项目本身有 `scheduled_news_service` 天天在跑，日期是完全可得的信息。它甚至在同一次会话里还问过用户"今天是几号"。

模型说"无法联网"因此不是无来由的谎言——它看着十条无摘要的日历网链接，要回答股市问题，那句话是对手上材料的如实描述。

**环境事实（已从配置核实，无需用户回答）**：`ai_config.json` 中唯一的 MCP server `mcp_firecrawl` `enabled: false`；`SearXngSearchBackend.isEnabled` 在全项目没有任何赋值处、UI 也无入口，因此实际搜索链只有 Bing → DuckDuckGo →（一个在 MCP 关闭时仍然占位、每次白跑并进冷却的 `McpSearchBackend`）。

## What Changes

- **修好 Bing 摘要提取**：正则覆盖 `b_lineclamp0/1/2`（并容忍未来的 `3/4`），让摘要重新进入模型输入。同时**把"摘要非空"加进现有测试断言**——那条测试的名字已经承诺了 snippet，只是从不检查。
- **把当前日期注入 system prompt**：模型不必再猜年份，query 里的时间词才有锚点。
- **检索结果与 query 明显无关时，不再默默灌给模型**：由系统检测并明确告知"检索结果与问题不相关"，让模型基于常识回答或说明检索未命中，而不是把无关结果当材料。
  - 注意本条**不承诺**"判定一定准确"——相关性判定本身就是启发式的，spec 只要求**可识别且对用户诚实**。
- **从搜索链摘除 MCP 后端（当 MCP 未配置/未启用时）**：`McpSearchBackend()` 目前在链上无条件构造，MCP 关闭时每次搜索都白跑一次失败请求并进冷却。这是既存事实，本次顺带修正（否则用户为一个没启用的服务承担等待与冷却噪声）。
- **明确不在本次范围**：不换搜索源、不引入 SearXNG（它当前无启用入口，启用它是独立决策）、不改结构化 function calling（prompt+正则的工具协议仍在 spec  `ai-news-assistant` 的既有契约内）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `ai-news-assistant`: 检索结果必须真的到达并被使用——摘要不得在链路中丢失、日期上下文必须可得、结果与问题不相关时必须可识别且如实告知，而不是无声地把无关内容当作答案依据。

## Impact

- **Dart**：`lib/services/web_search_service.dart`（Bing 摘要正则；搜索链在 MCP 未启用时不含 MCP 后端）、`lib/tools/ai_assistant/services/ai_assistant_service.dart`（system prompt 注入当前日期；把检索结果的相关性信号传回模型）。
- **测试**：`test/web_search_service_test.dart` 补 snippet 断言（现有 fixture 里就有 10 个 `b_lineclamp2`，无需新样本）；新增日期注入与"结果不相关时如实告知"的测试。
- **数据**：无 schema 变更、无迁移。
- **依赖**：无新增。
- **回归风险**：正则放宽只会让原本为空的 snippet 变成有值，不改变既有返回结构；搜索链摘除 MCP 后端对 MCP 已启用的用户无影响（启用时照常入链）。
