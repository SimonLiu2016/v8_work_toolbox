## 1. 标题行视觉与样式修复

- [x] 1.1 在 `lib/tools/notebook/ui/note_editor.dart` 中，修改标题 `TextField` 的 `InputDecoration`，显式设置 `filled: false`，消除深灰背景框。

## 2. 编辑器崩溃防护与完备样式兜底

- [x] 2.1 在 `lib/tools/notebook/ui/note_editor.dart` 中，改用 `DefaultStyles.getInstance(context).merge(...)` 合并样式，确保 `link`、`lists`、`indent` 等具备完整默认实现，彻底消除 Release 模式下的空指针灰屏崩溃。
- [x] 2.2 强化 `NoteEditor` 的错误边界与 Delta 文档加载容错，遇到异常或不规范 Delta 时安全降级恢复。

## 3. 印象笔记代码块与媒体导入引擎重构

- [x] 3.1 在 `scripts/evernote_import.py` 中重构代码块提取算法：使用标签匹配算法完整提取包含多层内部 `<div>` 的代码块，支持 `-en-codeblock:true` 与 `--en-codeblock:true`，并提取网页剪藏或深底等宽代码区。
- [x] 3.2 在 `lib/tools/notebook/evernote_import_service.dart` 中对附件资源进行严格图片 MIME/扩展名校验，仅对图片生成 `BlockEmbed.image`，并在 Delta 结构中规范前后换行隔离。

## 4. 验证与构建

- [x] 4.1 编写单元测试验证包含超链接、代码块与混合附件的笔记在 `NoteEditor` 中正常加载与渲染。
- [x] 4.2 运行代码静态分析 `flutter analyze --no-fatal-infos` 并通过。
- [x] 4.3 编译 macOS Release 版本并重启验证实际运行效果。
