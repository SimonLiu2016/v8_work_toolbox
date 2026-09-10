## Context

在之前的实现中，`_NotebookWindowApp` 是独立的 MaterialApp 根组件，并未配置 `FlutterQuillLocalizations.delegate`，而 flutter_quill 11.5.0 在渲染工具栏按钮（如撤销/重做、待办清单提示等）时强制要求本地化委托，否则在 build 期抛出 `MissingFlutterQuillLocalizationException`。在 macOS Release 模式下，未捕获异常导致按钮被替换为 ErrorWidget 纯色方块并伴随严重溢出，导致编辑器不可用。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 在 `_NotebookWindowApp` 与 `V8WorkToolboxApp` 中完整注入 FlutterQuill 本地化委托与常用系统委托。
- 通过为 `NoteEditor` 提供基于笔记 ID 的 `ValueKey` 保证切换笔记时 State 树干净卸载与重建。
- 在 `_NoteEditorState` 中持有生命周期完备的 `FocusNode` 与 `ScrollController`。
- 在编辑器周围添加全尺寸 `GestureDetector`，捕获整屏正文空白区点击并定位光标。

**Non-Goals:**
- 不重构底层 SQLite 存储结构或 Delta 解析逻辑。
- 不变更笔记本树状目录或侧边栏分类结构。

## Decisions

1. **MaterialApp 全局注入 `FlutterQuillLocalizations.delegate`**
   - *Rationale*：这是 flutter_quill 官方标准要求，可一劳永逸防止任何工具栏按钮抛出缺少国际化的异常。
   - *Alternatives*：重写自定义工具栏不使用官方按钮——维护成本极高且破坏现有功能。

2. **采用 `ValueKey(widget.note?.id ?? 'empty')` 重建编辑器**
   - *Rationale*：当切换笔记时，老编辑器的 State 会被彻底销毁并调用 dispose，新笔记以全新状态和干净的 QuillController 初始化，避免在 `didUpdateWidget` 中手动 dispose 造成组件树中老 Widget 引用已释放控制器的问题。

3. **正文空白区域点击转发机制**
   - *Rationale*：富文本未填满屏幕时，点击外围 Container 自动触发 `_focusNode.requestFocus()`，并使用 `_quillCtrl.updateSelection` 将光标移动到文末。这样用户无论点在空白处何处都能立即唤起输入。

## Risks / Trade-offs

- [Risk]：使用 `ValueKey` 重建 NoteEditor 会导致切换笔记时的微小组件重建开销。
  → [Mitigation]：笔记切换本就是离散的用户交互动作，重建开销在桌面端小于 1 毫秒，换取绝对的状态安全是完全值得的。
