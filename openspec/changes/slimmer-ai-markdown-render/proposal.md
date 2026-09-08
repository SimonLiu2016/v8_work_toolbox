## Why

AI 深度研判弹窗（`_showSingleAiDialog`）使用 `SelectableText` 渲染 AI 返回的分析报告。AI 按 prompt 要求返回 markdown 格式（`##` 标题、`**加粗**`、`-` 列表等），但 `SelectableText` 不解析 markdown，语法符号原样显示，影响可读性。

## What Changes

- 新增 `flutter_markdown` 依赖
- 将 AI 深度研判弹窗中的 `SelectableText` 替换为 `MarkdownBody`，正确渲染 markdown 标题、加粗、列表、代码块等
- 配置 markdown 样式与 AppTheme 保持一致（字体、颜色、间距）

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

（无 — 纯 UI 渲染改进，不涉及行为变更）

## Impact

- `pubspec.yaml` — 新增 `flutter_markdown` 依赖
- `lib/tools/slimmer/smart_disk_slimmer_page.dart` — `_showSingleAiDialog` 方法中替换渲染组件
- 改动面极小（1 个依赖 + 1 处 UI 替换），不影响其他功能
