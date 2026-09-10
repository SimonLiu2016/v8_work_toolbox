## Why

笔记本中大量从印象笔记迁移过来的笔记（如“SDD Kit”等 700+ 条笔记）包含内嵌图片（`BlockEmbed.image`）。由于 `NoteEditor` 的 `QuillEditorConfig` 未注册任何 `embedBuilders`，`flutter_quill` 遇到图片节点时直接抛出 `UnimplementedError`。在 Flutter Release 模式下，未捕获异常被全局 `ErrorWidget` 替换为纯灰色容器，造成整片灰色、光标不可对焦且不可编辑。
同时，`NoteEditor` 的选区高亮颜色配置为完全不透明纯色（`Color(0xFFBFDBFE)`），由于 Quill 将高亮选区矩形覆盖绘制在文字上方，导致被选中的文字被不透明色块完全遮挡隐形。

## What Changes

- **实现并注册图片嵌入渲染器（NoteImageEmbedBuilder）**：
  - 在 `NoteEditor` 中实现继承自 `EmbedBuilder` 的图片渲染器，支持本地图片文件路径（`File(path)`）与远程图片的安全加载展示；
  - 具备自适应限制、优雅圆角与图片缺失/损坏时的 Fallback 容错展示，杜绝任何未命中引发的崩溃；
  - 注册 `unknownEmbedBuilder` 作为所有未知 Embed 类型的全兜底，确保任何特殊块元素都不致使编辑器崩溃为灰色块。
- **修复文本选区透明度与对比度**：
  - 将 `NoteEditor` 内部 `textSelectionTheme` 的 `selectionColor` 调整为半透明柔和高亮色（如 `const Color(0x66BFDBFE)`），使覆盖在上层的选区矩形透出底层深色文字；
  - 保持标题输入框 `TextField` 与正文编辑器的选中样式和谐一致。

## Capabilities

### New Capabilities
- `notebook-tool`: 笔记本富文本编辑器内嵌多媒体（图片与扩展块）安全渲染能力，以及可读性良好的半透明选区高亮交互规范。

## Impact

- `lib/tools/notebook/ui/note_editor.dart`: 新增 `NoteImageEmbedBuilder` 与 `NoteUnknownEmbedBuilder`，配置 `QuillEditorConfig.embedBuilders` 与 `unknownEmbedBuilder`，修正 `selectionColor` 为半透明。
- `test/notebook_editor_test.dart`: 增加含本地图片 Embed 与未知 Embed 的笔记渲染测试用例，确保不会抛出未处理异常。
