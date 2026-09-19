## Context

现有提取链路（`lib/tools/notebook/pdf_to_markdown.dart`）：

```
osascript -l JavaScript（JXA）
  └─ PDFDocument.attributedString（逐页）
       └─ attributes(at:, effectiveRange:) 遍历 run
            └─ [NSFont.pointSize, text]  ← 只有这两项
         ↓ JSON
PdfToMarkdown.convertFromRuns(pages)
  ├─ 统计正文字号（字符数加权）→ 相对倍数映射标题层级
  ├─ _blocksFromPage：run 按 \n 拆行 → 合并同字号片段 → 页码过滤
  ├─ _reflowParagraphs：连续正文行按句末标点回流成段落
  ├─ _dropLoneBullets：丢弃孤立符号行
  └─ 渲染 Markdown（标题 + 段落）
```

提取层输出已验证正确（Swift 直连 PDFKit 复现同样 run，带 `\n` 与字号）。字号推断在真实样本上工作正常。

**真实样本**：Seatrium 用户 ID 申请表，2 页，49 run，三种字号（15.96 / 11.04 / 9.96）。字体分布：

```
Arial-BoldMT        17 runs  282 字符
ArialMT             17 runs  475 字符
Helvetica           11 runs  775 字符   ← 含 bullet 符号
CourierNewPSMT       3 runs    3 字符   ← 'o' ×3，字体回退噪声
TimesNewRomanPSMT    1 run    43 字符   ← mailto:...
```

17 个 bold run 中的关键几项（这是标题层级的真正来源，字号与正文相同）：

```
[B 15.96] WELCOME TO Seatrium                ← 唯一的大标题
[B 11.04] User Details                       ← 标签组容器标题
[B 11.04] (A) Steps to Login to Computer     ← 小节标题
[B  9.96] Note - Password Criteria           ← 小节标题
[B  9.96] ServiceDesk Hotline / Email        ← 底部联系信息标题
```

而 8 个加粗标签全部以冒号结尾：`Name :` / `Company :` / `Department :` / `Username :` / `Email ID:` / `Password :` / `ServiceDesk Hotline:` / `ServiceDesk Email:`。**冒号是本样本里近乎完美的判别器**——加粗 + 冒号 = 标签，加粗 + 非冒号 = 标题。

## Goals / Non-Goals

**Goals:**

- 提取层保留粗体与字体族信息，使下游能区分加粗的标题与加粗的标签。
- 修正同字号无差别合并，保留表单项、列表项的原始换行边界。
- 加粗的标签还原为 `**标签:** 值`，加粗的小节还原为标题层级。
- bullet 前缀（含私用区码位）正确还原，而非混入正文或被误删。
- 英文句号结尾的行不再被误合并。

**Non-Goals:**

- 不做两栏正文与复杂表格还原（需要 x/y 坐标，见"延后项"）。
- 不做 OCR（无文字层的扫描件仍引导"保留原文件为附件"）。
- 不追求 1:1 版式还原——目标是"可读、可复制、结构可辨认"。
- 不改 DOCX / XLSX 导入路径。
- 不处理字体回退产生的单字符噪声（`CourierNewPSMT` 的 `o` ×3），见 D8。

## Decisions

### D1: 粗体与章节标记优先，坐标延后

上一版设计（已作废）建议"先走 `boundingBox` 最小改动"。真实样本分析后判定**粗体与冒号比坐标更值钱**：

| 方案 | 覆盖本样本 | 改动面 |
|---|---|---|
| 粗体 + 冒号 + 章节标记 | 8 个标签 + 3 个加粗标题 + bullet | 提取脚本加 2 个字段 + 判定规则 |
| x/y 坐标 | 两栏、复杂表格、精确列表缩进 | JXA 取坐标 + 全部分组逻辑重写 |

坐标能解决的问题（两栏正文）在本样本中不存在；粗体能解决的问题覆盖了本样本 80% 以上的可读性损失。先做高收益项，坐标作为后续独立 change。

