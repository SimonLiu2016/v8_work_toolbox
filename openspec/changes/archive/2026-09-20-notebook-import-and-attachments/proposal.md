## Why

笔记本功能当前只支持 Markdown 文件导入（`.md/.txt`），无法从 PDF/Word/Excel 等常见文档格式导入生成笔记——尽管同项目的"文档语音朗读"模块已有 `DocumentParser` 支持 PDF/DOCX 解析能力，notebook 未复用。同时，笔记附件数据模型（`attachments` 表、`attachmentsDir`、删除/导出附件逻辑）已存在，但缺少"在笔记内添加附件"的 API 与 UI 入口——用户只能在 Evernote 导入时被动获得附件，无法主动为笔记添加任意文件作为附件。

## What Changes

- **文件导入生成笔记（功能①）**：笔记本页面"导入"入口扩展，支持 `.pdf/.docx/.xlsx/.md/.txt` 四类格式。PDF/DOCX 复用 reader 模块的 `DocumentParser` 提取文本；DOCX 额外引入 docx→Markdown 转换以尽量保留原有格式（标题、加粗、列表、表格）；XLSX 引入 Excel 解析将每个 sheet 转为 Markdown 表格拼入正文。提取的 Markdown 经现有 `MarkdownConverter.markdownToDelta()` 转为 AppFlowy 文档块。导入时默认不保留原文件，用户可勾选"保留原文件为附件"将原始文档作为附件存储到该笔记。
- **笔记内添加附件（功能②）**：`NoteStore` 新增 `addAttachment(noteId, file)` API——复制文件到 `attachmentsDir/<noteId>/`、写 `attachments` 表。编辑器工具栏新增"添加附件"按钮，支持多选文件；附件在编辑器内以自定义 AppFlowy 附件块呈现（文件名 + 大小 + 下载/打开按钮），点击可打开或另存为。
- **自定义附件块**：AppFlowy 编辑器新增自定义 `AttachmentBlock`——渲染文件名、文件大小、文件类型图标，带"在访达中显示"和"另存为"操作。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `notebook-editor`: 新增自定义附件块渲染需求（AttachmentBlock：文件名/大小/图标/可点击操作）。
- `notebook-storage`: 修改"Attachment storage"需求，补充用户主动添加附件的 API 与多文件支持；新增"多格式文档导入"需求（PDF/DOCX/XLSX/MD 提取文本生成笔记 + 可选保留原文件为附件）。

## Impact

- **代码**：`lib/tools/notebook/ui/notebook_page.dart`（导入入口扩展支持多格式 + 导入时保留原文件选项）；`lib/tools/notebook/note_store.dart`（`addAttachment` API）；`lib/tools/notebook/ui/note_editor.dart`（附件块渲染 + 工具栏"添加附件"按钮）；新增 docx→Markdown 转换与 xlsx→Markdown 表格转换工具；AppFlowy 自定义 block 注册。
- **依赖**：新增 Excel 解析包（如 `excel` 或 `spreadsheet_decoder`）；DOCX→Markdown 可能需新包或手写 XML→Markdown 映射（reader 的 `_parseDocx` 只提纯文本，格式丢失）。
- **行为兼容**：现有 Markdown 导入路径零变化（新增格式是纯增量）；附件表结构与存储路径不变，仅新增写入入口。无 BREAKING。
