## 1. 依赖

- [x] 1.1 在 `pubspec.yaml` 中添加 `flutter_markdown` 依赖，运行 `flutter pub get`

## 2. UI 改造

- [x] 2.1 在 `smart_disk_slimmer_page.dart` 中导入 `flutter_markdown`
- [x] 2.2 将 `_showSingleAiDialog` 中的 `SelectableText(report)` 替换为 `MarkdownBody`，配置 `MarkdownStyleSheet` 与 AppTheme 一致

## 3. 验证

- [x] 3.1 手动验证：点击"让 AI 分析此文件/目录"，确认弹窗中 markdown 标题、加粗、列表正确渲染


## 归档说明

本变更已于 4eeab46 实施完毕并经人工验证。`ai-markdown-shared-view` （bab08c6）随后将内联 `MarkdownStyleSheet` 收敛为共享组件 `AppMarkdownView`，本变更为直接祖先而非并行替代：`flutter_markdown` 依赖与 slimmer 弹窗的 markdown 渲染均由本变更引入，未回退，仍保留在提交历史中。归档时点（20:53）晚于最后一次构建（20:37），归档期间无代码改动，已安装版本不受影响。
