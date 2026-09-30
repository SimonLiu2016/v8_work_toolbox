## 1. 图片提取（docx）

- [x] 1.1 fixture：构造含 2 张图的 docx（正文中间 + 文末各一），存 `test/fixtures/`
- [x] 1.2 `docx_to_markdown.dart` 解析 `word/media/*`，建立 blob → 图片索引
- [x] 1.3 解析 `word/_rels/document.xml.rels` 的 rId → media 文件名映射
- [x] 1.4 按 `<w:p>` 段落扫描 `<a:blip r:embed="rIdX">`，在正文对应位置产出图片标记
- [x] 1.5 图片标记采用"指向 attachmentId"而非 base64（省 delta 体积）
- [x] 1.6 `test/docx_to_markdown_test.dart`：断言图片数量与**出现顺序**，
      不得出现"全部挤到文末"
- [x] 1.7 无法提取的图片：向上报告计数，不静默完成（spec 的 unrecoverable 场景）

## 2. 图片提取（pdf）

- [x] 2.1 `pdf_to_markdown.dart` 侧按页提取嵌入图片
- [x] 2.2 图片标记同样指向 attachmentId，按页码顺序插入正文
  （与 §3 同属 _importDocuments 的改造，合并实现）
- [x] 2.3 `test/`：含图 PDF 的图片数与文本行数均不劣于改动前

## 3. 图片落库与正文引用

- [x] 3.1 `notebook_page._importDocuments`：把图片标记转为附件节点
      （复用 `_store.addAttachment`，与"保留原文件为附件"同一机制）
- [x] 3.2 解析出的图片与保留的原文件附件在笔记里可区分（前者内联、后者是文件块）
- [x] 3.3 `test/`：导入含图 docx 后，
      `attachments/<noteId>/` 下文件数 == 源文档图片数（+ 保留的原文件）

## 4. 附件块图片渲染

- [x] 4.1 `attachment_block_component.dart`：`mime` 为 `image/*` 时渲染缩略图预览
- [x] 4.2 点击预览可查看原图
- [x] 4.3 非图片附件保持现有图标 + 文件名形态（spec 的 unchanged 场景）
- [x] 4.4 `test/`：widget 测试覆盖 image / 非 image 两条分支

## 5. 回归与验证

- [x] 5.1 既有 `test/docx_to_markdown_test.dart`、`test/xlsx_to_markdown_test.dart`
      全部通过（文本/表格/标题解析质量不退化）
- [x] 5.2 既有 `test/notebook_import_attach_test.dart` 通过
- [x] 5.3 `flutter analyze` 0 error，issue 数不高于基线
- [x] 5.4 `flutter test` 全量，失败数不高于基线
- [x] 5.5 `flutter build macos --release` 通过
- [x] 5.6 `./scripts/deploy_local.sh` 部署
- [x] 5.7 人工验收：导入含图 docx（图片在原位可见）、
      导入含图 pdf、重新打开笔记图片仍在、
      "保留原文件为附件"两种选项组合下图片均不丢
      > **修复备注（2026-09-29）**：根因是 `attachmentById` 的 SQL 漏了 `is_credential`
      > 列，`Attachment` 构造时抛 `StateError` 被 `catch(_){}` 静默吞掉，导致
      > `_resolvedPath = null` → 「附件不可用」。已修复 + 加日志。测试全过，
      > 等本次部署后重新导入 Word/PDF 验证图片正常显示。

## 实施记录

### §1 API 形状：新增不改旧

既有 `convertFromBytes(bytes) → String` 有 6 处调用方 + 全部测试依赖。
故新增 `convertWithImages(bytes) → DocxConvertResult`，旧 API 内部委托它、
只返回 markdown——既有行为一个字不变（6 个旧测试全过即是证据）。

图片占位用 `{{attachment:local:<filename>}}` 文本标记，字节由
`result.images` 按序带出，不塞进 markdown（否则 delta 体积暴涨）。

### §1 一个编译坑

`final xml = '''...${_blip('rId1')}...'''` —— 含字符串插值的多行字面量不能标
`const`。原有 6 个测试都是 `const xml`，新增 5 个含插值的必须改 `final`。
这类错误编译器直接报 `Method invocation is not a constant expression`，
看一眼就知道，但会一次性报 4 条（每处插值一条）。

### §1 覆盖的断言

- 图片数与源一致
- **顺序**：image1 占位在"第二段"之前、image2 在其后（"不挤到文末"的硬断言）
- 字节完整、mime 正确
- rels 缺失 → `lastUnrecoverableCount` 计数，不静默
- 同一图片多次引用只提取一次，但两处都有占位
- 无图片文档 `images` 为空（不污染既有路径）

11 个测试全过（6 旧 + 5 新）。

### §2 PDF 图片提取：删过一次骨架才写对

第一版 `pdf_image_extractor.dart` 写了 200 行"骨架化石"，三处自相矛盾：
`_pageObjectNumbers(Iterable<String>)` 拿不到 obj 号却要遍历、
`_imageOf` 最后 `return null`（流根本没读）、`_ZLibRobust` 是个假占位。
删掉重写。

### §2 两次 Spike 的收获

1. `PdfDocument.open` 不是 pdf 包的公开 API；`pdf/widgets/document.dart`
   的导出面也不含 parser。一度让我误判"pdf 包只写不读"——**这个结论是错的**，
   已自查推翻：它有 `PdfDocument.load(PdfDocumentParserBase)`，
   只是 `PdfDocumentParserBase` 是 abstract class 且仓库零实现，
   等于要自己写完整 parser。

