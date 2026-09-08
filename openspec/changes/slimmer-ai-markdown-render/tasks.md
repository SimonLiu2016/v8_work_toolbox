## 1. 依赖

- [ ] 1.1 在 `pubspec.yaml` 中添加 `flutter_markdown` 依赖，运行 `flutter pub get`

## 2. UI 改造

- [ ] 2.1 在 `smart_disk_slimmer_page.dart` 中导入 `flutter_markdown`
- [ ] 2.2 将 `_showSingleAiDialog` 中的 `SelectableText(report)` 替换为 `MarkdownBody`，配置 `MarkdownStyleSheet` 与 AppTheme 一致

## 3. 验证

- [ ] 3.1 手动验证：点击"让 AI 分析此文件/目录"，确认弹窗中 markdown 标题、加粗、列表正确渲染
