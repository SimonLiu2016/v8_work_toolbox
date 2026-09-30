## 0. 矩阵数据源先行（先红）

> 顺序：矩阵表 + 一致性测试必须先存在且**当前是红的**，否则无法证明 27 个可用格
> 真的被逐个交付。写完就是绿说明测试太松。

- [x] 0.1 新建 `lib/tools/notebook/convert/matrix.dart`：导出格式枚举、
      矩阵表（T1/T2/不可用三态）、`availableTargets(source)`
- [x] 0.2 新建 `test/document_conversion_matrix_test.dart`：把矩阵表与
      已注册的 converter 注册表做交叉比对——矩阵标了可用但没实现 → fail；
      实现了但矩阵标不可用 → fail
- [x] 0.3 断言不可用格不出现在 `availableTargets` 结果里（UI 缺席的守卫）
- [x] 0.4 跑一遍确认：27 个可用格**全部红**（未实现），记录清单作为交付对照

## 1. 内容模型与翻译器

- [x] 1.1 `document_model.dart`：块树（段落/标题/列表/表格/单元格）+ 图片引用
- [x] 1.2 `parsers/`：docx / xlsx / csv / md / txt / pdf 六个 parser 产出模型
      （复用现有 `docx_to_markdown` / `xlsx_to_markdown` 的 ZIP+XML 解析底子）
- [x] 1.3 `translator.dart`：复用 `AiService.instance.chat(slot: 'text')`，
      按**字符预算**动态分批（≤4000 字符/批，非固定条数）
- [x] 1.4 失败批次单独重试，不整体失败；进度回调驱动 UI
- [x] 1.5 `test/`：parser 产出模型的结构断言 + 翻译分批的条数/预算测试

## 2. T1 路径（8 格，原地改写）

> T1 绕过内容模型，直接改源文件字节——这是"除文本外一个字节都不动"的唯一保证。

- [x] 2.1 `ooxml_rewriter.dart`：docx→docx —— 按 `<w:p>` 聚合 run 文本，
      整段送译，按原 run 边界均分回写（已知限制见 design Risks）
- [x] 2.2 回写前做 XML 实体转义（`&` `<` `>`），保证译文不破坏良构
- [x] 2.3 `spreadsheetml_rewriter.dart`：xlsx→xlsx —— 改 `xl/sharedStrings.xml`
      的 `<t>` 与 inlineStr 两类
- [x] 2.4 `csv→csv`、`md→md`、`txt→txt`：逐行重写
- [x] 2.5 `txt→docx`、`txt→pdf`、`txt→md`：单段文本直出（无排版要保）
- [x] 2.6 `md→pdf`：T1 的 pdf 列（md 本就无复杂排版，原地语义成立）
- [x] 2.7 `test/`：**字节级断言** —— 除 `<w:t>` 内容外，
      docx→docx 产物的 `word/media/`、`styles.xml` 与源逐字节相同

## 3. T2 扁平 writer（10 格）

- [x] 3.1 `flatten.dart` 的 `toMarkdown`：由内容模型渲染 md
- [x] 3.2 `flatten.dart` 的 `toText`：由内容模型渲染纯文本
- [x] 3.3 覆盖 `→md`：docx / md / pdf / xlsx / csv
- [x] 3.4 覆盖 `→txt`：docx / md / pdf / xlsx / csv
- [x] 3.5 `test/`：图片在 md 输出中保留为引用节点；页码/表头不丢失

## 4. T2 pdf writer（4 格）

- [x] 4.1 `pdf_writer.dart`：用已装 `pdf` 包自实现块级排字
      （段落 y 推进、换行、分页、图片放置、中文字体嵌入）
- [x] 4.2 覆盖 `→pdf`：docx / md / pdf / xlsx（csv 由 §3 的 csv→pdf 归入本节）
- [x] 4.3 CJK 字体：复用项目既有 `CJK Fidelity in PDF Document Export` 的做法
- [x] 4.4 `test/`：产出 PDF 的页数、图片对象数、CJK 文本可抽取

## 5. T2 OOXML writer（3 格）

- [x] 5.1 `docx_writer.dart`：最小 OOXML 写出器
      （`[Content_Types].xml` + `word/document.xml` + `word/_rels` + `styles.xml`），
      用 `archive` 打包
- [x] 5.2 覆盖 `→docx`：md / xlsx / csv
- [x] 5.3 `test/`：archive 解出的 XML 良构 + 必需 part 齐备
- [x] 5.4 人工用 Pages/Word 打开验证（转出的文件不报损坏）

## 6. T2 表格 writer（2 格）

- [x] 6.1 `xlsx_writer.dart`：csv→xlsx —— 最小 SpreadsheetML
      （`xl/worksheets/sheet1.xml` + `sharedStrings.xml` + `styles.xml`）
- [x] 6.2 `flatten.dart` 的 `toCsv`：xlsx→csv —— 逐 sheet 扁平化
      （必然丢样式，这是 csv 的性质，spec 已按 T2 声明）
- [x] 6.3 `test/`：xlsx 写出可被本项目 `xlsx_to_markdown` 读回（闭环）

## 7. UI 接入

- [x] 7.1 `attachment_block_component.dart` 操作区加「转换」入口
- [x] 7.2 目标下拉只渲染 `availableTargets(source)` 的结果
- [x] 7.3 源语言 / 目标语言 / 目标格式三个选择 + 是否翻译的开关
- [x] 7.4 进度展示（复用 translator 的回调）
- [x] 7.5 产物写为新 attachment（不覆盖原件），命名带 `_<lang>_to_<fmt>` 后缀
- [x] 7.6 扫描版 PDF（无文字层）：明确报告，不产出看似成功的空文件

## 8. 验证与部署

- [x] 8.1 矩阵一致性测试：27 可用格全绿、9 不可用格仍缺席
- [x] 8.2 `flutter analyze` 0 error
- [x] 8.3 `flutter test` 全量，失败数不高于基线
- [x] 8.4 `flutter build macos --release` 通过
- [x] 8.5 `./scripts/deploy_local.sh` 部署
- [x] 8.6 人工冒烟：每条 T1 各转一次（重点验收"排版无变化"），
      每条 T2 各转一次（重点验收"内容与图片不丢"）

## 实施记录

（执行中记录）
