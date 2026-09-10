## 1. 国际化代理注入与根应用加固

- [x] 1.1 在 `lib/main.dart` 中的 `_NotebookWindowApp` 与 `V8WorkToolboxApp` 注册 `FlutterQuillLocalizations.delegate`
- [x] 1.2 引入 `flutter_localizations` 常用代理（GlobalMaterialLocalizations, GlobalWidgetsLocalizations, GlobalCupertinoLocalizations）

## 2. 编辑器生命周期隔离与状态安全

- [x] 2.1 在 `lib/tools/notebook/ui/notebook_page.dart` 中为 `NoteEditor` 挂载 `key: ValueKey(_selectedNote?.id ?? 'empty')`
- [x] 2.2 在 `lib/tools/notebook/ui/note_editor.dart` 的 `_NoteEditorState` 中实例化持久的 `FocusNode` 与 `ScrollController`，并在 `dispose` 中安全释放

## 3. 正文全屏空白区点击捕获与自动聚焦

- [x] 3.1 为富文本编辑区外层 Container 包裹 `GestureDetector`，捕获空白区域点击并触发 `requestFocus()` 与光标末尾定位
- [x] 3.2 对新建空笔记或空白内容默认自动激活聚焦，保障即点即写交互体验

## 4. 验证与发布

- [x] 4.1 运行 `flutter analyze --no-fatal-infos` 保证 0 错误
- [x] 4.2 运行回归测试套件验证工具栏与编辑器渲染正常且 0 异常
- [x] 4.3 构建 macOS Release 版本并重启应用验证
