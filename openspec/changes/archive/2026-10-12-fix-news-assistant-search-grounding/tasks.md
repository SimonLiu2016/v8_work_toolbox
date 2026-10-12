## 1. 修好 Bing 摘要提取（首恶，一行正则）

- [x] 1.1 ✅ `b_lineclamp[01]` → `b_lineclamp[0-9]`。注释写明这个正则曾经如何骗过人（样本里 10 个 `b_lineclamp2`、0 个 `[01]`，形状全部照旧通过）
- [x] 1.2 ✅ 新增 `snippets are actually extracted, not silently empty`：要求至少 `length-1` 条带摘要（留 1 条余量给 Bing 偶发的无摘要块）。**这条才是修复的本体**——原来那条测试名里写着 snippets 却从不断言它
- [x] 1.3 ✅ 新增 `snippet extraction covers the lineclamp class variants`：用最小 HTML 逐个验 `b_lineclamp0/1/2/3` 都提得出摘要，将来 Bing 再改名先改这里

## 2. 把当前日期注入 prompt

- [x] 2.1 ✅ system prompt 新增【当前时间上下文】段：`今天是 2026-10-08 星期四`，并说明涉及"今天/最近/最新"以此为准、不要自行推测年份
- [x] 2.2 ✅ 时钟抽成可注入的 `todayProvider`（默认 `DateTime.now()`），测试注入 `DateTime(2026,10,8)` 断言 prompt 含 `2026-10-08 星期四`。**没有写死某一天**——那会随时间腐烂。另测 `formatTodayForPrompt` 的补零与周日（weekday 7）边界

## 3. 检索结果不相关时如实告知，而不是灌给模型

- [x] 3.1 ✅ `searchResultsLookRelevant(query, results)`：从 query 取字片段（中文 2-4 字滑动窗口 + 拉丁词），top 结果标题+摘要一条都不命中才判不相关。**保守判定**：弱相关算相关
- [x] 3.2 ✅ 不相关时在回灌文本前加【系统提示】段：明说检索未命中、不要把这些结果当答案依据、可基于常识但必须说明。**结果本身仍灌给模型**——让它能否决我们的启发式
- [x] 3.3 ✅ 徽章保持 success。工具确实成功了，把启发式升级成"失败"是冒领权威。区分只活在模型读到的内容里
- [x] 3.4 ✅ 6 例：实机事故复现（股市问题 vs 日历网 → false）、相关不误报、部分命中算相关、空 query 不判定、空结果不判定、拉丁大小写。**另有一条钉住已知局限**：「股指」vs「指数」这类同义改写测不出 → 判 false，这是声明过的代价而非缺陷

## 4. MCP 关闭时不再白跑一次搜索后端

- [x] 4.1 ✅ `McpSearchBackend()` 改为 `if (_hasEnabledMcpServer)` 条件入链；判定用 `AiConfigStore.instance.mcpClients.any((m) => m.enabled)`。**MCP 启用时顺序不变**，唯一变化是未启用时不在链上
- [x] 4.2 ✅ 2 例：无启用 server → 链中不含 MCP 后端（复现实机 `mcp_firecrawl.enabled:false`）；有启用 server → 后端回来。为此加了 `debugSearchChainNames` 观察点——否则这个条件判定只能靠打日志人工确认

## 5. 验证

- [x] 5.1 ✅ 全量 `flutter test`：1343 → **1371 passed** / 3 skipped / 20 → 19 failed，**新增失败 0**。
  - 唯一消失的 `msf_rpc_service_test`（live integration: startDaemon…）是既有 flaky——上一轮 change 也见过它时有时无，单独重跑通过。与本次改动无关（本次未碰 security_toolbox）。
  - `flutter analyze lib/`：**0 error**
- [x] 5.2 `flutter analyze lib/` 零 error（2026-10-12 复核：0 error）
- [x] 5.3 ~~实机：重新问"今天股市为什么会大跌"~~ **2026-10-12 经用户确认关闭**：需真实模型调用的实机 AI 行为验证，未执行。后续若发现问题，在新 change 中处理
- [x] 5.4 ~~实机：问一个不需要联网的问题（如"解释什么是闭包"）~~ **2026-10-12 经用户确认关闭**：同上
- [x] 5.5 实机：`./scripts/deploy_local.sh` 部署（2026-10-12 已完成：AOT 602d1473… → 2473117d…，strict 签名通过，实例存活）
