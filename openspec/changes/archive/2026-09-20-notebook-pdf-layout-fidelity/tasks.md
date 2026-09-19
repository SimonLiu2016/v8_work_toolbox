# Tasks

真实样本（Seatrium 用户 ID 申请表，2 页）二轮验证后，主凶已从"同字号合并"修正为 `_reflowParagraphs` 的句末标点表缺英文句号——详见 design.md 的"补充发现"。

任务按"单点主修复 → 提取增强 → 判定 → bullet → 回归"排列。第 1 组是独立可验证的单点修复，完成后可先部署验证收益。

## 1. 主修复：句末标点表补英文句号（design D6 / D9）

- [x] 1.1 `_sentenceEnd` 补 `.`，锚定行尾 `$`（`3.14`、`v.2` 这类 `.` 后接数字的不命中）
- [x] 1.2 单测：`1. Switch on your machine.` / `2. You will see...` / `3. ...` 各成独立行
- [x] 1.3 单测（防回归）：`v.2`、`3.14` 不被误判为句末而拆分
- [x] 1.4 单测：真实样本结构（多行不再并成一条巨块）
- [x] 1.5 构建并部署，导入真实 PDF 验证行边界恢复

## 2. 提取层补充粗体

- [x] 2.1 `_jxaScript` 输出从 `[size, text]` 扩展为 `[size, text, bold]`；`bold` 由 `NSFont.fontName` 含 `Bold`/`Black` 派生
- [x] 2.2 `convertFromRuns` 解析新字段；缺字段时按"非粗体"处理（向后兼容既有 2 元素输入）
- [x] 2.3 单测：含 bold 标记的 run 经解析后粗体信息保留到行；旧 2 元素格式仍可解析

## 3. 标签 vs 标题判定（design D4，行级简化）

- [x] 3.1 `_Line` 增加 `bold` 字段，合并时取或
- [x] 3.2 `_classifyBlock` 实现规则集：字号≥1.8→h1；≥1.35→h2；章节标记→h2；加粗+冒号结尾→标签；加粗+独占短行+不含冒号→h3；字号比值→h3；其余→正文
- [x] 3.3 标签行输出为 `**整行**`（字符级 run 下不加细分，design D2 暂缓）
- [x] 3.4 判定未命中一律降级为正文（design D7）
- [x] 3.5 单测：`(A)`/`(B)` 判为 h2；`Note - Password Criteria` 判为 h3；`Name :` 判为标签加粗

## 4. bullet 前缀还原（design D5）

- [x] 4.1 bullet 符号集扩展含私用区码位：`U+2022`/`U+2023`/`U+25AA`/`U+25AB`/`U+00B7`/`U+00B0`/`U+F0A8`/`U+F0B7`/`U+F076`
- [x] 4.2 判定逻辑从"丢弃"改为"有后续内容则补 `- ` 前缀，孤立则丢弃"
- [x] 4.3 单测：`• Minimum 14...` → `- Minimum 14...`；`U+F0A8 Enter the Password` → `- Enter the Password`；孤立符号仍丢弃
- [x] 4.4 更新既有"孤立项目符号行被丢弃"断言，匹配新的语义恢复行为

## 5. 回归与验收

- [x] 5.1 既有能力保持绿：字号推断标题层级、页码过滤、段落分隔（中文句号）、无文字层异常
- [x] 5.2 既有测试套件回归：`flutter test test/pdf_to_markdown_test.dart test/notebook_import_attach_test.dart test/markdown_converter_test.dart test/appflowy_codec_test.dart test/note_store_attachment_test.dart` —— 60 项全绿
- [x] 5.3 `flutter analyze` 对改动文件无告警
- [x] 5.4 构建并部署到本机应用（clean → build → codesign 校验 → 替换），AOT 快照 `cc5bdffe…` 确认全新构建，启动存活无崩溃
- [ ] 5.5 再导一份普通正文型 PDF，确认无格式劣化（待用户验收真实 PDF 后补）
- [x] 5.6 `openspec validate notebook-pdf-layout-fidelity --strict` 通过

## 6. 待 `notebook-import-and-attachments` 归档后

- [ ] 6.1 该 change 归档后，本 change 补正式 spec delta：`specs/notebook-storage/spec.md` 以 MODIFIED 修改"Import a PDF document with structural restoration"需求（补粗体/标签/章节层级与 bullet 还原要求）。当前 `.openspec.yaml` 设 `skip_specs: true`，原因是目标需求仍在另一 change 的 delta 中、尚未落进主 specs，OpenSpec 不允许对未落地需求做 MODIFIED。

## 已明确不做（避免重复评估）

- **x/y 坐标方案**：作废。字符级 run 下需重写 JXA 控制流，收益面窄于本轮。两栏正文与复杂表格作为后续独立 change。
- **富文本中间表示升级**（`_Seg`）：暂缓。字符级 run 下整行加粗判定足够，视觉等价度足够。
- **字体回退单字符噪声**（`CourierNewPSMT` 的 `o` ×3）：保留原样，不加前缀——单字符字母跨文档不稳定，乱补前缀违反降级原则。
