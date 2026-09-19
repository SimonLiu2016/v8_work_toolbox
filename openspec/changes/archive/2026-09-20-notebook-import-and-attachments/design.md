## Context

当前状态（动机见 proposal.md）：

- **Markdown 导入已存在**：`notebook_page._importMarkdown()`（`:304-331`）用 `FilePicker` 选 `.md/.markdown/.txt`，读文本 → `MarkdownConverter.markdownToDelta()` → `NoteStore.createNote()`。仅限 Markdown。
- **多格式解析在 reader 模块**：`DocumentParser.parseFile()`（`reader/services/document_parser.dart:292`）支持 `.txt/.md/.docx/.pdf/.epub`，返回 `ReadingDocument`（含 chunks）。**DOCX 走 XML 纯文本提取**（`:387-408`），不保留格式——标题/加粗/列表/表格全丢。
- **附件数据层齐备**：`attachments` 表（`id/noteId/filename/mime/localPath/createdAt`）；`NoteStore.attachmentsForNote()`（`:330`）；`attachmentsDir` 已建好（`note_store.dart:27`）；删除笔记连带删附件（`:247-249`）；导出附件到文件夹（`:342+`）。**缺 `addAttachment` 写入 API**。
- **AppFlowy 自定义 block**：编辑器基于 `appflowy_editor`，已有自定义 `TableBlock`、`CodeBlock`——附件块参照同一模式注册。
- **Excel 解析**：项目中无 `.xlsx` 解析依赖。

## Goals / Non-Goals

**Goals:**

- 导入 `.pdf/.docx/.xlsx/.md/.txt` 生成笔记，DOCX 尽量保留格式。
- 用户能在打开的笔记内添加任意文件作为附件，附件以可交互的块呈现。
- 导入时可选保留原文件为附件。
- 复用已有附件数据层与存储路径，不新建表。

**Non-Goals:**

- 不做 `.pptx/.rtf/.epub` 导入（reader 的 epub 解析可后续复用，本期不纳入）。
- 不做附件预览（只支持"在访达中显示"和"另存为"，不在编辑器内渲染文件内容）。
- 不做附件的全文搜索索引。
- 不改 Evernote 导入流程（它有自己的附件创建路径，保持不变）。

## Decisions

### D1: DOCX→Markdown 转换用独立工具函数，不直接复用 reader 的 _parseDocx

reader 的 `_parseDocx` 提取纯文本（格式丢失），不满足"尽量保留格式"。新建 `lib/tools/notebook/docx_to_markdown.dart`，解析 DOCX 的 `word/document.xml`，映射：

```
  Word XML 元素          → Markdown
  ═══════════════════════════════════════
  <w:p> with Heading style → ## 标题
  <w:r><w:b>              → **bold**
  <w:r><w:i>              → *italic*
  <w:numPr>               → - 列表项
  <w:tbl>                 → Markdown 表格
  普通段落                 → 纯文本段
```

**为什么不用现成包**：`docx_to_markdown` 类的 pub 包维护不稳定/依赖重；DOCX XML 结构相对可预测，手写映射更可控。若实现时发现复杂边界（嵌套表格、合并单元格）可降级为纯文本 + "格式未完全保留"提示。

### D2: PDF 导入用独立转换器 + PDFKit 字号推断结构（不用 reader 的 _parsePdf）

**修订说明**：初版设计复用 reader 的 `_parsePdf` 提取纯文本，验收发现丢失全部结构，用户要求"可直接在笔记中复制想要的内容"——纯文本流不可用。改为独立转换器。

`reader/services/document_parser.dart:_parsePdf` 走 `PDFKit` 的 `doc.string`，返回**扁平纯文本**（无字号/段落信息），且随后被 `ParagraphChunker` 按 TTS 需要重新切句，结构进一步打散。不可复用。

新建 `lib/tools/notebook/pdf_to_markdown.dart`，仍走 macOS PDFKit（项目已有 JXA 通道），但改为读**逐 run 的排版属性**：

```
  pdf_to_markdown.dart 提取流程
  ════════════════════════════════════════════════════════
  1. JXA 逐页取 page.attributedString
  2. 按 effectiveRange 遍历 run，取 NSFont.pointSize + 文本
  3. 统计正文字号 = 出现频次最高的字号
  4. 相对字号 → 标题层级映射
        ≥ 正文字号 × 1.8  → #     （文档标题）
        ≥ × 1.35         → ##
        ≥ × 1.12         → ###
        其余             → 正文段落
  5. 噪声过滤：孤立纯数字行（页码）、页眉页脚重复行
  6. 输出 Markdown（标题 + 段落，段落间空行分隔）
```

