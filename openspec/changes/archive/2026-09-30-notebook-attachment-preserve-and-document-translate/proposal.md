## Why

「笔记本 → 导入文档」导入 Word 后，正文进来了但**图片全部丢失**。实测定位到两层缺失，不是一处 bug：

1. `lib/tools/notebook/docx_to_markdown.dart` 全文不解析图片——`word/media/` 里的
   二进制被直接丢弃，产出的 markdown 连 `![](...)` 都没有。
2. 即使抽出图片，笔记当前也没有承载它的地方：附件块
   （`attachment_block_component.dart`）只渲染图标 + 文件名，从不内联显示图片；
   编辑器真正的图片节点走的是另一套 `ImageBlockKeys.url` 机制。

同一批导入路径上，`xlsx` / `pdf` 的图片与版式细节也有同类损耗，但文档类型里
内嵌图片的高频场景是 docx，故本次以 docx 为主，其余格式按同一机制顺带覆盖。

本 change 是 `document-format-conversion-matrix` 的前置：那条 change 的
◎（排版零变化）路径要求"图片先能被笔记承载"，否则转换结果仍然无处安放。

## What Changes

- **docx 解析提取图片**：解包 `word/media/*`，按 `document.xml` 中
  `<a:blip r:embed="rIdX">` + `word/_rels/document.xml.rels` 的关系表，
  在正文对应位置产出图片引用（而不是把图片挤到文末）。
- **图片经附件机制落库**：图片字节写入 `attachments/<noteId>/`，正文写入
  指向该 `attachmentId` 的节点——与现有 `addAttachment` 同一条路，
  比 base64 内联更省 delta 体积，也让"保留原文件为附件"的图片与解析出的图片
  共用一套寻址方式。
- **附件块支持图片内联渲染**：附件节点带 `mime: image/*` 时渲染缩略图 preview
  （点击可查看原图），非图片附ables保持现有图标 + 文件名形态不变。
- **pdf 图片同样纳入**：`pdf_to_markdown` 侧按页面提取嵌入图片，走同一附件机制。
- **不引入新依赖**：图片提取用已有的 `archive` 包 + XML 解析。

**非目标：**
- 不做任何格式转换或翻译（那是 `document-format-conversion-matrix`）。
- 不改 docx 的文本/表格/列表解析质量（现状已覆盖）。
- 不引入图片压缩或尺寸归一化（保持原图，后续如需优化另立 change）。

## Capabilities

### New Capabilities

- `notebook-document-image-fidelity`: 定义文档导入时内嵌图片的保真契约——图片
  必须按其在原文中的位置进入笔记，且以附件形式持久化，不再是"导入即丢弃"。

### Modified Capabilities

- `notebook-tool`: 补充「导入文档时内嵌图片不得丢失」的约束。
- `app-shell`: 无需求变更。此处列出仅说明已核查其不受影响。

## Impact

**代码：**

| 文件 | 改动 |
|---|---|
| `lib/tools/notebook/docx_to_markdown.dart` | 解析 `word/media/*` 与 `document.xml` 的 blip 引用，产出带位置的图片标记 |
| `lib/tools/notebook/pdf_to_markdown.dart` | 提取页面嵌入图片，产出图片标记 |
| `lib/tools/notebook/ui/notebook_page.dart` | `_importDocuments` 把图片标记转为附件节点 |
| `lib/tools/notebook/note_store.dart` | 图片附件写入（复用现有 `addAttachment`，必要时补图片变体） |
| `lib/tools/notebook/ui/components/attachment_block_component.dart` | `mime: image/*` 时渲染预览 |

**测试：**
- 新增 fixture docx（含 2 张图，正文中间 + 文末各一），断言图片数与位置顺序
- 新增附件块图片渲染的 widget 测试
- 回归既有 `test/docx_to_markdown_test.dart` / `test/xlsx_to_markdown_test.dart`

**不变更：**
- 笔记的 delta 结构（沿用现有 attachment / image 节点类型）
- `attachments` 表结构
- 任何业务的 API、存储格式
