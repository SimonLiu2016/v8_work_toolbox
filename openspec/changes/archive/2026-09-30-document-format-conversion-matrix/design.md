## Context

`notebook-attachment-preserve-and-document-translate` 已让 docx/pdf 导入时图片不再
丢失，且附件块能内联渲染图片——那是本 change 的前置：转换产物里的图片总得有地方安放。

动机见 `proposal.md` — Why；矩阵契约见
`specs/document-conversion-matrix/spec.md`。

## Goals / Non-Goals

**Goals:**
- 36 个 (源 × 目标) 格子中 27 个可用格（T1 × 8 + T2 × 19）全部交付，无静默落格。
- 9 个不可用格在 UI 中缺席。
- 翻译与格式转换三者组合（只译 / 只转 / 都做）都可用。
- 矩阵与实现的对应关系由测试看守，不是靠人记。

**Non-Goals:**
- 不做 OCR（扫描版 PDF 无文字层，spec 要求"报告"而非"猜"）。
- 不引入 LibreOffice / pandoc（本机未装、用户机器不保证、随 App 分发 400MB+ 不现实）。
- 不承诺 T2 路径排版无变化——spec 写明是 best-effort。
- 不动图片保真（前置 change 的职责）。

## Decisions

### 1. 内容模型作为唯一中间表示，格式化职责后置到 writer

- **Decision**：解析层产出统一的 `DocumentModel`（块树：段落/标题/列表/表格/
  单元格 + 图片引用），翻译只作用于模型里的文本字段，writer 各自把模型渲染成
  目标格式。
- **Rationale**：6 种源格式 × 6 种目标格式，若两两直连要写 27 个适配器；经统一模型
  后是 6 个 parser + 3 类 writer。翻译也只做一处——否则每种格式各接一次 AI 调用。
- **Alternatives Considered**：
  - *源格式直连目标格式*：27 个适配器，翻译逻辑重复 27 次。否决。
  - *以 Markdown 为中间格式*：看似省事，但表格/单元格/图片位置会先在 md 里
    损失一次，T1 路径就废了。否决——T1 必须绕过模型直接改写源文件。

### 2. T1 路径完全绕过内容模型，原地改写源文件字节

- **Decision**：T1（docx→docx / xlsx→xlsx / csv→csv / md→md / txt→*）不解析成
  模型，直接改源包内的文本节点后重新打包。
  - docx：正则定位 `word/document.xml` 的 `<w:t>…</w:t>`，逐节点原文→译文替换
  - xlsx：改 `xl/sharedStrings.xml` 的 `<t>` 与 inlineStr
  - csv/md/txt：逐行重写
- **Rationale**：T1 的卖点就是"除文本外一个字节都不动"。走内容模型必然损失
  样式细节（docx 的 numbering、xlsx 的公式与条件格式都进不了简化模型）。
  `word/media/` 因此天然保留，图片零额外工作。
- **Trade-off**：需要保证"译文不破坏 XML 良构"——替换文本要做实体转义
  （`&` `<` `>`），且 `<w:t>` 可能被拆分在多个 run 里（详见 Risks）。

### 3. T2 路径按目标格式分三个 writer，不自研通用排版引擎

- **Decision**：
  - `* → md` / `* → txt`：扁平导出，直接由内容模型渲染
  - `* → pdf`：用已装的 `pdf` 包，自实现"块级排字"（段落 y 推进、换行、
    分页、图片放置、中文字体嵌入）
  - `* → docx`：自研最小 OOXML 写出器（`[Content_Types].xml` + `document.xml`
    + `_rels` + `styles.xml`），用 `archive` 打包
- **Rationale**：`* → xlsx / csv` 的语义错配已在矩阵中列为不可用，故 T2 只需
  md/txt/pdf/docx 四个 writer。pdf 与 OOXML 都是"够用即止"的最小实现，
  不做 Word/LibreOffice 那套完整引擎。
- **Alternatives Considered**：
  - *引入商业/重型库*：Dart 生态本来就没有成熟的 .docx 写出库。
  - *T2 也走 OOXML 中间表示再由外部转*：又回到依赖外部引擎的老路。否决。