**实测验证**（AI_System_Access_Control_Specification.pdf）：
```
  22pt  → "AI智能查询系统多数据源权限控制系统"   H1
  15pt  → "第二部分：系统架构与技术设计文档"      H2
  12pt  → "业务目标"                            H2
  10.5pt → 正文                                  body
  9.5pt → "CREATE VIEW v_sales_data..."          code
  9pt   → " 2"                                  页码（过滤）
```
字号分层清晰，映射可行。

**为什么不用其他方案**：
- `pdftotext -layout`（poppler）：引入外部二进制依赖，且输出是等宽排版而非 Markdown
- 页面渲染为图片嵌入：视觉保真但笔记体积暴增、文字不可复制——与用户"想复制内容"的目标相反
- 表格还原：PDF 表格结构还原是公认难题（无表格语义，仅线条与位置），本期不做，降级为普通段落

**降级**：纯扫描件（无文字层）→ 明确报错并提示可勾选"保留原文件为附件"。

### D2b: 附件块不缓存文件路径，按 attachmentId 查表解析（修订 D5）

**修订说明**：初版让节点 data 缓存 `localPath`，实现时误把**原始文件路径**写入（而非复制后的路径），导致用户删除桌面原文件后附件块失效。

结构化修复：**节点不再是路径的真相来源**。

```
  节点 data（修订后）
  ════════════════════════════════════════════════════════
  {
    attachmentId: 'att_xxx',   ← 唯一身份
    filename: 'report.pdf',    ← 仅用于首帧显示
    sizeBytes: 1234567,
    mime: 'application/pdf',
  }
  不含 localPath

  渲染时：NoteStore.attachmentById(attachmentId) → local_path
  → attachments 表是路径的唯一真相
```

**为什么**：两份真相（DB 记录 + 节点缓存）必然漂移。改为单一真相后，"引用原始路径"这个 bug 在结构上不可能再发生；附件目录迁移、换机恢复也能自动跟随。

**兼容**：早期版本已写入带 `localPath` 的节点——渲染时优先查表，查不到再回退节点内缓存的路径（legacy fallback），保证旧笔记仍可渲染。

### D3: XLSX→Markdown 表格用 `excel` 包

新增 `excel`（pub.dev）依赖解析 `.xlsx`。每个 sheet 遍历行列，生成 Markdown 表格：

```markdown
## Sheet1

| A1 | B1 | C1 |
|---|---|---|
| A2 | B2 | C2 |

## Sheet2
...
```

空 cell 用空字符串，合并单元格取左上值填入（简化处理）。

### D4: addAttachment API 放 NoteStore，复制文件到 attachmentsDir/<noteId>/

```
  NoteStore.addAttachment(String noteId, File source)
  ════════════════════════════════════════════════════
  final attId = uuid
  final destDir = Directory(p.join(attachmentsDir, noteId))
  await destDir.create(recursive: true)
  final destPath = p.join(destDir.path, '$attId_${source.basename}')
  await source.copy(destPath)
  final mime = lookupMimeType(source.path)
  await _db.insertAttachment(Attachment(id: attId, noteId: noteId, filename: source.basename, mime: mime, localPath: destPath, createdAt: now))
  return attId
```

**为什么 `attId_` 前缀**：防原文件名冲突（两个同名文件附件）。

### D5: AttachmentBlock 作为 AppFlowy 自定义 Node

参照现有 `TableBlock`/`CodeBlock` 的注册模式：

```
  AttachmentBlock Node 结构
  ════════════════════════════════════════════════════
  type: 'attachment'
  data: {
    attachmentId: 'att_xxx',   ← 关联 attachments 表
    filename: 'report.pdf',
    sizeBytes: 1234567,
    mime: 'application/pdf',
  }
  
  渲染:
  ┌──────────────────────────────────────────┐
  │ 📄 report.pdf            1.2 MB          │
  │ [在访达中显示]  [另存为]                   │
  └──────────────────────────────────────────┘
```

编辑器 toolbar 加 `IconButton(Icons.attach_file, '添加附件')` → `FilePicker.pickFiles(allowMultiple: true)` → 对每个文件 `addAttachment` + 在当前光标位置 `insertNode(AttachmentBlock)`。

### D6: 导入入口扩展为统一"导入文档"，支持多格式 + 保留原文件选项

现有 `_importMarkdown` 扩展为 `_importDocuments`：

