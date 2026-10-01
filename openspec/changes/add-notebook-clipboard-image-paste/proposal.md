## Why

笔记本里按 `⌘V` 粘贴剪贴板图片（微信截图等）完全没有反应。根因不是"没实现"：`note_editor.dart` 里的 `_handlePaste()` 逻辑完整——探测剪贴板位图、存附件、插正文都有——但它绑在 `CallbackShortcuts` 上，而 `AppFlowyEditor` 用自己的 `Focus(onKeyEvent:)` 在同一焦点节点上更早接到 `⌘V`、返回 `handled` 就终止分发。**这段图片粘贴代码从写下来那刻起一次都没执行过**，且没有任何报错或提示，所以一直没人发现。

同一个失效模式还波及所有粘贴：`AppFlowyClipboard.getData()` 只读 `kTextPlain`，`html` 恒为 `null`，包内的 `pasteHtml` 分支是死代码；剪贴板里只有图片没有文本时，包的 handler 什么都不做却返回 `handled`——按键被吃掉，外层的 `.duplicate` 绑定形同虚设。

## What Changes

- **接管编辑器的粘贴命令**：给 `AppFlowyEditor` 显式传 `commandShortcutEvents`，从 `standardCommandShortcutEvents` 中滤掉 `pasteCommand` / `pasteTextWithoutFormattingCommand`，换成自己的处理器。接管后文字粘贴行为由我们负责，必须逐条对齐包原有的 `pastePlainText` 表现（URL/电话识别、多行拆分、选区属性继承、选中区替换），否则修图片粘贴会顺手弄坏文字粘贴。
- **剪贴板位图 → 正文图片块**：读取 macOS 剪贴板的位图表示（`osascript` + `class PNGf`），经 `NoteStore.saveAttachment` 落盘，以 `imageNode` 插入正文。**存储位置、插入方式、渲染路径与「插入图片」按钮完全一致**——不是附件卡片、不是外链、不落 `/tmp`。
- **浏览器「复制图片」→ 同样支持**：剪贴板无位图但文本是 `http(s)` 图片 URL 时，下载后走同一条落盘与插入路径。任意软件一视同仁：抓的是剪贴板表示而非来源标记，微信 / QQ / `⇧⌘4` / Preview 复制天然覆盖。
- **显式入口**：工具栏新增「粘贴图片」按钮。最常用的功能不该只有一条会被人抢走的隐形路径——三个月无人发现正是这个教训；将来升级 `appflowy_editor` 时它也是兜底。
- **失败必须可见**：位图读不出、下载失败、超出体积上限、落盘失败，都以 snackbar 说明是哪一步。静默失败是这次 bug 能藏住的直接原因。**例外**：剪贴板里压根没有图片时保持静默并按纯文本粘贴——那是一次普通的粘文字，不是失败。

## Capabilities

### New Capabilities

- `notebook-clipboard-image-paste`: 从剪贴板粘贴图片进笔记——位图与图片 URL 两类来源、与「插入图片」按钮同构的存储与渲染、接管粘贴命令后的文字粘贴不退化、以及每一步失败的可见反馈。

### Modified Capabilities

- `notebook-editor`: 编辑器获得剪贴板图片粘贴能力（快捷键 + 工具栏按钮）；同时明确接管粘贴命令后，纯文本粘贴的行为不得退化。

## Impact

- **Flutter 层**：`lib/tools/notebook/ui/note_editor.dart`（接管 `commandShortcutEvents`、重写 `_handlePaste`、接入 snackbar 反馈）、`lib/tools/notebook/ui/components/note_editor_toolbar.dart`（「粘贴图片」按钮）、新增 `lib/tools/notebook/services/clipboard_image_service.dart`（剪贴板位图探测 + URL 下载，独立于 widget 便于测试）。
- **不再依赖**：`note_editor.dart:573` 的 `CallbackShortcuts` 绑定将被替换——它是当前失效的直接原因，留着会误导后来者以为 `⌘V` 已接线。
- **依赖**：无新增第三方包。剪贴板位图走 `osascript`（项目已有 macOS 依赖），下载走 `package:http`（已在依赖中）。
- **数据**：图片存储复用既有 `NoteStore.saveAttachment`（`attachmentsDir/<id><ext>` 扁平 + attachments 表记录），**无 schema 变更、无迁移**。
- **非目标**：不做尺寸缩放或体积上限（用户明确不要求）；不做拖拽图片进编辑器；不做多图批量粘贴（剪贴板位图通常单张）。
