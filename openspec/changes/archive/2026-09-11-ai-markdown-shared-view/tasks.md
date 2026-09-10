## 1. 共享组件

- [x] 1.1 新建 `lib/components/markdown_view.dart`，实现 `AppMarkdownView`（`StatelessWidget`，参数：`data`、`baseStyle` 默认 `AppTheme.fontBody`、`codeBlockColor` 默认 `AppTheme.bgCardHover`、`selectable` 默认 `true`、`maxHeight` 可空），内部使用 `MarkdownBody` 并构造派生 `MarkdownStyleSheet`
- [x] 1.2 按 design.md 决策 4 的派生表实现各元素样式（h1/h2/h3、p、strong、em、code（含代码块）、listBullet、blockquote）及对应 padding/indent

## 2. 调用点接入

- [x] 2.1 `lib/tools/ai_assistant/ui/ai_assistant_page.dart:338` 将 AI 回答气泡的 `SelectableText` 替换为 `AppMarkdownView`，`baseStyle` 传入既有 `fontSize: 14, height: 1.6`，并传 `maxHeight = 屏幕高度 × 0.6` 防止超长回答顶高对话列表
- [x] 2.2 `lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart:299` 将资讯快报内容的 `SelectableText` 替换为 `AppMarkdownView`，`baseStyle` 传入既有 `fontSize: 13, height: 1.5`
- [x] 2.3 `lib/tools/slimmer/smart_disk_slimmer_page.dart:373` 删除已内联的约 33 行 `MarkdownStyleSheet`，改为 `AppMarkdownView`，确认视觉与内联版本一致
- [x] 2.4 确认 `ai_assistant_page.dart:290` 用户输入气泡**未改动**，仍为 `SelectableText`

## 3. 验证

- [x] 3.1 运行 `flutter analyze --no-fatal-infos`：本变更相关文件 0 错误 0 警告（仓库仅余 2 条 pre-existing 警告，位于未改动的 `lib/tools/reader/services/tts_engine.dart:460` / `:573`）
- [x] 3.2 新增 `test/markdown_view_test.dart`：13 个测试覆盖标题/加粗/列表/code 渲染、`selectable` 透传、`baseStyle` 派生、标题字号锚定、`codeBlockColor` 生效、`maxHeight` 滚动容器 → 全部通过
- [x] 3.3 修复 `test/ai_rate_limiting_test.dart:132` 的 pre-existing 编译错误（引用了 `slimmer-batch-retry` 已移除的 `pacingDuration` setter），改为断言串行默认步频延迟 → 该文件 3 个测试通过
- [x] 3.4 全量 `flutter test`：181 passed / 1 failed。唯一失败为 `disk_slimmer_hardening_verify_test.dart:92`（`v8-video-downloader` 被判 `SafetyRating.danger`），属本机真实磁盘状态驱动的测试，断言的是孤立应用模糊匹配逻辑，本次未改动任何扫描相关文件（`git diff --name-only` 已确认）
- [x] 3.5 手动验证（用户确认完成）：AI 对话含表格/列表/代码块渲染正确、代码块与气泡背景可区分；资讯快报视觉一致；用户输入气泡中 `**hello**` 与 `` `code` `` 原样显示未被解析；AI 回答与快报中可框选复制
- [x] 3.6 确认 `flutter_markdown ^0.7.7+1` 保留于 `pubspec.yaml`（本变更未移除该依赖）；`slimmer-ai-markdown-render` 已归档至 `openspec/changes/archive/2026-09-08-slimmer-ai-markdown-render/`（该变更无 `specs/` delta，归档未改动 `openspec/specs/`）
