## Why

「MCP 工具清单」按钮挂在 AI 资讯助手窗口顶部，但它罗列的工具全都是在「AI 配置 → 外部 MCP 客户端」页签里配置的。用户在得知某个工具不可用时，被迫离开当前窗口、穿过主界面侧栏、才能到达真正该改的地方；而按钮自己的空状态文案（"请先在 AI 设置中配置并启用"）也已经在向用户指向别的窗口。同时，`_testMcpClient` 探测得到的完整工具列表只在 SnackBar 里显示了前 5 个名字，其余被丢弃——两份工具数据（探测结果与 `getAllTools()`）各算一份，重复发起进程且互不一致。此外，`'ai-assistant'` 这个代理工具标识以魔法字符串散落在 11 处，字符串漂移会让代理静默失效。

## What Changes

- **MCP 工具清单移入「外部 MCP 客户端」页签**：从 AI 资讯助手窗口顶部移除入口，在 `ai_config_page.dart` 的「外部 MCP 客户端」页签内以常驻区块展示已加载的 MCP 工具，按所属客户端分组，显示工具名、描述与服务名；无工具时显示引导文案并保留指向「添加 MCP 服务」的路径。
- **复用探测结果，消除重复进程拉起**：工具清单以「测试连接与探测工具」已缓存的 `McpServerStatus.tools` 为数据源，未探测的客户端显示"未探测"占位；不再在该页签额外调用 `McpService.instance.getAllTools()`（该方法继续服务于 AI 助手的 system prompt 构建，不改变其行为）。
- **代理开关保留原位**：AI 资讯助手窗口顶部的「代理」开关保持不动。它是工具级状态（驱动 `web_search_service` 的 Bing 域名选择与 `AppHttpClient` 的通道决策），且与「文档朗读」工具窗口的同构开关构成既有惯例。
- **引入共享工具标识常量**：收拢散落的 `'ai-assistant'`、`'doc-audio-reader'` 字符串为具名常量，`web_search_service`、`ai_assistant_page`、`doc_audio_reader_page`、`registry` 与相关测试统一引用，消除字符串漂移风险。

## Capabilities

### New Capabilities

*(无)*

### Modified Capabilities

- `ai-configuration`：「外部 MCP 客户端」页签新增「已加载 MCP 工具清单」的可见性要求——探测后工具必以客户端分组可见，未探测时显示占位状态。
- `ai-news-assistant`：AI 助手窗口不再提供 MCP 工具清单入口，该视图的职责收敛为纯对话与检索交互。

> 说明：本次为 UI 重定位 + 常量收拢，运行时行为（工具的加载、调用、代理决策）不变。两处 spec 增补的是"入口位置与可见状态"的可观察契约，用于防止清单入口再次漂回对话窗口。

## Impact

### Affected Code
- `lib/tools/ai_assistant/ui/ai_assistant_page.dart` — 移除 `_showMcpToolsDialog` 与顶部按钮
- `lib/shell/ai_config_page.dart` — 「外部 MCP 客户端」页签新增工具清单区块（复用 `_mcpTestResults`）
- `lib/services/web_search_service.dart`、`lib/tools/ai_assistant/ui/ai_assistant_page.dart`、`lib/tools/reader/ui/doc_audio_reader_page.dart`、`lib/tools/registry.dart` — 统一引用工具标识常量

### Affected APIs / Dependencies
- `McpService.getAllTools()` 调用点不变（`ai_assistant_service.dart` 继续使用），本 change 不改其签名或行为
- 代理持久化格式 `config/proxy.json` 的 `perToolEnabled` 键名不变；仅把产生键名的字面量换成常量，**无数据迁移**

### Test Impact
- `test/network_proxy_test.dart` 中 `'ai-assistant'` / `'doc-audio-reader'` 断言改用常量；新增页签内工具清单可见状态的 widget 级测试