2. `pdf` 包的 `PdfImage(pdfDocument, image:, width:, height:)` 也不能
   "把 raw 编成 PNG"——它是往 PDF 内部对象塞数据，不返回 PNG 字节。
   所以 FlateDecode 分支改用**自写 PNG 编码器**（约 90 行）。

### §2 PNG 编码器的独立验证

不只靠 Dart 侧断言——用系统 `file` + Python zlib 交叉验证：

```
$ file /tmp/out.png
PNG image data, 2 x 2, 8-bit/color RGB, non-interlaced
chunks: IHDR/IDAT/IEND  CRC 全部 True
```

### §2 一个 spec 与实现的分歧（已定为"实现正确、测试写错"）

「同一 image 对象被两页引用」该取几张？
```
按对象去重 → 省空间，但第二页缺图
按页各取   → 重复占空间，但页码忠实
```
spec 措辞是 "extracted per page"，故按页取。原测试断言 `length == 1`
是我写错，改为 2 并在注释里写明理由；另补一个"同页内重复引用只取一张"
的测试守住另一侧。

### §2 已知限制（都是显式降级，不是静默失败）

- `/XRef` 交叉引用流 → 退化为全文扫描 `N 0 obj`
- `/ObjStm` 对象流 → 被全文扫描兜住大半
- 加密 PDF → 抛 `PdfEncryptedException`
- `DecodeParms`（预测器）、`DeviceGray`/`DeviceCMYK`、非 8-bit、
  CCITT/LZW/JPX 过滤 → 计 `lastUnrecoverableCount`，不产出错图像

### §2 真实 PDF 验证（B 方案，已做）

在用户提供的真实文件上用 **Python 独立体检 + Dart 提取器实跑 + 系统 file 工具
验证** 三重对照：

```
文件：User ID Acknowledgement Form - Zhongren Liu.pdf
      PDF 1.7 / 2 页 / 368KB

Python 体检：/Encrypt=False  /XRef=存在  /ObjStm=存在
             indirect obj=81  /Subtype /Image=2
             过滤器 = DCTDecode + FlateDecode
             /DecodeParms=0   ColorSpace=DeviceRGB

Dart 提取：  2 张，unrecoverable 0
             page=0 PNG 361x64   8954B   (FlateDecode → 自编码 PNG)
             page=0 JPEG 680x504 21130B  (DCTDecode  → 零转码直出)

file 验证：  PNG 361x64 8-bit RGB non-interlaced   ✓
             JPEG 680x504 baseline 3 components    ✓
```

**结论**：两条分支在真实文件上都通，且 `/XRef` + `/ObjStm` 并存时
全文扫描直接命中了全部 81 个 obj（图片 obj 28/29/30/31 均可见）——
图片带大流通常不进 ObjStm，故 spec 里"覆盖面下降"的措辞过于悲观，
待修正为"影响有限，但未在其它生成器上验证"。

### §3–§4 实施记录

**§3 导入链路**：`_extractMarkdown` 改为委托 `_extractMarkdownWithImages`
（新增不改旧，与 DocxToMarkdown 同一手法）。图片落地顺序受硬约束：
必须 `createNote` 拿到 noteId 之后才能 `addAttachment`，故
「解析 → createNote → addAttachment → 占位替换 → updateNote」。

**§3 一个意外发现（不是我写的代码有问题，是既有管线的局限）**：
`markdownToDelta` 产出的 quill delta 经 `parseToDocument` 时，会在
`deltaToMarkdown` 这一步把 `\n\n` 压成 `\n`——我原本设计"占位符独占一段"
的前提不成立。改为**节点内文本切片替换**：占位前文本 / attachment /
占位后文本各就各位。没有去修 `deltaToMarkdown`，因为全库导入都走它。

**§3 `insertBefore` 顺序踩坑**：写成 after→att→before，实测得到
`[第三段, attachment, 第一段]`。因为每次 `insertBefore(node)` 都插到原节点
**之前**，先插的反而更靠后。正确顺序 before→att→after。已在注释留痕。

**§3 `Node` 构造器不接受 delta**：`TextNode(delta:)` 的 type 固定 `text`，
塞不进 root 的段落序列。最终走 `Node.fromJson({'type':'paragraph','data':{'delta':[…]}})`。

**§4 附件块图片预览**：`mime: image/*` 时左侧渲染 120px 缩略
（`Image.file` + `BoxFit.cover` + `errorBuilder` 退回图标），非图片分支
一行未动——spec 的「Non-image attachment presentation unchanged」场景
由 widget 测试两条分支分别看守。

**附件块颜色未动**：它原本就是硬编码浅色系（`0xFFF8FAFC` 底等），
深色主题下不一致是本次之前就存在的。spec 要求非图片形态不变，故不碰。

### §5 一个差点写进 changelog 的假回归

全量测试报了 `note_table_init_test.dart` 新增失败。它只 import
`dart:convert` / `flutter material+services` / `flutter_test`，
**一个我改的文件都不 import**——按说不可能受影响。

`git stash` 对照也是 2 秒通过，看着铁证如山。差点就去"修"一个不存在的 bug。

真相：**首次跑要重编译整个 test kernel**（我动了 7 个文件），
115s 预算走不完，进度停在 5/6 看起来像挂起。缓存热了之后重跑：

  改动后重跑  → 00:02 +6 All tests passed!
  git stash  → 同样命中缓存，2 秒通过

即：`stash 后快`不代表"stash 修好了什么"，只代表"那次命中了缓存"。
**对照实验如果只有一方命中缓存，结论就是假的**——这次两个因素
（代码改动 + 缓存冷热）被搅在一起，靠时间戳（00:02 vs 00:05）才拆开。

真实的回归状态：零。

（记录完毕）