**实现代价**：坐标方案需要 JXA 侧调用 `boundingBox`（Swift 侧已验证可用，但 JXA 的 `enumerateAttributesInRange` 实测不可用，需走 `boundingRectWithSize`），而粗体方案只需在现有循环里多取 `fontName` 并派生 `bold`，不动控制流。

### D2: 中间表示升级为富文本段

当前 `_Block(text: String, level: int)` 无法表达"标签加粗、值不加粗"。升级为：

```dart
class _Seg { final String text; final bool bold; }
class _Block { final List<_Seg> segs; final int level; }
```

影响面：`_Line`、`_blocksFromPage`、`_reflowParagraphs`、`_joinWrapped`、Markdown 渲染全部需要处理 `_Seg` 列表。判定规则（D4）需要读"当前行是否以粗体结尾"，富文本段是该规则的必要条件——这是 A 方案真正的成本所在，而非规则本身。

### D3: 同字号合并只在"词内折行"时生效

主凶。原逻辑无差别合并所有相邻同字号行，把 `User Details` / `Name :` / `Zhongren Liu` / `Company :` 全拼成一条。

合并的判定条件（**需同时满足**）：

1. 上行以非空格字符结尾，且该字符不是词终结字符（字母、数字、连字符）
2. 上行不以标点结尾（`.` `,` `;` `:` `?` `!` `)` `]` `》` `」` 等）
3. 下一行以小写字母、数字或连字符开头（`software` ← `soft-`），而非大写或句首风格

任一不满足 → 不合并，保留为独立行。`Name :` 结尾是冒号 → 不合并；`Zhongren Liu` 结尾是大写后空格 → 按规则 2 不合并；`soft-` 结尾是连字符且下一行小写 → 合并。

**备选：完全取消同字号合并**，改为在 `_reflowParagraphs` 里按句末标点判断。代价是真正的词内折行（`soft-\nware`）会保留为 `soft- ware`。本样本中不存在此类折词，但英文长文档常见。选条件合并以保留原有能力。

### D4: 标签 vs 标题判定

按优先级从上到下匹配，首个命中即定：

| # | 条件 | 结论 |
|---|---|---|
| 1 | 字号比值 ≥ 1.8 | h1 |
| 2 | 行首匹配章节标记 `[(（]([A-Z]|[一二三四五六七八九十]|\d+)[)）.]` | h2 |
| 3 | 加粗 且 结尾为 `:` / `：` | 标签 |
| 4 | 加粗 且 独占一行 且 长度 ≤ 40 | h2（若无规则 2 命中）/ h3 |
| 5 | 字号 < bodySize | 正文（level 0） |
| 6 | 其余 | 正文 |

规则 4 的"独占一行"含义：该行是 `_Block` 中唯一的文本，后面不紧跟同字号非空行。这是区分"加粗标签组容器标题"（`User Details` 独占一行，后接标签行）与"行内加粗"的判据。

**为什么需要规则 2**：本样本的 `(B) Rules and Regulations on use of company devices` 标题几乎全是非粗体（`[H 11.04] (B)` 非粗 + `[B 11.04] ` 粗 + `[H 11.04] Rules and...` 非粗），纯加粗规则会漏掉它。章节标记前缀是更可靠的信号。

**已知残余**：标签判定依赖冒号。若标签不加冒号（如 `Name Zhongren Liu`），规则 3 不命中，会退回规则 6 作为普通正文。这是可接受的降级——不会产出错误结构，只是少了加粗还原。

### D5: bullet 前缀还原

- 已知符号集扩展为含私用区码位：`U+2022` / `U+2023` / `U+25AA` / `U+25AB` / `U+00B7` / `U+00B0` / `U+F0A8`（Wingdings 私用区）/ `U+F0B7` / `U+F076`。
- 判定"符号 run 是 bullet"而非"是孤立噪声"：符号 run 之后紧跟同字号非空 run → bullet，补 `- ` 前缀；孤立且无后续内容 → 丢弃。
- 现有 `_dropLoneBullets` 的白名单只认 `U+2022` 等，`U+F0A8` 不在其中，导致三个 Wingdings bullet 被当作普通文本混入段落。

