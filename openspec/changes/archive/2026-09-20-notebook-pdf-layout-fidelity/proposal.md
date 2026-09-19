## Why

`notebook-import-and-attachments` 的 PDF 导入已能还原**标题层级**（按 PDFKit 逐 run 的 `NSFont.pointSize` 推断），但真实表单类 PDF 验收发现布局还原仍有硬缺陷。用真实样本（Seatrium 用户 ID 申请表，2 页）定位后，根因**不是"缺坐标"，也不是"同字号合并"**——而是 `_reflowParagraphs` 的句末标点表不含英文句号。

字号推断本身做对了：该文档只有三种字号（15.96 / 11.04 / 9.96），bodySize=11.04，唯一的大标题 `WELCOME TO Seatrium` 被正确识别为 `##`。用户观察到"只有第一行是大标题"，因为**这份 PDF 里确实只有一个大标题**——其余标题靠的是粗体，而粗体从未被取过。

用真实 JXA 输出逐步回放后定位到主凶（详见 design.md 二轮验证）：

```
阶段               输出              是否正确
─────────────────────────────────────────────────────────────
JXA 提取            字符级 run        ✓ 字号/文本/\n 完整
_lines 构建          37 条独立行      ✓ 与原文档视觉换行一致
_blocksFromPage    同上（合并未跨 \n）  ✓ 非主凶
_reflowParagraphs   4 条巨块           ✗ ★主凶：句末标点表缺 '.'
```

**主凶**是 `_sentenceEnd = [。！？；：!?;:][”"）)\]】]*$` 不含 `.`。英文行几乎全部以 `.` 或无标点结尾，`canMerge` 因此几乎恒为真，整篇被并成 4 条巨块。第 1 条块保留了 `WELCOME TO Seatrium` 的 h2 层级，但它后面的所有内容都被并进同一个 level-2 块，渲染时全部作为标题正文输出——这正是"只有第一行是大标题"的直接来源。

**次要**是 `U+F0A8`（Wingdings 私用区，原文档的 checkbox 符号）未被 bullet 白名单覆盖，混入正文；三个 `•`（U+2022）被正确丢弃，但丢弃后丢失了列表语义。

**第三**是粗体从未被提取，导致 11.04/9.96 的加粗标题（`(A) Steps to Login`、`Note - Password Criteria` 等）全部降级为正文。

## What Changes

- **修正句末标点表（主修复）**：`_sentenceEnd` 补英文句号 `.`，仅当 `.` 后为空格或行尾时判句末，避免 `3.14`、`v.2` 误切。这是单点修复，恢复所有行级边界。
- **提取层补充粗体**：JXA 输出从 `[size, text]` 扩展为含 `bold`（由 fontName 判定），使下游可区分加粗的标题与加粗的标签。
- **标签 vs 标题判定**：基于粗体 + 冒号 + 章节标记前缀的规则集（design D4），简化为整行级判定。
- **bullet 前缀还原**：白名单补 `U+F0A8`（Wingdings 私用区）等码位；改为"有后续内容则补 `- ` 前缀，孤立则丢弃"，恢复列表语义而非丢弃。
- **降级原则不变**：无法可靠判定的结构降级为段落——宁可少还原，不可错还原。
- **不做**：富文本中间表示升级（D2 暂缓，整行加粗过渡足够）、x/y 坐标方案（D1 作废，字符级 run 下需重写 JXA 控制流且收益面窄）、字体回退单字符噪声（`CourierNewPSMT` 的 `o` ×3，保留原样）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `notebook-storage`：待"Import a PDF document with structural restoration"需求随
  `notebook-import-and-attachments` 归档落进主 specs 后，补正式 MODIFIED delta
  （补粗体/标签/章节层级与 bullet 还原要求）。当前 `.openspec.yaml` 设
  `skip_specs: true`——目标需求尚在该 change 的 delta 中、未落进主 specs，
  OpenSpec 不允许对未落地需求做 MODIFIED。见 tasks 第 7 组。

## Impact

- **代码**：`lib/tools/notebook/pdf_to_markdown.dart`——`_sentenceEnd`（补句号）、`_jxaScript`（取粗体）、`convertFromRuns`（解析新字段）、`_blocksFromPage`（行级粗体判定 + 标签/标题规则）、`_dropLoneBullets`（补私用区码位 + 语义恢复）、Markdown 渲染（行级加粗标记）。
- **依赖**：无新增。仍走现有 JXA → PDFKit 通道。
- **风险**：句末标点补入后影响中文文档的可能性低（中文以 `。` 为主，`.` 多为小数/版本号，且已限定"后接空格或行尾"）；标签/标题判定依赖冒号与章节标记，在不含这两类标记的文档上退化为纯加粗标记（不影响可读性）；bullet 语义恢复后原"丢弃符号"的测试断言需更新。
- **兼容**：输出仍是 Markdown → 下游 `markdownToDelta` 不变。字号推断标题层级、页码过滤保持。
- **不纳入**：两栏正文与复杂表格（需要 x/y 坐标，延后）；`.docx`/`.xlsx` 导入；图片型 PDF 的 OCR（扫描件仍走"保留原文件为附件"）；PDF 内图片抽取；富文本中间表示升级。
