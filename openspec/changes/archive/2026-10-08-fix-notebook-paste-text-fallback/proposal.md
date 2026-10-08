## Why

笔记本正文按 `⌘V` 粘贴复制的文字没有任何反应——无插入、无气泡、无日志。图片粘贴反而是好的。这不是"新建笔记才有"的现象：**自 `d131b75`（10-01）落地 `notebook-clipboard-image-paste` 那天起，所有笔记的文字粘贴一直是坏的**。

根因是一处枚举映射断裂，且与上一个已修的 bug 同形：`_PasteOutcome.notAnImage` 被声明、被注释描述、被 `_handlePaste` 判断，但 `_pasteClipboardImage()` 的三条 return 没有一条产生它。剪贴板里有文字时 `readImage()` 返回 `nothingPasteable`，被映射成 `failed`，`_handlePaste` 在 `note_editor.dart:493` 处提前 return，`_pastePlainText()` 成了永远执行不到的死分支。按键被我们的 handler 吞掉（`KeyEventResult.handled`），也不会交还给系统。

上一次同样的失效（`CallbackShortcuts` 绑定的 `_handlePaste` 因包内 `Focus.onKeyEvent` 抢先返回 handled，三个月一次没跑）靠"接管命令表"修好了入口，但接管后我们自己写的分派层复制了同一个错误模式：**测了叶子函数（`insertPlainTextPaste`，9 个用例全过），没测分派器（什么时候才调它）**。29 个新单测全绿与文字粘贴全线失效同时存在，说明测试缺口才是让这类 bug 活下来的土壤。

## What Changes

- **修好文字粘贴的回落**：剪贴板里没有任何图片形态时，`_handlePaste` 必须继续走纯文本分支，而不是提前 return。路线取 A+C 合并：
  - **A（最小修复）**：`nothingPasteable` 映射为 "没有图片" 而不是 "失败"——两者此前被压成同一个 `failed`，是断裂的直接位置。
  - **C（顺带收掉 TOCTOU）**：`readImage()` 判 URL / 本地路径时已经读过剪贴板全文又丢掉，随后 `_pastePlainText()` 用 `Clipboard.getData` 二次读取。改为把已读到的文本交还给调用方，文本分支不再二次读盘，也重新落回可注入的 `clipboardTextReader` 测试替身覆盖范围。
- **补上分派层测试**：对 `_handlePaste` 本身建组，喂三份剪贴板（纯文字 / 位图 / 空），断言三条出路——文字插入、图片插入、无操作且不弹气泡。这是本次事故的真正缺口，比 A 更重要。
- **修订 spec 措辞**：`notebook-clipboard-image-paste` 的 "Text pasting behaviour is preserved" scenario 写的是 "link detection ... preserved"，而接管前包内的 `maybeConvertToUrlOrPhone` 因排在 `deleteSelectionIfNeeded()` 之后、其守卫要求 `selection.isCollapsed == false` 而**恒 return false**——接管前从不产生链接。行为不变是真的，但 spec 字面承诺了一个从未存在过的行为。按实际契约（URL 保持纯文本）重写，并补一条明确"文字粘贴不得静默失败"的 scenario。
- **修正过期注释**：`note_editor.dart:546` 说接管后实现了"URL/电话识别并写成 href"，与 `:43-52` 刻意删除该分支的说明矛盾。
- **修正 `⌘⇧V` 的遗留**：`tasks.md` 2.5 声明 `⌘⇧V` 随 `pasteTextWithoutFormattingCommand` 一并移除、落到同一 handler，但代码里它被整条滤掉且没有替身——`⌘⇧V` 目前完全无响应。与 Decision 3（"两个命令本就等价"）自相矛盾，本次补齐。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `notebook-clipboard-image-paste`: 修正"剪贴板无图片时按纯文本粘贴"这条既存行为——它是该 capability 的 spec 场景，但实现从未让它生效；同时把"文字粘贴必须实际发生"写进 scenario，并把 URL 识别改写为反映真实契约（URL 保持纯文本）。
- `notebook-editor`: 编辑器粘贴命令接管后的文字粘贴行为——原 scenario 只规定了"图片优先"，未规定文字回落的可达性与不可静默失败。

## Impact

- **Flutter 层**：`lib/tools/notebook/ui/note_editor.dart`（`_handlePaste` / `_pasteClipboardImage` 的返回值映射、`_pastePlainText` 复用已读文本、`_buildCommandShortcutEvents` 补 `⌘⇧V`）、`lib/tools/notebook/services/clipboard_image_service.dart`（`readImage()` 把已读到的文本随结果交还，或新增一个轻量查询入口——取哪种由 design 定，不动三条取图来源分支的内部逻辑）。
- **测试**：`test/note_editor_paste_text_test.dart` 新增分派层组；`test/clipboard_image_service_test.dart` 视 design 选择补充 1-2 例。既有 9 个叶子函数用例与 20+ 服务用例应保持通过。
- **数据**：无 schema 变更、无迁移。图片存储路径不变。
- **依赖**：无新增。
- **回归风险**：本次只放开一条此前不执行的分支，不改变 `insertPlainTextPaste` 自身逻辑；图片粘贴路径（`handled` / 其它失败）保持不变。
