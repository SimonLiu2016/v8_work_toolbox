# Tasks

## 1. NoteStore.addAttachment API

- [x] 1.1 `note_store.dart` 新增 `addAttachment(String noteId, File source) → Future<String>`：生成 attId、复制文件到 `attachmentsDir/<noteId>/attId_原名`、检测 MIME、写 attachments 表、返回 attId
- [x] 1.2 批量入口 `addAttachments(String noteId, List<File> files) → Future<List<String>>` 遍历调用 1.1
- [x] 1.3 单测：添加附件后 `attachmentsForNote` 返回含该条目；文件物理存在于 attachmentsDir；MIME 检测正确；原文件名保留；多文件批量添加

## 2. DOCX→Markdown 转换工具

- [x] 2.1 新建 `lib/tools/notebook/docx_to_markdown.dart`：解压 .docx → 读 `word/document.xml` → 映射标题/加粗/斜体/列表/表格为 Markdown，返回 Markdown 字符串
- [x] 2.2 降级处理：无法解析的元素降级为纯文本段落；空文档返回空字符串
- [x] 2.3 单测：含标题+加粗+列表+表格的 DOCX → Markdown 含对应语法；纯文本文档 → 无格式 Markdown

## 3. XLSX→Markdown 表格转换

- [x] 3.1 ~~`pubspec.yaml` 添加 `excel` 依赖~~ **偏离**：`excel` 最高版仅支持 `archive ^3.6.1`/`xml ^5.0.2`，与项目已有 `archive ^4.0.7`+`xml ^6.0.0` 冲突无法安装。改用已有的 `archive`+`xml` 包手写 XLSX 解析（XLSX 本质为 ZIP+XML）
- [x] 3.2 新建 `lib/tools/notebook/xlsx_to_markdown.dart`：解压 .xlsx → 解析 `sharedStrings.xml` 共享字符串表 + `workbook.xml` sheet 名 + `_rels` 映射 → 每个 sheet 生成 Markdown 表格 → 用 `## sheetName` 拼接
- [x] 3.3 大表截断：单 sheet 超 500 行截断 + 末尾追加 `> ⚠️ 表格过大，已截断至前 500 行`；管道符转义 `|` → `\|`
- [x] 3.4 单测（4 项全绿）：2×3 sheet → Markdown 表格正确；数值型单元格直接输出；管道符转义；600 行截断至 500

## 4. 多格式文档导入入口（UI + 分发）

- [x] 4.1 `notebook_page.dart` 将 `_importMarkdown` 扩展为 `_importDocuments`：FilePicker 支持 `['pdf','docx','xlsx','md','markdown','txt']` + `allowMultiple`
- [x] 4.2 导入选项面板：选完文件后弹对话框含 checkbox"保留原文件为附件"
- [x] 4.3 按扩展名分发：`.md/.markdown/.txt` → 直接读文本；`.docx` → `DocxToMarkdown.convert()`；`.pdf` → `PdfToMarkdown.convert()`（见第 10 组，已从"复用 reader 提纯文本"改为结构还原）；`.xlsx` → `XlsxToMarkdown.convert()`
- [x] 4.4 提取的 Markdown → `MarkdownConverter.markdownToDelta()` → `NoteStore.createNote()`；若"保留原文件"选中 → `addAttachment` + 追加附件块 + `updateNote`（见第 9 组）
- [x] 4.5 不支持格式 → SnackBar 提示支持列表

## 5. AppFlowy 自定义附件块

- [x] 5.1 新建 `lib/tools/notebook/ui/components/attachment_block_component.dart`：定义 AppFlowy Node type `'attachment'`，data 含 `attachmentId/filename/sizeBytes/mime`（不含路径——见第 8 组）
- [x] 5.2 渲染 widget：文件类型图标 + 文件名 + 人性化大小 + [在访达中显示] + [另存为] 按钮
- [x] 5.3 "在访达中显示"：`Process.run('open', ['-R', path])`；"另存为"：`FilePicker.platform.getDirectoryPath` + 复制
- [x] 5.4 附件不可用时渲染"附件不可用"占位，且不提供任何文件操作按钮
- [x] 5.5 编辑器注册自定义 block（参照 TableBlock/CodeBlock 注册模式）

## 6. 编辑器工具栏"添加附件"按钮

- [x] 6.1 `note_editor.dart` 工具栏新增 `IconButton(Icons.attach_file, '添加附件')`
- [x] 6.2 点击 → `FilePicker.pickFiles(allowMultiple: true)` → 对每个文件 `NoteStore.addAttachment(noteId, file)` → 在当前光标位置 `insertNode(AttachmentBlock)`
- [x] 6.3 插入后笔记自动保存（触发现有 autosave）

## 7. 验证

- [x] 7.1 相关测试套件全绿（addAttachment 4 项 / docx_to_markdown 6 项 / xlsx_to_markdown 4 项，共 14 项）
- [x] 7.2 手动验收（2026-09-19 部署后）：导入 .pdf 勾选"保留原文件为附件" → 附件可见（`_appendAttachmentBlock` 修复后正文含附件块入口）；添加附件按钮 → 附件块渲染且可操作。.docx/.xlsx 手动验收待后续样本。
- [x] 7.3 `openspec validate notebook-import-and-attachments --strict` 通过

## 8. 验收缺陷修复：附件引用完整性（C）

