## 1. 工具标识常量收拢

- [x] 1.1 在 `lib/tools/registry.dart` 定义 `kToolIdAiAssistant = 'ai-assistant'` 与 `kToolIdDocAudioReader = 'doc-audio-reader'`，并使 `AiAssistantToolDefinition.id` / `DocAudioReaderToolDefinition.id` 返回对应常量
- [x] 1.2 将 `lib/services/web_search_service.dart` 中 4 处 `'ai-assistant'`（域名决策 1 处 + `AppHttpClient.create(toolId:)` 3 处）替换为常量
- [x] 1.3 将 `lib/tools/ai_assistant/ui/ai_assistant_page.dart` 的 2 处 `'ai-assistant'` 与 `lib/tools/reader/ui/doc_audio_reader_page.dart` 的 2 处 `'doc-audio-reader'` 替换为常量
- [x] 1.4 将 `test/network_proxy_test.dart` 中的 `'ai-assistant'` / `'doc-audio-reader'` 断言改为引用常量
- [x] 1.5 grep 校验：全库裸字面量 `'ai-assistant'` / `'doc-audio-reader'` 仅剩常量定义处，运行 `flutter test test/network_proxy_test.dart` 确认无回归

> 落地说明：常量定义在 `lib/tools/tool_definition.dart`（而非 registry.dart——它是所有工具定义的共享基座，registry 与各 service 均可无环引用）。常量收拢顺带覆盖了 tasks 未列名的 `reader/services/document_parser.dart`、`reader/services/tts_engine.dart`、`test/doc_audio_reader_test.dart`，最终 grep 裸字面量为 0。

## 2. 「外部 MCP 客户端」页签内工具清单

- [x] 2.1 在 `lib/shell/ai_config_page.dart` 的「外部 MCP 客户端」页签新增「已加载 MCP 工具」区（置于客户端列表之后的底部，见 design 开放问题 1 的默认决定）
- [x] 2.2 遍历 `store.mcpClients`，按客户端分组渲染 `_mcpTestResults[client.id]?.tools`；以 `client.enabled` 为闸门，停用或已删除的客户端不显示工具
- [x] 2.3 为未探测的客户端渲染占位态：文案说明"连接测试后显示工具"并指向该客户端自己的「测试连接与探测工具」按钮
- [x] 2.4 单个工具条目显示工具名与描述（描述超长截断），并显示所属服务名；空工具集的已探测客户端显示"未发现工具"分组而非隐藏
- [x] 2.5 工具数较多的客户端置于独立滚动容器，避免撑高整个页签

> 落地说明：清单抽为独立 widget `lib/shell/mcp_tool_inventory_view.dart`（`McpToolInventoryView`），由页签的 `_buildMcpWithInventory()` 拼进同一 ListView 与配置区共用一次滚动。独立 widget 使任务 4 的 widget 测试可直接注入 `probeResults`，不必构建整个 `AiConfigPage`（那会牵动单例 store 与持久化）。

## 3. 移除助手窗口的工具清单入口

- [x] 3.1 删除 `lib/tools/ai_assistant/ui/ai_assistant_page.dart` 中 `_showMcpToolsDialog`（`:67-116`）
- [x] 3.2 删除顶部 header 中的「MCP 工具清单」`AppButton.secondary`（`:122-127`）及其 `SizedBox` 间距
- [x] 3.3 保留 header 中的「代理」开关不动，确认常量替换（任务 1.3）未改动其行为
- [x] 3.4 清理因删除而失效的 import（`services/mcp_service.dart`），确认 `flutter analyze` 无未使用告警

## 4. 测试与验证

- [x] 4.1 新增 widget 测试：配置客户端 + 预设探测结果后，清单按客户端分组显示工具名与描述
- [x] 4.2 新增 widget 测试：未探测客户端显示占位态且不显示工具
- [x] 4.3 新增 widget 测试：停用客户端后其工具清单不再展示
- [x] 4.4 新增测试：AI 助手窗口 header 不含工具清单入口（无「MCP 工具清单」文本的 button）
- [x] 4.5 运行全量 `flutter test` 与 `flutter analyze`，确认无回归
- [x] 4.6 运行 `openspec validate consolidate-mcp-tool-list-and-tool-ids --type change`

> 验证说明（4.5）：全量 `flutter test` 结果 `773 passed / 3 skipped / 15 failed`。
> 15 个失败逐一用 `git stash` 在干净树上复跑，**改动前同样失败**，与本次无关：
> 10 个 notebook 表格/编辑器交互测试（`table_*` / `notebook_editor` /
> `pointer_tap_table` / `notebook_codeblock_interactive`）、
> `doc_audio_reader_test` 的 AiLogger 落盘测试、以及 `mcp_assistant_test` 的
> testConnection（单独复跑 3 次均通过，属进程握手时序 flaky）。
> 本 change 新增的 `test/mcp_tool_inventory_test.dart`（5 例）与受影响的
> `test/network_proxy_test.dart`（6 例）、`test/doc_audio_reader_test.dart`
> 中除 AiLogger 外全部通过。`flutter analyze lib/` 0 error。
