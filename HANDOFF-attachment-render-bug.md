# 待解决问题移交文档：笔记附件（图片渲染 + 一键转换）

> 生成时间：2026-09-29
> 部署版本 AOT：`832d95135769b0b3e804db3c0405da4b`
> 当前分支：`main`（HEAD = `d7d7f97`）
> 相关 change：
> - `notebook-attachment-preserve-and-document-translate`（23/24 完成，卡在本文档的问题 A）
> - `document-format-conversion-matrix`（0/44 未开工，即本文档的问题 B）

---

## 零、原始需求（用户原话，未删改）

### 问题 A：导入文档后图片不显示

> 我导入了 word 和 pdf，但是结果没有达到预期，都显示图片 image.png.png 附件不可用。
> 具体可以查看当前笔记中的「User ID Acknowledgement Form - Zhongren Liu」和
> 「Seatrium User Manual_E&I iShop」的内容，它们就是我刚才测试的导入后的笔记。

### 问题 B：笔记附件需要「一键转换」功能

> 针对 pdf、excel、word、txt、csv、markdown 等类型笔记附件，应该提供一键转换的功能，
> 即点击后可以将文件内的源语言转义为目标语言，将文件转换为对应的目标文件格式，
> 并且内容格式和排版无变化。
>
> 比如，原来的附件是英文的 word，点击后，设定源语言为英文，目标语言为中文，
> 目标格式依然为 word 格式，那么生成的后的文件依然是 word，内部的排版及图片都是原来的，
> 只是里面的英文被翻译成了中文。
>
> 而如果目标格式为 pdf，那么就是内部排版与图片还是原来的，英文翻译成了中文，
> 但是输出的文件格式是 pdf。
>
> 同时，源文件的类型与可以转换的目标文件类型的对应关系你需要确定清楚，
> 比如：word 和 pdf 可以互相转换、word 和 markdown 可以互相转换，
> 但是，pdf 转 excel 可能就有部分不兼容的情况。你要清楚如何设计与处理。

### 两个问题的关系

```
问题 A（图片渲染）是问题 B（一键转换）的前置
    ↓
B 要求"排版与图片保持原样"，而图片当前连显示都做不到
    ↓
所以顺序是：先修 A，再开工 B
```

### B 的进度（已铺路但未动工）

change `document-format-conversion-matrix` 已建好，proposal / specs / design / tasks
四件套齐全且 `openspec validate` 通过，44 个任务全部未开始。

矩阵已定为（36 格全清单，◎ 8 + ○ 19 + ✗ 9）：

```
源＼目标   docx     pdf      md       txt      xlsx     csv
─────────────────────────────────────────────────────────────────
docx       T1       T2       T2       T2       —        —
md         T2       T1       T2       T2       —        —
txt        T1       T1       T1       T1       —        —
pdf        —        T2       T2       T2       —        —
xlsx       T2       T2       T2       T2       T1       T2
csv        T2       T2       T2       T2       T2       T1

T1 = 排版/图片零变化（原地替换文本节点，其余字节不动）
T2 = 内容与图片保留，排版尽力还原
—  = 不提供（不假装能做到）
```

用户举的两个例子分别落在：
- 英文 word → 中文 word = `docx→docx` T1，真正零变化
- 英文 word → 中文 pdf = `docx→pdf` T2，图片在、排版尽力

已有的实现基础（都在 C1 里写好了）：
- `lib/tools/notebook/docx_to_markdown.dart` — docx 解析（含 media/rels/blip）
- `lib/tools/notebook/pdf_image_extractor.dart` — 自研 PDF 图片提取
- `lib/tools/notebook/png_encoder.dart` — 自写 PNG 编码
- 翻译入口可复用 `AiService.instance.chat(slot: 'text')`

详见 `openspec/changes/document-format-conversion-matrix/` 四件套。

---

## 一、问题 A 的现象（用户实测）

从「笔记本」导入 Word 和 PDF 后，笔记正文里的图片附件块显示为：

```
┌────────────────────────────────┐
│ 📄 image2.png.png              │  ← 文件名正确识别
│    附件不可用                  │  ← 副标题
└────────────────────────────────┘
```

