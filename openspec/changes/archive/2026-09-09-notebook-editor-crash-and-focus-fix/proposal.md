## Why

在“笔记本”工具中创建或切换笔记时，子窗口由于缺少 `FlutterQuillLocalizations.delegate` 导致工具栏按钮在构建时抛出 `MissingFlutterQuillLocalizationException`，在 Release 模式下被 Flutter 底层降级替换为纯色色块（黑白交替条块），并引发 `RenderFlex overflowed by 199525 pixels` 致命布局崩溃。同时，正文编辑器缺少持久 `FocusNode` 与空白区点击捕获，导致新笔记完全无法获得焦点和输入。需要修复国际化代理缺失、隔离编辑器状态生命周期，并补全空白区点击即聚焦交互。

## What Changes

- **国际化代理注入**：在 `_NotebookWindowApp`（以及主应用 `V8WorkToolboxApp`）的 `MaterialApp` 中添加 `FlutterQuillLocalizations.delegate` 与常规国际化委托，彻底消除工具栏构建期崩溃与黑白块假象。
- **编辑器状态隔离**：在 `NotebookPage` 中为 `NoteEditor` 绑定 `Key(_selectedNote?.id ?? 'empty')`，确保切换笔记时完整重置 State，杜绝 Controller 在渲染树中被提前 dispose 的冲突。
- **持久化焦点与滚动管理**：在 `_NoteEditorState` 中实例化持久的 `FocusNode _editorFocusNode` 与 `ScrollController _editorScrollController`，并在 dispose 时安全释放。
- **正文空白区点击穿透聚焦**：在外层包裹 `GestureDetector`，点击正文区域任意空白位置自动为 `_editorFocusNode` 请求输入焦点并将光标定位至文档末尾；空笔记时默认自动聚焦。

## Capabilities

### New Capabilities
- `notebook-editor`: 规范笔记编辑器的国际化代理、状态生命周期管理、焦点稳定维护与全屏空白区点击聚焦交互规范。

### Modified Capabilities
<!-- 无需修改已有 main specs -->

## Impact

- `lib/main.dart`: 在子窗口与主窗口的 MaterialApp 中引入国际化代理。
- `lib/tools/notebook/ui/note_editor.dart`: 修复 FocusNode、ScrollController 生命周期与正文空白区点击聚焦。
- `lib/tools/notebook/ui/notebook_page.dart`: 为 `NoteEditor` 绑定基于笔记 ID 的 Key。
