## Context

「笔记本 → 导入文档」导入 Word 后正文进来了但图片全丢。定位到两层缺失：
`docx_to_markdown.dart` 完全不解析图片（`word/media/` 二进制被丢弃），且附件块
从不内联渲染图片（只给图标 + 文件名）。详见 `proposal.md` — Why。

`document-format-conversion-matrix` 的 T1/T2 路径要求"图片先能被笔记承载"，
否则转换产物无处安放，故本 change 是其前置。

## Goals / Non-Goals

**Goals:**
- docx 的每张嵌入图片都进入笔记，且**在原文对应位置**（不是挤到文末）。
- 图片经现有 `addAttachment` 机制落库，正文用 attachmentId 引用（不 base64）。
- 附件块 `mime: image/*` 时渲染预览；非图片形态不变。
- pdf 嵌入图片按同一机制纳入。
- 无法提取的图片明确报告计数，不静默完成。

**Non-Goals:**
- 不做任何格式转换或翻译（那是 `document-format-conversion-matrix`）。
- 不改 docx 的文本/表格/列表解析质量。
- 不做图片压缩或尺寸归一化（保持原图）。

## Decisions

### 1. 图片走 attachmentId 引用，不 base64 内联

- **Decision**：图片字节写入 `attachments/<noteId>/`，正文节点持 `attachmentId`。
- **Rationale**：`addAttachment` 已存在且被"保留原文件为附件"使用，同一机制
  意味着两处图片共用一套寻址与清理逻辑。base64 内联会让 delta 体积暴涨
  （一张 500KB 图 → 667KB 文本），笔记列表加载与 FTS 都会受拖累。
- **Alternatives Considered**：base64 直接进 delta。否决——体积与性能都不划算。

### 2. 位置 fidelity：按 `<w:p>` 段落扫描 `<a:blip>`

- **Decision**：解析按段落进行，遇到 `<a:blip r:embed="rIdX">` 就在该段落位置
  插入图片节点，而不是全文扫完图片统一追加。
- **Rationale**：`docx_to_markdown` 现有结构已是"按 `<w:p>` 分块逐段转换"
  （`_extractParagraphs` + `_convertParagraph`），在段落级插入是自然延伸，
  改动面小。rId 需经 `word/_rels/document.xml.rels` 映射到 `word/media/*`。
- **Trade-off**：浮动图片（`<wp:anchor>`，文字环绕型）没有确定段落位置，
  按"其 XML 出现处所属段落"近似处理；已在 spec 的场景中表述为
  "position corresponding to its anchor"而非"逐像素一致"。

### 3. 附件块预览用缩略图，点击看原图

- **Decision**：块内渲染缩略（约束高度 + 等比），点击后用现有图片查看路径打开原图。
- **Rationale**：附件块嵌在长笔记流里，原图直显会把版面冲散。缩略 + 可放大
  兼顾可扫读性与完整性。
- **Trade-off**：缩略需在 build 时解码——同一张图重复解码的开销可接受
  （附件块通常一屏内少量），若后续 profiling 发现问题再加缓存。

### 4. pdf 图片按页提取，不与文本层强耦合

- **Decision**：按页提取嵌入图片对象，按页码顺序插入正文图片节点。
- **Rationale**：现有 `pdf_to_markdown` 已按页走 PDFKit 的 `attributedString`，
  页码是现成的顺序锚点；无需建立"图片-文本"的精确位置关系。
- **Trade-off**：pdf 里图片与文本的相对位置只能到"页"这一级，
  比 docx 的"段落"级粗。spec 的场景相应表述为"extracted per page and
  referenced from the note body"。

## Risks / Trade-offs

- **[Risk] `<a:blip>` 的 rId 在 rels 里找不到**（文档损坏或非常规生成）：
  → *Mitigation*：缺失关系的图片跳过并计入"无法提取"计数，最终报告给用户，
    不静默丢弃（对应 spec 的 unrecoverable 场景）。

- **[Risk] `/XRef` + `/ObjStm` 并存时漏抓图片**（spec 原措辞过于悲观）：
  实测用户提供的真实 PDF（PDF 1.7，`/XRef` 与 `/ObjStm` 并存）上，全文扫描
  直接命中全部 81 个 obj，图片 obj 均可见——带大流的图片通常不进 ObjStm。
  影响有限，但**未在其它生成器上验证**，仍按 unrecoverable 计数兜底。

- **[Risk] 图片体积过大拖累笔记**：
  → *Mitigation*：本 change 不做压缩（Non-Goals），但附件机制天然是"按需加载"
    的文件而非 delta 内容，影响已被限制在"块内缩略图解码"这一处。

- **[Risk] 附件块改预览后，既有含附件的老笔记外观变化**：
  → *Mitigation*：仅 `mime: image/*` 分支改变；非图片附件走原路径。
    测试覆盖两条分支，且 mime 为空的老附件按非图片处理。

- **[Trade-off] docx 段落级位置 fidelity 不覆盖浮动图片**：
  → *Mitigation*：已知限制，spec 措辞已避开"逐像素一致"的绝对承诺。

## Migration Plan

1. 先建 fixture 与断言图片数/顺序的测试（此时红——提取能力不存在）。
2. 实现 docx 图片提取（media + rels + blip 三段）。
3. 接入 `_importDocuments` 的落库与正文引用。
4. 附件块预览渲染。
5. pdf 侧按页提取。
6. 全量验证 + 部署。
7. 回滚策略：图片提取可整体关停（退回"仅文本"行为），
   因改动集中在 `_extractMarkdown` 之后的新增步骤，不牵动既有解析路径。

## Open Questions

（无。位置 fidelity 的粒度已由 docx 段落级 / pdf 页码级的现状决定，
spec 措辞相应留有余地而不做绝对承诺。）