**备选**：不补前缀，仍丢弃符号。已否决——本样本的三个 bullet 各带一行内容，丢弃符号后这些行会失去"是列表项"的语义，比保留原样更糟。

### D6: `_sentenceEnd` 补英文句号

现正则 `[。！？；：!?;:][”"）)\]】]*$` 不含 `.`。英文文档中所有以句号结尾的行都被判定为"未结束"，与下一行合并——这是 9.96 步骤说明全部并成一条的原因。

补 `.` 时需防小数误判：`.5`、`3.14` 这类。规则：`.` 后是空格或行尾才判为句末，`.` 后是数字则不判。

### D7: 判定失败一律降级为正文

无法可靠判定时不产出错误结构——不补错误的 `- ` 前缀，不把标签误判为表格行列。判定规则只作用于"命中"的分支，未命中走原有正文路径。这是既有降级原则的延续（见 `notebook-import-and-attachments` design 的"宁可少标题，不可错标题"）。

### D8: 不处理字体回退产生的单字符噪声

本样本中 `CourierNewPSMT` 的 `o` ×3 是 Word 生成 PDF 时的字体回退产物——原文档里大概是二级列表标记（对应 `Employees should...` 三项）。单字符字母 + 空格 + 正文的模式可识别，但"单字符字母是否算列表标记"跨文档不稳定（`a` `b` `c` 可能是正文缩写、版本号 `v.2` 的一部分）。

**决策**：保留原样，不加前缀。单字符原样输出至少文字可读；乱补 `- ` 会产出错误结构，违反 D7。若后续样本证明这是高频模式，再以独立 change 处理。

## Risks / Trade-offs

- [富文本中间表示改动面大] → `_Line`/`_Block`/`_reflowParagraphs`/渲染全链路改写；必须保留现有字号推断、页码过滤、无文字层异常的测试全绿。建议先在现有测试上跑通再逐条加规则。
- [标签判定依赖冒号，跨文档不稳定] → 无冒号标签退回规则 6（普通正文 + 无加粗还原），不产出错误结构。
- [同字号合并的判定条件可能过严] → 真正的词内折行（`soft-\nware`）可能残留为 `soft- ware`。可接受：残留比误合并更易人工修正。
- [英文句号补入后可能影响中文文档] → 句号仅在后接空格或行尾时判句末，中文文档以 `。` 为主，`.` 出现频率低且多为小数/版本号。
- [私用区码位集合不完整] → 不同字体（Wingdings / Symbol / ZapfDingbats）的私用区映射不同，无法穷举。当前覆盖 Wingdings 的 `U+F0A8`；后续按样本补充。
- [回归面大] → 既有标题层级、页码过滤测试必须保持绿；新增判定只作用于命中分支。

## 延后项（需要 x/y 坐标，独立 change）

- 两栏正文的列分离
- 复杂表格的行列还原
- 精确的列表缩进层级（当前只区分一级/二级）

这些在粗体 + 冒号规则之后仍有剩余价值，但收益面窄于本轮。

## Migration Plan

- 无数据迁移。存储格式、Delta 结构、附件表均不变。
- 已导入的历史笔记不受影响；用户可重新导入同一 PDF 获得更好还原。
- 回滚 = revert 代码，无状态残留。

---

## 补充发现：字符级 run、真正的合并主凶与句号（2026-09-19 二轮验证）

上一版 design D1 主张"先走 boundingBox"。二轮用真实 JXA 输出逐步回放后确认**该路径走不通**，且主凶定位有修正——**不是** `_blocksFromPage` 的合并，而是 `_reflowParagraphs`。

### 字符级 run 输出

实测 JXA 侧 `attributesAtIndexEffectiveRange(idx, effRange)` 返回的 `effRange.length` **恒为 0**（首 run 即为 0，循环 `if (effLen <= 0) effLen = 1` 强制为 1）。逐页统计：

```
page0: textLen=594  runs=594
page1: textLen=984  runs=984
```