- [x] 8.1 `attachment_block_component.dart`：节点 data 不再写入 `localPath`；改为 StatefulWidget 在 `initState` 异步调 `NoteStore.attachmentById(attachmentId)` 解析路径
- [x] 8.2 legacy 兼容：查表失败时回退读取节点内缓存的 `localPath`（旧笔记仍可渲染）
- [x] 8.3 记录不存在且无缓存路径 → 渲染"附件不可用"占位，不提供任何文件操作按钮
- [x] 8.4 `note_editor.dart` `_addAttachments`：`AttachmentRef` 不再传原始 `localPath`
- [x] 8.5 `note_editor_toolbar.dart` `AttachmentRef` 移除 `localPath` 字段
- [x] 8.6 单测：查表成功→用表内路径；查表失败+有缓存→回退缓存；查表失败+无缓存→不可用态

## 9. 验收缺陷修复：导入保留原文件不可见（B）

- [x] 9.1 `notebook_page.dart` `_importDocuments`：keepOriginal 时在 `createNote` 后追加附件块并回写笔记内容
- [x] 9.2 新增辅助：解析 deltaJson → Document → 追加 `attachmentNode(attId, filename, sizeBytes)` → `documentToJson` → `updateNote`
- [x] 9.3 单测：导入保留原文件后，笔记内容含 attachment 类型节点且 attachmentId 与 DB 记录一致 —— **曾虚勾选**：勾定时无对应测试，实际 `doc.root.children.add()` 抛 `UnsupportedError` 导致该路径从未成功过（见第 11 组）。现由 `test/notebook_import_attach_test.dart` 覆盖。

## 10. PDF 结构还原（A2）

- [x] 10.1 新建 `lib/tools/notebook/pdf_to_markdown.dart`：JXA 逐页取 `attributedString`，按 effectiveRange 遍历 run 取 `NSFont.pointSize` + 文本
- [x] 10.2 统计正文字号（频次最高），按相对倍数映射标题层级（≥1.8→#，≥1.35→##，≥1.12→###，其余正文）
- [x] 10.3 噪声过滤：页首/页尾 2 行内的纯数字或罗马数字短行（页码）、页眉页脚重复行
- [x] 10.4 输出 Markdown（标题 + 段落，段落间空行），无文字层时抛明确异常
- [x] 10.5 `notebook_page.dart` `_extractPdfMarkdown` 改用 `PdfToMarkdown.convert`；捕获无文字层异常 → 提示可勾选保留原文件为附件
- [x] 10.6 单测：用真实 PDF（合成多字号文档）验证标题层级映射、页码过滤、段落分隔

## 11. 验收缺陷修复：导入失败 + 正文翻倍（2026-09-19）

真实 PDF（Seatrium 表单，2 页）验收发现四个缺陷。其中 11.1–11.3 为本组修复项；
PDF 布局还原（11.4）另立 change `notebook-pdf-layout-fidelity` 跟踪。

- [x] 11.1 `markdown_converter.dart` `_parseInlineMarkdown` 移除末尾 `lastEnd == 0` 的重复兜底
  - **根因**：无内联格式的行在循环内已 `add(text)`（`lastEnd` 此时仍为 0），
    末尾兜底 `if (lastEnd == 0) ops.add({'insert': text})` 又把整行追加一遍。
    实测 `'## H\n\n普通段落行\n'` → 5 ops 中含两遍 `普通段落行`；真实 PDF 导入的
    18 ops 里 5 个 text op 全部成对重复，正文长度翻倍。
  - **修法**：`lastEnd == 0` 时 `text.substring(0)` 已等于整行，兜底分支冗余，直接删除。
- [x] 11.2 附件节点追加改用 `Node.insert()`，不再 `doc.root.children.add()`
  - **根因**：`parseToDocument` 返回的 `root.children` 是 AppFlowy `Node` 的
    `_cacheChildren ??= _children.toList(growable: false)` 缓存快照，
    `.add()` 抛 `UnsupportedError: Cannot add to a fixed-length list`。
    该异常被 `_importDocuments` 外层 catch 吞掉 → 提示"已导入 0 篇，失败 1 篇"，
    而附件文件与 DB 记录均已成功写入，正文里却没有任何附件入口（用户看不到附件）。
  - **修法**：抽出共享入口 `AppFlowyCodec.appendAttachmentNode()`，用 `root.insert(node)`
    （AppFlowy 官方可变 API），`_appendAttachmentBlock` 委托给它。
- [x] 11.3 导入失败回滚已建笔记：`createNote` 先于附件追加执行，中途失败会留下
  正文残缺 + 孤儿附件的半成品笔记，但用户只见"失败 1 篇"。新增 `_rollbackFailedImport()`：
  `NoteStore.permanentlyDeleteNote()`（连带删附件文件与 DB 记录）+ 删 FTS 条目，
  使"失败"与数据库状态一致。回滚自身异常只 debugPrint，不再抛出。
- [x] 11.4 单测 `test/notebook_import_attach_test.dart`（7 项）：无格式单行只产生 1 个 text op；
  多行文档每行只出现一次；短表单标签不重复；含内联格式的行正确拆分且不重复；
  `appendAttachmentNode` 不抛异常且节点数 +1；附件节点位于末尾且元数据完整且不含 `localPath`；
  追加附件后原有正文完整保留。
- [x] 11.5 PDF 表单/多栏布局还原（表单项被粘成一行、`o ` 与 `• ` 符号丢失、`mailto:` 字面量泄露）
  → **已由 `notebook-pdf-layout-fidelity` change 处理**：真因重新定位（见该 change proposal），
  主凶是 `_reflowParagraphs` 的句末标点表缺英文句号（非"同字号合并"或"缺 x/y 坐标"），
  次要为粗体未被提取、私用区 bullet 未识别。该 change 已实现并部署验收。
  **残余**（富文本 `_Seg` 升级、`mailto:` 归一、字体回退噪声）留作后续可选 change。