关键细节：
1. **副标题显示「附件不可用」**，而不是文件大小
2. **块左侧是文件图标，不是图片缩略图** —— 说明 `_isImage` 判了 false
3. 文件名是 **`image2.png.png`（双扩展名）**
4. 正文文本、标题、列表全部正常导入

两条样本笔记：
| 来源 | 标题 | noteId | 附件数 |
|---|---|---|---|
| PDF | User ID Acknowledgement Form - Zhongren Liu | `abd08a95-a756-4164-90fa-4dde8a613cdb` | 3（2 图 + 1 原文件） |
| Word | Seatrium User Manual_E&I iShop | `8dfb7568-ea11-47e7-a5a5-c06728da2bf5` | 20（19 图 + 1 原文件） |

---

## 二、核心矛盾（这是定位的起点）

**数据库侧完全正常，磁盘侧完全正常，但 UI 显示不可用。**

### 已验证正常的部分（全部实测过，非推断）

```
1. 图片字节全部落盘
   Word 笔记 20 个附件：0/20 路径缺失
   PDF 笔记 3 个附件：全部存在

2. attachments 表记录齐全
   SELECT ... WHERE note_id='abd08a95…'  返回 3 行
   每行 local_path 指向的文件 os.path.exists() = True

3. notes.delta_json 里的 attachment 节点引用正确
   PDF 笔记第 0 个节点：
   {"type":"attachment","data":{
       "attachmentId":"5260180c-c475-4cef-ad98-808d63690d32",
       "filename":"p0_361x64_8954.png",
       "sizeBytes":8954,
       "mime":"image/png"}}

4. 正文里的 attachmentId 与 attachments 表能对上
   20/20 全部匹配

5. 节点顺序正确
   PDF 笔记：[0] image1  [1] image2  [2] heading "WELCOME TO Seatrium"
   Word 笔记：[0] image1 … [151] 原 .docx（正文在中间）
```

### 具体交叉验证（可自己复现）

```bash
DB='/Users/simon/Library/Application Support/V8WorkToolbox/notebook.db'

# 附件记录在、文件在
sqlite3 "$DB" "SELECT id, filename, local_path FROM attachments WHERE note_id='abd08a95-a756-4164-90fa-4dde8a613cdb';"
# → 5260180c-…  p0_361x64_8954.png  …/abd08a95…/5260180c-c475-4cef-ad98-808d63690d32_.png

# 文件确实在
ls -la "/Users/simon/Library/Application Support/V8WorkToolbox/notebook_attachments/abd08a95-a756-4164-90fa-4dde8a613cdb/"

# 正文节点引用该 id
sqlite3 "$DB" "SELECT delta_json FROM notes WHERE id='abd08a95-a756-4164-90fa-4dde8a613cdb';"
```

---

## 三、代码路径（从哪里下手）

### 渲染链路

```
notes.delta_json（appflowy document JSON）
  → AttachmentBlockComponentWidget.initState()
      → _resolvePath()
          → NoteStore.instance.attachmentById(attId)
          → resolved = att?.localPath
          → resolved ??= _legacyCachedPath
      → setState(_resolvedPath, _resolving=false)
  → build()
      → _available = _resolvedPath != null && File(p).existsSync()
      → 副标题 = _resolving ? '解析中…' : (_available ? _formatSize() : '附件不可用')
      → _isImage 决定走 _buildThumbnail() 还是 Icon()
```

### 涉及文件与行号

| 文件 | 关键位置 |
|---|---|
| `lib/tools/notebook/ui/components/attachment_block_component.dart` | `_resolvePath()` L118–135、`_available` L138–141、`_isImage` L102–110、`build()` L144+ |
| `lib/tools/notebook/note_store.dart` | `addAttachment()` L607–630、`attachmentById()` L645–663 |

### 最可疑的一处（`catch (_) {}` 静默吞异常）

```dart
// attachment_block_component.dart L118–135
Future<void> _resolvePath() async {
  final attId = _attachmentId;
  String? resolved;
  if (attId != null && attId.isNotEmpty) {
    try {
      final att = await NoteStore.instance.attachmentById(attId);
      resolved = att?.localPath;
    } catch (_) {
      // ← 静默！DB 不可用/未初始化/查询出错，全部无声消失
    }
  }
  resolved ??= _legacyCachedPath;
  ...
}
```

