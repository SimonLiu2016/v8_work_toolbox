## Why

用户要求对 pdf / excel / word / txt / csv / markdown 等类型的笔记附件提供**一键转换**：
把文件内的源语言翻译为目标语言，同时可选地把文件转成另一种目标格式，且要求
「内容格式和排版无变化」。

之所以拆成两个 change，是因为按「排版还原度」实测下来，36 个 (源 × 目标) 格子
分属三个量级：

```
◎ = 排版/图片零变化（原地替换文本节点，其余字节不动）     8 格
○ = 内容与图片保留，排版尽力还原                          19 格
✗ = 不提供（技术上做不到"排版无变化"，不假装能）            9 格
```

`notebook-attachment-preserve-and-document-translate` 负责让图片先能被笔记承载；
本 change 在此之上铺开转换矩阵。**两个 change 都明确要求不得遗漏任何一个 ◎ 与 ○
格子**——每条路径都要么交付、要么在 spec 里写明它归哪条 change 的哪一批，不允许
 silently 落格。

## What Changes

**引擎三段式：**

```
源文件 ─▶ 1. 解析为「内容模型」       段落/标题/列表/表格/单元格 + 图片引用与字节
            │
            ▼
         2. 翻译（可选）             AiService.instance.chat(slot: 'text')
                                      分批 + JSON 数组 + 进度回调
                                      （模式照搬影音播放器字幕翻译）
            │
            ▼
      ┌─────┴─────┬──────────────┐
      ▼           ▼              ▼
   3a 原地回写    3b 结构渲染     3c 扁平导出
   ◎ 路径        ○ 路径          txt/csv/md 类
```

**矩阵（36 格全清单，◎ 8 + ○ 19 + ✗ 9）：**

```
源＼目标   docx        pdf         md          txt         xlsx        csv
────────────────────────────────────────────────────────────────────────────
docx       ◎  原地     ○  渲染     ○  转换     ○  扁平     ✗           ✗
md         ○  渲染     ◎  原地     ○  转换     ○  扁平     ✗           ✗
txt        ◎  原地     ◎  原地     ◎  原地     ◎  原地     ✗           ✗
pdf        ✗          ○  渲染     ○  转换     ○  扁平     ✗           ✗
xlsx       ○  渲染     ○  渲染     ○  转换     ○  扁平     ◎  原地     ○  扁平
csv        ○  渲染     ○  渲染     ○  转换     ○  扁平     ○  渲染     ◎  原地
```

- **◎ 路径 = 真正兑现"排版无变化"**：docx→docx 只替换 `word/document.xml` 的
  `<w:t>` 文本节点，`word/media/` 一个字不动 → 图片/样式/表格天然保留；
  xlsx→xlsx 替换 `xl/sharedStrings.xml` 的 `<t>` 与 inlineStr；
  csv→csv 逐行重写；md/txt 同格式为规范化重写。
- **○ 路径 = 内容与图片保留、排版尽力还原**：docx→pdf / md→docx 等需引入
  目标格式写出器。**Dart 生态无 .docx / .xlsx 写出的主流库**，需自研 OOXML
  与 SpreadsheetML 模板；pdf 用已装的 `pdf` 包自排（坐标/分页/中文字体嵌入）。
- **✗ 路径不进 UI**：选 docx 源时，目标下拉只出现 pdf/md/txt，看不到 xlsx/csv。
  不提供的能力不出现，而不是提供了再报错。
  - `pdf → docx` 需要版式识别（列/表格/图），学术级问题
  - `pdf → pdf` 改文本会破坏 xref 交叉引用表，实际须整体重排
  - `* → xlsx/csv` 的语义错配（把散文灌进表格没有意义）
- **翻译与格式解耦**：可只翻译不转格式（docx→docx），也可翻译 + 转格式
  （docx→pdf），也可只转格式不翻译（docx→md）。
- **输出命名与落点**：产物保存为新的 attachment，不覆盖原附件；
  命名带 `_zh-CN` / `_to-pdf` 之类后缀便于识别。

**非目标：**
- 不做 OCR（扫描版 PDF 提取不出文本层，需先解决文字识别，另立 change）。
- 不保证 ○ 路径的排版"无变化"——spec 中的验收标准是"内容与图片不丢、
  排版不劣于导入时"。
- 不使用 LibreOffice / pandoc 外部引擎（本机未装、用户机器不保证有、
  随 App 分发 400MB+ 不现实）。
- 不动 `notebook-attachment-preserve-and-document-translate` 已交付的图片保真。

## Capabilities

### New Capabilities

- `document-conversion-matrix`: 定义 (源格式 × 目标格式) 转换矩阵的完整性与
  还原度分级——哪些组合必须可用、每个组合承诺保留什么、以及不提供的组合
  如何在 UI 中缺席。

### Modified Capabilities

- `notebook-tool`: 附件获得「一键转换」入口，行为受矩阵约束。

## Impact

**代码 — 新增（预计）：**

| 模块 | 职责 |
|---|---|
| `lib/tools/notebook/convert/document_model.dart` | 内容模型（段落/标题/列表/表格/单元格/图片引用） |
| `lib/tools/notebook/convert/translator.dart` | 复用 `AiService.chat('text')`，分批 + JSON + 进度 |
| `lib/tools/notebook/convert/ooxml_rewriter.dart` | ◎ 路径：docx 原地回写 `<w:t>` |
| `lib/tools/notebook/convert/spreadsheetml_rewriter.dart` | ◎ 路径：xlsx 原地回写 |
| `lib/tools/notebook/convert/docx_writer.dart` | ○ 路径：OOXML 生成 |
| `lib/tools/notebook/convert/pdf_writer.dart` | ○ 路径：基于 `pdf` 包自排 |
| `lib/tools/notebook/convert/flatten.dart` | ○/◎：md / txt / csv 扁平导出 |
| `lib/tools/notebook/convert/matrix.dart` | 矩阵定义 + UI 可选目标推导（✗ 格子不进下拉） |

**代码 — 改动：**

| 文件 | 改动 |
|---|---|
| `lib/tools/notebook/ui/components/attachment_block_component.dart` | 附件操作区加「转换」入口 |
| `lib/tools/notebook/ui/notebook_page.dart` | 转换结果写回为 attachment |

**依赖：** 不新增 pub 依赖（`archive` / `xml` / `pdf` 已在）。

**风险：** ○ 路径的 OOXML 写出器是本 change 最大工作量；若交付压力大，
可把 ○ 中「*→pdf」与「*→docx」拆成后续 change，但**必须在 spec 中显式登记
其归属**，不允许静默落格。
