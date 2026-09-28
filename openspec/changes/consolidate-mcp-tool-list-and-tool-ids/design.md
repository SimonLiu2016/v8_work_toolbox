## Context

当前状态（详见 proposal.md - Why）：

- 工具清单入口在 `lib/tools/ai_assistant/ui/ai_assistant_page.dart:170-174`（按钮）+ `:67-114`（`_showMcpToolsDialog`，调 `McpService.instance.getAllTools()`）
- 「外部 MCP 客户端」页签在 `lib/shell/ai_config_page.dart:734-1022`（`_buildMcpTab`），已有每客户端的「测试连接与探测工具」按钮与 `Map<String, McpServerStatus?> _mcpTestResults` 缓存（`:26`）
- `_testMcpClient`（`:1685-1707`）已拿到完整 `res.tools`，但 SnackBar 只 `.take(5)` 展示前 5 个名字后丢弃
- `'ai-assistant'` 魔法字符串 11 处：`web_search_service.dart`(4)、`ai_assistant_page.dart`(2)、`registry.dart:194`(1)、测试(4 处左右)；`'doc-audio-reader'` 2 处

约束：
- `McpService.getAllTools()` 的调用点不得改变——`ai_assistant_service.dart:231` 依赖它构建 system prompt，且它会真实拉起子进程
- 代理持久化格式 `config/proxy.json` 的 `perToolEnabled` 键名不变（仅替换产生键名的字面量）

## Goals / Non-Goals

### Goals
- 工具清单唯一入口落在「外部 MCP 客户端」页签，且默认可见、按客户端分组
- 不新增进程拉起：清单数据复用 `_mcpTestResults` 中已探测到的 `McpServerStatus.tools`
- 工具标识从"散落字符串"收敛为单一具名来源

### Non-Goals
- 不重构 `McpService` 的会话生命周期（`_sessions` 缓存、`disposeAll` 保持原样）
- 不为 `ai-configuration` 增加"自动探测"或"后台刷新工具"能力——未探测就是未探测，显示占位
- 不改 `_testMcpClient` 的判定逻辑或两阶段远端探活语义（`mcp_service.dart:487-547`）
- 不动「文档朗读」工具窗口的代理开关——它已符合工具级惯例

## Decisions

### D1: 清单数据源 = 探测缓存，不重新拉进程

在页签内直接渲染 `_mcpTestResults`，不调 `getAllTools()`。

**为什么**：`getAllTools()` 会为每个启用的客户端 `Process.start` 一个 stdio 子进程（`mcp_service.dart:573-586`）。若用户打开设置页就触发，等于每次进 AI 配置都要拉起 firecrawl 进程、握手、`tools/list`、且会话驻留在 `_sessions` 里不释放。缓存方案零额外进程，代价是"未探测则不显示"。

**替代方案与否决理由**：
| 方案 | 否决理由 |
|---|---|
| 打开页签时 `getAllTools(refresh: true)` | 设置页不应有隐藏的进程副作用；打开即慢数百毫秒到数秒；会话泄漏到 `_sessions` |
| `getAllTools()` 但复用 `_sessions` 已有会话 | 若助手窗口先前跑过会命中缓存，但冷启动时仍要拉进程；且"是否新鲜"无法判断 |
| 应用启动时后台预热 | 引入启动期后台进程，超出本次 scope，且用户没要求 |

**未探测态的呈现**：每个已配置客户端显示占位（"连接测试后显示工具"），并指向该客户端自己的测试按钮。这比隐藏更诚实——避免"没测过"被误读成"没有工具"。

### D2: `McpServerStatus.tools` 不再被视为可丢弃字段

`_mcpTestResults` 从"仅用于 SnackBar 文案"升级为"页签数据源"。这是纯消费侧变化，`McpService.testConnection` 已填充 `tools`（`mcp_service.dart:527`），**无需改服务层**。

SnackBar 的 `.take(5)` 摘要保留（即时反馈有价值），但不再是工具数据的唯一出口。

### D3: 工具标识常量放哪

在 `lib/tools/registry.dart` 已有 `AiAssistantToolDefinition.id`（`:194`）与 `DocAudioReaderToolDefinition.id`（`:162`）的事实旁边，新增一组具名常量：

```dart
// registry.dart 或新的 tool_ids.dart
const String kToolIdAiAssistant = 'ai-assistant';
const String kToolIdDocAudioReader = 'doc-audio-reader';
```

`ToolDefinition.id` 的实现改为返回对应常量，`web_search_service` / UI / 测试全部引用常量。

**为什么放在 registry 侧而非 `ProxySettings`**：代理是消费方之一，但工具 id 的权威定义在工具注册表。`ProxySettings` 不该拥有它不认识的概念。

**替代方案**：enum + extension。否决——`perToolEnabled` 持久化的是 `Map<String, bool>`，enum 要额外维护序列化映射，且现存 `config/proxy.json` 里的键就是字符串。

**兼容性**：常量值与现有字符串逐字相同，`config/proxy.json` 中已持久化的 `perToolEnabled` 键无需迁移。

### D4: ai-news-assistant spec 的两条新场景是"入口负面契约"

spec 写的是"助手窗口 SHALL NOT 提供工具清单入口"——这不是在用 spec 描述 UI 长相，而是在钉住职责边界，防止清单下次又漂回对话窗口（这是它第一次漂移的根因）。同类的"proxy toggle 属于该工具"场景则用来固定"按钮搬走、开关留下"这个不对称决策。

## Risks / Trade-offs

- **[清单可能显得空/陈旧]** — 数据只在测试后存在，且测试结果仅存于内存（`_mcpTestResults` 不进持久化），应用重启后回到"未探测"占位态。
  → Mitigation：占位文案明确说明"连接测试后显示"，并把用户引到该客户端的测试按钮；不为图省事做本地缓存（工具集可能随客户端版本变化，缓存反而更危险）。
- **[冷启动用户看不到任何工具]** — 第一次进页签必然全是占位。
  → Mitigation：可接受的引导成本。原有的 SnackBar `.take(5)` 摘要仍在测试后立即给出正反馈，形成"测一下就能看见"的闭环。
- **[常量收拢的遗漏面]** — `'ai-assistant'` 有 11 处，漏改一处就仍处于漂移风险中。
  → Mitigation：改完后 grep `'ai-assistant'` 与 `'doc-audio-reader'` 的裸字面量应为 0（常量定义处除外）；`test/network_proxy_test.dart` 的断言同步改引用，它们会在测试里兜住回归。
- **[`_mcpTestResults` 与 enabled 状态不同步]** — 用户先测试、后停用该客户端，缓存里的工具仍在。
  → Mitigation：渲染时以 `client.enabled` 为闸门，停用即显示占位而非工具（spec 已立此场景）。

## Migration Plan

1. 加常量 → 替换 11 处引用 → grep 验证裸字面量为 0
2. 页签内渲染 `_mcpTestResults`（含 enabled 闸门 + 未探测占位）
3. 移除助手窗口的按钮与 `_showMcpToolsDialog`
4. 跑 `flutter test`，重点 `network_proxy_test.dart` 与新增 widget 测试

**回滚**：纯 UI + 字面量替换，`git revert` 即完整回退；无数据格式变化，无需迁移脚本。

## Open Questions

- 工具清单区块放页签顶部（客户端列表之上）还是底部？倾向底部——顶部应保留"添加/预置"这两个主动作，清单是结果区。可在实现时按实际观感定，不影响 spec。
- 单个客户端工具数可能很多（firecrawl 一类的服务工具数可达数十）。是否需要折叠/滚动限高？建议 ListView 置于独立滚动容器即可，若有性能问题再议。