**如果这里抛异常，用户看到的就是「附件不可用」，且不留任何线索。**

---

## 四、已排除的假设（别重复劳动）

| 假设 | 排除方式 | 结论 |
|---|---|---|
| 图片没提取出来 | DB + 磁盘双重核对 | ❌ 排除，19+2 张全在 |
| 双 notebook.db 分裂 | 查另一个库 | ❌ 排除，旧库无这两条笔记 |
| app 多副本 / 版本不一致 | `ps` + AOT md5 比对 | ❌ 排除，单一副本 AOT 832d9513 |
| B 库干扰 | 删除后用户确认 | ❌ 排除，删除后无任何影响 |
| 路径拼接错误 | 实测 p.basename/p.extension | ❌ 排除 |

### 关于「双扩展名」的澄清

`image1.png.png` 是**预期行为、无害**，不是 bug 的证据：

```dart
// notebook_page.dart 的临时文件名拼接
img.key = 'image1.png'        ← 来自 docx word/media/ 的文件名
File('${dir.path}/${img.key}.${_extFor(img.mime)}')
// → /tmp/v8_note_img_XXX/image1.png.png

// addAttachment 用 p.basename(临时文件) 作为 DB filename
filename = 'image1.png.png'   ← 就是它
// 落库名 = <uuid>_.png       ← 磁盘名正常
```

磁盘文件名是 `<uuid>_.png`（正常），`local_path` 指向它（存在）。双扩展名只影响显示。**它无害，可以先不管。**

---

## 五、观察障碍（为什么之前定位不了）

### release 构建下 `debugPrint` 是 no-op

```dart
// main.dart 的 runAppWithErrorHandling（上一轮 L5 加的）
debugPrint('[未捕获异常] $error');   // ← release 下不输出到任何地方
```

app 的日志目录只有：
```
~/Library/Application Support/V8WorkToolbox/logs/
  ai.log              ← AI 子系统专用
  ops_gitlab.log      ← 磐石运维专用
```

**没有任何 notebook / attachment 相关日志。**

这意味着：修复前必须先建立观测能力，否则改代码只能靠猜。

---

## 六、建议的下一步（按优先级）

### 第 1 步：加真实日志（必须先做）

找到 release 下能落盘的 logger。参考 `ai.log` 是怎么写的——那个机制在 release 下确认有效。

然后在 `_resolvePath()` 里把四个量打出来：

```dart
// 伪代码
log('[附件解析] attId=$attId');
log('[附件解析] 查表结果=${att != null ? "命中" : "null"}');
log('[附件解析] local_path=${att?.localPath}');
log('[附件解析] existsSync=${_available}');
log('[附件解析] _isImage=$_isImage mime=${_mime}');
```

**关键：catch (_) {} 里也要打**，把异常和 stack trace 写进去。

### 第 2 步：区分失败原因（改文案）

现在「附件不可用」一句话涵盖三种完全不同的失败：

```
1. attId 为空，或查表抛异常
2. 查到了但 local_path 为空
3. local_path 有值但文件不在磁盘
```

分别显示「附件记录缺失」「文件不在磁盘」等，用户回报时就能直接定位。

### 第 3 步：验证 _isImage 为何为 false

截图中块左侧是文件图标而非缩略图，说明 `_isImage` 返回 false。但节点 JSON 里明明有 `"data": {"mime": "image/png"}`。

```dart
bool get _isImage {
  final m = _mime;   // node.attributes[AttachmentBlockKeys.mime] as String?
  if (m != null && m.isNotEmpty) return m.startsWith('image/');
  ...
}
```

需要确认 `node.attributes` 是否正确映射到 JSON 的 `data` 字段。appflowy_editor 0.1.12 的 `Node.fromJson` 把 `attributes` 读进 `_attributes`，但若 JSON 用的是 `data` 键，可能走了 `_normalizeJsonNodeData` 的转换路径——这个转换是否覆盖了 attachment 节点，需要实跑验证。

