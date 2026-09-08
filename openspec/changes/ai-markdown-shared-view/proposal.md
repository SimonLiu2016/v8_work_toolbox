## Why

AI 生成的内容在多处 UI 中以 `SelectableText` 渲染，markdown 语法（`##` 标题、`**加粗**`、`-` 列表、``` 代码块）原样显示为纯文本，不可读。

当前 `lib/` 下共 3 处 `SelectableText`，其中 2 处承载 AI 输出：

| 位置 | 内容来源 | 是否需要 markdown |
|---|---|---|
| `ai_assistant_page.dart:290` | 用户输入气泡 | 否（用户原样输入，不应被解析） |
| `ai_assistant_page.dart:338` | AI 回答气泡 | **是** |
| `scheduled_tasks_drawer.dart:299` | 定时资讯快报 | **是** |

另外，上一个变更 `slimmer-ai-markdown-render` 已在 `smart_disk_slimmer_page.dart:373` 内联了约 33 行 `MarkdownStyleSheet`。若其余两处也内联，同一份样式将存在 3 份拷贝，改一处漏两处。

## What Changes

- 新增共享组件 `lib/components/markdown_view.dart`（`AppMarkdownView`），封装 `MarkdownBody` 与统一 `MarkdownStyleSheet`
- 将 `ai_assistant_page.dart` 的 AI 回答气泡改为使用 `AppMarkdownView`
- 将 `scheduled_tasks_drawer.dart` 的资讯快报内容改为使用 `AppMarkdownView`
- 将 `smart_disk_slimmer_page.dart` 中已内联的 `MarkdownStyleSheet` 替换为 `AppMarkdownView`，消除重复（与 `slimmer-ai-markdown-render` 同一目标，由本变更取代其内联写法）
- 用户输入气泡保持 `SelectableText` 不变

## Capabilities

### New Capabilities

（无 — 纯 UI 渲染改进，无行为变更）

### Modified Capabilities

（无）

## Impact

- `lib/components/markdown_view.dart` — 新增共享组件
- `lib/tools/ai_assistant/ui/ai_assistant_page.dart` — AI 回答气泡接入
- `lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart` — 资讯快报接入
- `lib/tools/slimmer/smart_disk_slimmer_page.dart` — 移除内联样式，改为接入共享组件
- `flutter_markdown` 依赖已由 `slimmer-ai-markdown-render` 引入（`pubspec.yaml:31`，`^0.7.7+1`），本变更不新增依赖

## 与 slimmer-ai-markdown-render 的关系

两个变更均在工作区中处于未提交状态。`slimmer-ai-markdown-render` 解决的是"一处内联"，本变更将其泛化为共享组件并覆盖另外两处。落地时以本变更为准：`smart_disk_slimmer_page.dart` 的内联样式会被删除，`flutter_markdown` 依赖保留。建议将 `slimmer-ai-markdown-render` 归档为已被取代（superseded），不单独合并。