```
  FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'docx', 'xlsx', 'md', 'markdown', 'txt'],
    allowMultiple: true,
  )
  → 弹一个导入选项面板（多选文件 + checkbox "保留原文件为附件"）
  → 按扩展名分发到对应解析器
  → MarkdownConverter.markdownToDelta(markdownContent)
  → NoteStore.createNote(...) → noteId
  → 若 checkbox 选中:
       attId = addAttachment(noteId, originalFile)
       → 解析 deltaJson 为 Document，追加 attachmentNode(attId)，
         documentToJson 回写
       → updateNote(noteId, deltaJson: 更新后内容)
```

**修订说明（B）**：初版只调用 `addAttachment` 建了 DB 记录与磁盘副本，**没有把附件块写进文档**，导致用户勾选"保留原文件"后在笔记里看不到任何入口。修订后必须把附件块追加进笔记正文。

先建笔记再追加块（而非先组块再建笔记），因为 `addAttachment` 需要 noteId——鸡生蛋问题的解是分两步：createNote → addAttachment → updateNote。

**修订说明（D，2026-09-19 真实 PDF 验收）**：初版实现两处缺陷导致该路径从未真正成功过。

- **追加块抛异常**：`_appendAttachmentBlock` 原写 `doc.root.children.add(...)`。但 `parseToDocument` 返回的 `root.children` 是 AppFlowy `Node` 内部 `_children.toList(growable: false)` 的缓存快照，`.add()` 抛 `UnsupportedError: Cannot add to a fixed-length list`。该异常被 `_importDocuments` 的外层 `catch (e)` 吞掉，表现为"已导入 0 篇，失败 1 篇"——而附件文件与 DB 记录其实都已写入成功，只有正文里没有附件入口。改用官方可变 API `Node.insert(node)`，并抽出共享入口 `AppFlowyCodec.appendAttachmentNode()`，供导入与编辑器工具栏复用。
- **半成品笔记**：`createNote` 先于附件追加执行，异常路径下留下正文残缺 + 孤儿附件的笔记，用户只看到"失败"。现由 `_rollbackFailedImport()` 在 catch 内彻底删除（`NoteStore.permanentlyDeleteNote` 连带删附件文件与记录，再删 FTS 条目），使失败提示与数据库状态一致。

**另（E，影响 Markdown 导入全路径）**：`_parseInlineMarkdown` 末尾的 `if (lastEnd == 0) ops.add(...)` 兜底导致无内联格式的行被完整追加两遍——循环内已 add，兜底又 add 一次（此时 `lastEnd` 仍为 0）。合成 `'## H\n\n普通段落行\n'` 即可复现。兜底分支冗余（`lastEnd == 0` 时 `substring(0)` 已覆盖整行），直接删除。

## Risks / Trade-offs

- [DOCX 格式映射不全——复杂表格/合并单元格/图片丢失] → D1 降级策略：无法转换的元素降级为纯文本，附"格式未完全保留"提示；用户可导入后手动调整。
- [Excel 大表格生成巨型 Markdown 表格导致编辑器卡顿] → 限制单 sheet 行数（如超过 500 行截断 + "表格过大已截断"提示）。
- [附件文件名冲突] → D4 用 `attId_` 前缀防冲突。
- [PDF 字号映射误判——例如封面大字被当正文、图表标注被当标题] → 按"相对正文字号"分层而非绝对字号；正文取频次最高者，避免少数大字号拉偏基线；无法判别时降级为段落（宁可少标题，不可错标题）。
- [PDF 噪声过滤误删正文（如正文中孤立的数字行）] → 页码过滤限定"位于页首/页尾 2 行内 + 纯数字/罗马数字 + 长度 < 10"三重条件叠加，降低误删概率。
- [扫描件无文字层] → 明确报错 + 提示"可勾选保留原文件为附件"，引导到可用路径而非静默产出空笔记。
- [旧笔记中已存在的附件块（带缓存 localPath）] → 渲染时优先按 attachmentId 查表；查不到再回退节点内 `localPath`（legacy fallback），保证旧笔记不白屏。
- [新增 `excel` 包依赖体积] → **未采用**：`excel` 与项目 `archive ^4.0.7`/`xml ^6.0.0` 版本冲突无法安装，改用已有包手写解析（见 tasks 3.1 记录）。

## Migration Plan

- 无需数据迁移。附件表无 schema 变更；`updateNote` 与 codec 的 `parseToDocument`/`documentToJson` 均为现有 API。
- 旧笔记中的附件块按 legacy fallback 继续渲染；用户重新添加一次附件即升级为查表模式。
- 回滚 = revert 代码，无状态残留。