**这也是最可能的根因**：如果 `_mime` 读不到，`_isImage` 会退回扩展名判断，而 `filename` 是 `p0_361x64_8954.png`（扩展名 png）—— 那扩展名判断应该返回 true。所以 `_isImage` 为 false 说明扩展名判断也没走到，或者 filename 那时还没值。**这条推理链必须靠日志证实，不要继续推断。**

### 第 4 步：修复后回归

```bash
flutter analyze
flutter test  # 特别是 attachment_block_image_test.dart
./scripts/deploy_local.sh
```

然后重新导入 Word + PDF，验证图片缩略图出现、副标题显示文件大小。

---

## 七、测试现状（哪些测试已经被骗过）

已有测试全绿，**但它们没能抓住这个问题**：

```
test/docx_to_markdown_test.dart          11 过（含 5 个图片测试）
test/pdf_image_extractor_test.dart       12 过
test/note_image_placeholder_replace_test.dart  3 过
test/attachment_block_image_test.dart     4 过
```

`attachment_block_image_test.dart` 里的 widget 测试**是过的**，它构造了 `mime: image/png` 的节点并断言 `find.byType(Image)` 命中。但真实导入的笔记不行。

差异在于：
- 测试用 `placeholderToAttachmentJson()` 直接造节点
- 真实链路是 `replacePlaceholderWithAttachment()` 从 markdown 占位替换而来

**建议补一个端到端测试**：走完整导入链路（`_extractMarkdownWithImages` → `replacePlaceholderWithAttachment` → 构造 widget → 断言渲染），而不是每一步分开测。

另外注意到一个历史教训：曾经有一个「新增失败」最后发现是 flutter test 首次编译缓存导致的假阳性。**改测试时注意对比基线**（当前失败基线见 `/tmp/base_fails.txt` 的思路：用 `git stash` 对照要在缓存都热的状态下做）。

---

## 八、相关文件清单

### 本次改动涉及（git status）

```
M lib/tools/notebook/appflowy_codec.dart
M lib/tools/notebook/docx_to_markdown.dart
M lib/tools/notebook/pdf_to_markdown.dart
M lib/tools/notebook/ui/components/attachment_block_component.dart
M lib/tools/notebook/ui/notebook_page.dart
?? lib/tools/notebook/pdf_image_extractor.dart  (新增)
?? lib/tools/notebook/png_encoder.dart          (新增)
```

### 测试

```
test/docx_to_markdown_test.dart              (已扩充图片测试)
test/pdf_image_extractor_test.dart           (新增)
test/note_image_placeholder_replace_test.dart (新增)
test/attachment_block_image_test.dart        (新增)
```

### Spec / 任务

```
openspec/changes/notebook-attachment-preserve-and-document-translate/
  proposal.md / design.md / tasks.md / specs/...
```

---

## 九、已知限制（不影响当前问题，但要知道）

PDF 图片提取器的 `unrecoverable` 路径未在真实文件上触发过。已在一个真实 PDF
（`User ID Acknowledgement Form - Zhongren Liu.pdf`，PDF 1.7 + /XRef + /ObjStm）
上验证过：2 张图全部提取成功，`file` 工具确认产物合法。

但以下情况会标 unrecoverable（不产出错图）：
- `/DecodeParms` 预测器
- `DeviceGray` / `DeviceCMYK` / ICCBased
- 非 8-bit 位深
- CCITT / LZW / JPX 过滤器
- 加密 PDF（抛 `PdfEncryptedException`）

---

## 十、给下一个 AI 的一句话总结

> **这个问题有两件事要做，A 是 B 的前置。**
>
> **问题 A（图片渲染 failed）**：图片字节、DB 记录、节点引用三者全部验证正确，
> 但 `AttachmentBlockComponentWidget` 显示「附件不可用」且不走 `_isImage` 分支。
> `_resolvePath()` 里的 `catch (_) {}` 把真正的失败原因吞了，而 release 下没有日志。
> **先加日志暴露真实失败点，不要继续静态推断——推断在这个问题上已经被骗过三次。**
>
> **问题 B（一键转换，0/44 未开工）**：四件套已备好且 validate 通过，
> 矩阵在 §零。但它依赖 A 修好——B 要求「排版与图片保持原样」，
> 而图片当前连显示都做不到。**先修 A，再开工 B。**