### 4. 翻译复用 `AiService.instance.chat(slot: 'text')`，批量 + 分段

- **Decision**：照搬 `ai_subtitle_service.translateSubtitleSegments` 的模式：
  每批 25 条，下发 JSON 数组，要求模型保持 id 对应，进度回调驱动 UI。
- **Rationale**：该入口已在生产使用，provider 健康检查、代理、槽位解析都已处理。
  新写一套等于把这些重做一遍。
- **注意**：字幕是短句，文档是长段落。批量条数与 token 上限需按段落长度
  动态收敛（见 Risks）。

### 5. 矩阵由单一数据源驱动，UI 与实现都从它派生

- **Decision**：`matrix.dart` 导出矩阵表 + `availableTargets(source)`；
  附件操作区只渲染 `availableTargets` 的结果；测试把矩阵表与已注册的
  converter 做交叉比对，不一致就 fail。
- **Rationale**：spec 的「Matrix conformance is machine-checked」场景要求
  "mismatch fails the build"。若不从同一数据源派生，UI 表与实现表必然漂移。

## Risks / Trade-offs

- **[Risk] `<w:t>` 文本被拆在多个 run 里**：Word 常因拼写检查/格式边界把一段话
  切成多个 run。逐 run 替换会导致译者看到碎片、译文语法错乱。
  → *Mitigation*：按 `<w:p>` 段落聚合 run 文本→整段送译→再按原 run 边界
    均分回写。均分不完美时退化为"写回第一个 run、其余置空"（视觉上等价，
    因同段落样式通常一致）。需在 tasks 中列为已知限制并测试覆盖。

- **[Risk] 长文档翻译超 token 上限**：
  → *Mitigation*：批大小按字符预算动态计算（如每批 ≤ 4000 字符），
    不是固定 25 条；失败批次单独重试，不整体失败。

- **[Risk] OOXML 写出器产出 Word 打不开的文件**：
  → *Mitigation*：T2 的 `* → docx` 交付前用真实 Word/Pages 打开验证；
    测试至少覆盖"archive 解出的 XML 良构 + 必需 part 齐备"。

- **[Risk] pdf 自排中文出现方框（字体缺失）**：
  → *Mitigation*：嵌入系统中文字体（`/System/Library/Fonts/PingFang.ttc`
    一类），并在 spec 场景中断言 CJK 可渲染——项目已有
    `CJK Fidelity in PDF Document Export` requirement，可复用其做法。

- **[Trade-off] T2 的 19 格里，`*→pdf` 与 `*→docx` 占 11 格，是主要工作量**：
  → *Mitigation*：若交付压力大，可把 T2 拆为后续 change，但**必须在 tasks 中
    显式登记归属**，不允许静默落格（这是用户明确要求的）。

## Migration Plan

1. 先建 `matrix.dart` 与矩阵一致性测试（此时除 T1 外全红——这是预期）。
2. 实现 T1 的 **8** 格：docx→docx、md→pdf、md→md(规范化)、txt→{docx,pdf,md,txt}、
   xlsx→xlsx、csv→csv。
3. 实现扁平 writer，覆盖 T2 的 **10** 格：`→md`(docx/md/pdf/xlsx/csv) 与
   `→txt`(docx/md/pdf/xlsx/csv)。
4. 实现 pdf writer，覆盖 T2 的 **4** 格：`→pdf`(docx/md/pdf/xlsx/csv)。
5. 实现 OOXML writer，覆盖 T2 的 **3** 格：`→docx`(md/xlsx/csv)。
6. 实现表格 writer，覆盖 T2 的 **2** 格：`→xlsx`(csv)、`→csv`(xlsx)。
7. 矩阵一致性测试转绿 → 全量验证 → 部署。

（步骤小计 8 + 10 + 4 + 3 + 2 = 27，与矩阵的 T1×8 + T2×19 对齐，无余无缺。）
7. 回滚策略：converter 按格子独立注册，任一格出问题可从矩阵摘除
   （同时测试会红，强制显式决策）而不影响其他格。

## Open Questions

（无。矩阵已规范化，T1/T2 边界由"是否原地改写"这一机械判据决定。）
