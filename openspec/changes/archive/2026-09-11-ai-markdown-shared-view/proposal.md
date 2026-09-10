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

## 与 slimmer-ai-markdown-render 的关系（实施记录）

原计划是"落地时以本变更为准，前置变更归档为已被取代、不单独合并"。实际落地顺序不同，如实记录如下：

- `slimmer-ai-markdown-render` 先单独合并（4eeab46）：引入 `flutter_markdown` 依赖，并在 slimmer 弹窗内联 `MarkdownStyleSheet` 完成 markdown 渲染，经人工验证。
- 本变更随后合并（bab08c6）：将该内联样式收敛为共享组件 `AppMarkdownView`，并覆盖 AI 对话与资讯快报两处；`smart_disk_slimmer_page.dart` 的内联样式删除，`flutter_markdown` 依赖保留。
- 因此二者是直接祖先关系，而非并行替代。前置变更的产出未被回退，仍存在于提交历史中。
- 归档：`openspec/changes/archive/2026-09-08-slimmer-ai-markdown-render/`。归档动作只移动目录（该变更无 `specs/` delta），未改动 `openspec/specs/`。