run 数等于文本长度——**PDFKit 在此路径下以字符为粒度返回 run**。设计 D1 里"先走 boundingBox 最小改动"的前提（run 是粗粒度文本片段）不成立，坐标方案需要改 JXA 控制流，且收益面窄于本轮。

### 合并不是主凶（修正上一版结论）

上一版把主凶归到 `_blocksFromPage` 的"合并相邻同字号片段"。用真实 JXA 输出逐步回放后**推翻该结论**：`_blocksFromPage` 的 lines 构建先按 `\n` 拆分，`empty` 行会打断同字号合并链，因此合并结果与原文档视觉换行一致。实测 page0 合并后：

```
[15.96] 'WELCOME TO Seatrium'
[11.04] 'User Details'
[11.04] 'Name : Zhongren Liu'           ← 同一物理行内正确拼合
[11.04] 'Company : CO-MALL'
[11.04] 'Department : GIOT - Application'
[11.04] 'AD Login Account and Password'
[11.04] 'Username : SEATRIUM\Zhongren.Liu-c'
...
[9.96]  '1. Switch on your machine.'
[9.96]  '2. You will see the "Login Screen" as shown below.'
[9.96]  'Note - Password Criteria'
```

37 条 block，边界清晰。**换行信息在提取与合并阶段都是完整的。**

### 真正的主凶：`_reflowParagraphs` 的句末标点表

`_sentenceEnd = [。！？；：!?;:][”"）)\]】]*$` 不含 `.`。英文行几乎全部以 `.` 或无标点结尾，`canMerge` 因此几乎恒为真，整篇被并成 4 条巨块：

```
1. 'WELCOME TO Seatrium User Details Name : Zhongren Liu Company : CO-MALL ... Email ID:'
2. 'Password :'
3. '22CUG=+_K#RPwY47(A) Steps to Login ... o Employees should not install ...'
4. 'This User ID is issued ... mailto:servicedesk@keppelenterprisesvcs.com'
```

这才是"只有第一行是大标题"的直接来源——第 1 条块里 `WELCOME TO Seatrium` 保留了 h2 层级，但它后面的所有内容都被并进了同一个 level-2 块，渲染时全部作为标题正文输出。

**次要问题**：``（Wingdings 私用区，原文档的 checkbox 符号）未被 bullet 白名单覆盖，混入正文。三个 `•`（U+2022）被 `_dropLoneBullets` 正确丢弃，但丢弃后丢失了列表语义。

### 决策修正（覆盖 D1，D3 大幅收窄）

- **D1 作废**：不引入坐标。字符级 run 下坐标方案需要重写 JXA 控制流，收益面窄。
- **D3 收窄**：不再要求"重写合并判定"——现有合并在本样本上产出正确结果。保留原逻辑，仅在验证发现跨 `\n` 合并时才改。
- **新增 D9（主修复）**：`_sentenceEnd` 补 `.`，且仅当 `.` 后为空格或行尾时判句末（防 `3.14`、`v.2` 误切）。这是单点修复，改动一行正则。
- **D2 暂缓**：富文本 `_Seg` 升级暂不做。字符级 run 下加粗标签仍可判定（`Name : ` 整段 bold=true），标签还原先用"整行加粗 → `**整行**`"过渡，视觉等价度足够。
- **D4 简化**：因合并非主凶，标签/标题判定可直接基于"行"做，不需要富文本段支持。规则集保留，但实现从"读段内 bold 状态"简化为"读整行 bold 状态"。
- **D5 扩展**：bullet 白名单补 `U+F0A8` 等私用区码位；改为"有后续内容则补 `- `，孤立则丢弃"，恢复列表语义而非丢弃。
- **D6 保持**：句号补全即为本 change 的主修复。

### 影响

改动面从"提取脚本 + 富文本全链路"进一步缩小为"`_sentenceEnd` 正则 + bullet 白名单 + 行级 bold 判定"。单点修复，可独立验证，风险低。富文本升级与坐标方案均推为后续可选 change。
