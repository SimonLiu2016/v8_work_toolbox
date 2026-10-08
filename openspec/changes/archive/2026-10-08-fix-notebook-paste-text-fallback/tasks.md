## 1. 让"没有图片"成为一个可判别的结局

- [x] 1.1 记录当前测试基线：全量 `flutter test`，保存通过/失败集合，供 4.1 对比（上一个 change 的 5.2 用过同一手法：失败集合须逐字相同才算零回归）。基线记在 `test-baseline.md`：1343 passed / 3 skipped / **20 failed / 13 文件**，全量日志 `/tmp/v8_baseline_full.log`
- [x] 1.2 ✅ `ClipboardImageResult` 新增可选 `clipboardText` 字段 + 同名 getter。`nothingPasteable` 的三处产出（空文本、路径不存在、扩展名不符）都带上原文；**拿到图片时为 null**（那条路没读文本）。三条取图分支与失败分类未动
- [x] 1.3 ✅ 反过来做了更彻底的一步：`_PasteOutcome` 从三态**缩为两态**（`handled`/`failed`），"没有图片"根本不进这个 enum——分派直接从 `readImage()` 的结果区分。bug 的成因正是"一个值表示两件事"，保留三态只会把歧义换个地方。事故全貌记在 `handleClipboardPaste` 的文档注释里
- [x] 1.4 ✅ 分派逻辑现位于顶层 `handleClipboardPaste`：`asSuccess()` → 图片分支；`asFailure()` 且非 `nothingPasteable` → 气泡 + 不动文档；其余 → 用 `result.clipboardText` 走文字分支。`NoteEditorState._handlePaste` 只负责读剪贴板 + 接气泡，不再有自己的判断

## 2. 文本分支复用已读到的剪贴板内容

- [x] 2.1 ✅ 文字分支直接吃 `result.clipboardText`，`Clipboard.getData` 从 `note_editor.dart` 里彻底消失。剪贴板全程只读一次
- [x] 2.2 ✅ `text == null || text.isEmpty` → `handleClipboardPaste` 返回 false（"什么都没做"），无插入、无气泡。单测覆盖
- [x] 2.3 ✅ `clipboardTextReader` 现在是唯一的剪贴板文本入口（原来 widget 里那条 `Clipboard.getData` 绕过它）。`readImage()` 的每个 non-bitmap 出口都必然读过它，读到的内容不再被丢弃——原来的死代码变成了活数据

## 3. 按键不再被无条件吞掉 + 补回 ⌘⇧V

- [x] 3.1 ✅ `_runPasteCommand`：`widget.note == null` 返回 `ignored`（什么都做不了，别吃按键）。**一个不能省的区别**："粘贴结果为空"要等 `readImage()` 的 await 才知道，而按键处理是同步的，所以那一层无法反映进返回值——它由 `handleClipboardPaste` 的 false 与气泡兜底。这个局限写在了 `_runPasteCommand` 的注释里，没有假装成全覆盖
- [x] 3.2 ✅ 滤掉的不再包含 `pasteTextWithoutFormattingCommand`（它已从命令表消失），新增 `'v8 custom paste as plain text'`（`ctrl+shift+v` / `cmd+shift+v`）指向同一个 `_runPasteCommand`；注释说明两者为何等价
- [x] 3.3 ✅ 删除。`flutter analyze` 不再报 `unnecessary_import`

## 4. 分派层测试（本次的重点，不是叶子函数）

- [x] 4.1 ✅ `test/note_editor_paste_text_test.dart` 新增 `handleClipboardPaste 分派层` 组，**6 例全部四条出路**：
  - 纯文字 → 文字真的进正文（本 bug 的回归测试，最要紧的一条）
  - 多行文字 → 按行拆段
  - 剪贴板空 → 什么都不做、不弹气泡、文档不变
  - 取图真失败 → 气泡带原因（含 '404'）、文档不动
  - 位图 → 插 image 块、文字分支没被走到
  - 位图与文字同时在 → 图片优先
  - 另加：图片落盘失败 → 气泡 + 不留下半个图片块
  - 纯文字、无任何图片形态 → 文字真的进了文档（spec 的 "Plain text is pasted" scenario，即本次 bug 的回归测试）
  - 剪贴板有位图 → 走图片插入，且不插入文字
  - 剪贴板既无文字也无图片 → 文档不变、不弹气泡
  - 文字与位图同时在 → 图片优先
- [x] 4.2 ✅ 这条的**前提**由结构保证而非计数器：`handleClipboardPaste` 收到的 `ClipboardImageResult` 是外部传进来的，它自己完全不读剪贴板——文字分支吃 `result.clipboardText`。所以"分派层只读一次剪贴板"是编译期性质，不需要计数断言。真正的单次读取在服务层，由 `test/clipboard_image_service_test.dart` 新增的 4 例覆盖（见 4.5）
- [x] 4.3 ✅ `act == false` 就是这条断言（"没东西可粘时这一下不算处理过"），在"剪贴板既无文字也无图片"和"取图失败"两例里都测了。`_runPasteCommand` 的 `KeyEventResult` 未直接测——它需要 widget 上下文，属实机范围（6.3-6.7）
- [x] 4.4 ✅ 走了这条：分派决策提到顶层 `@visibleForTesting Future<bool> handleClipboardPaste(...)`，`_handlePaste` 瘦身成"读剪贴板 + 接气泡"。**顺带的两个注入点**（不这么做图片分支测不了）：`ImageSaver saveImage` 参数（默认走 `NoteStore.saveAttachment`，测试传替身，免去为验一条分派初始化整座数据库）、`onError` 回调（测试收消息，替代 `ScaffoldMessenger`）。**未能覆盖、必须实机确认的**：`_runPasteCommand` 的按键归属、`⌘⇧V` 键位绑定、工具栏按钮路径——这三条都要真实 widget 树
- [x] 4.5 ✅ 既有 9 个 `insertPlainTextPaste` 用例全过（本文件开头三组）；`clipboard_image_service_test.dart` 20+ 例全过，并新增 4 例 `failure carries the clipboard text`（普通文字/非图片路径/空剪贴板/取到图片时不带文本）。两文件合计 32 例全绿

## 5. 文档与 spec 一致性

- [x] 5.1 ✅ `insertPlainTextPaste` 的文档注释改成"选中区删除 → 属性继承 → 按行拆段 → 单/多行插入"，并显式写明**没有** URL/电话识别那一步、理由指向同函数的 `:55-` 注释块
- [x] 5.2 ✅ `notAnImage` 已不复存在（三态缩为两态）。它留下的痕迹是一段事故记录，写在 `handleClipboardPaste` 的文档注释里：notAnImage 无人生产、文字分支失效一个月、29 个单测全绿——这段就是"这个 bug 长什么样"
- [x] 5.3 ✅ 同 5.2：事故全貌记在 `handleClipboardPaste` 文档注释 + 粘贴区 section 注释（含"一条读剪贴板的路、两个出口"的 ASCII 图）+ 测试文件顶部的两组证据边界说明。三处互相引用

## 6. 验证与部署

- [x] 6.1 ✅ 1343→1355 passed / 3 skipped / **20→19 failed，新增失败 0**。19 个失败与基线逐字相同；唯一消失的 `msf_rpc_service_test` 单独重跑通过（既有 flaky，与本 change 无关）。对比表写进 `test-baseline.md`
- [x] 6.2 ✅ `flutter analyze lib/`：**0 error**。两个改动文件单独 analyze：`No issues found`。163 个 info/warning 全部是既存的（`withOpacity` 弃用、`unnecessary_import` 等，分布在 slimmer / doc_audio 等未触碰文件）
- [x] 6.3 ✅ 用户实机确认：新建笔记 → 正文设光标 → `⌘V` 粘文字 → 文字出现在光标处（本 bug 主场景，修复生效）
- [x] 6.4 ✅ 用户实机确认：`⌘V` 粘截图仍为内联图片块（修文字没碰坏图片）
- [x] 6.5 ✅ 用户实机确认：多行文字按行拆段；选中后粘贴命中替换语义
- [x] 6.6 ✅ 用户实机确认：粘贴 URL 保持纯文本，未变成链接
- [x] 6.7 ✅ 用户实机确认：`⌘⇧V` 与 `⌘V` 行为一致（文字与图片各一次）
- [x] 6.8 ✅ `./scripts/deploy_local.sh` 完整跑通：clean → release build → 注入 mihomo (f4b5fd41) → ad-hoc 重签 → 替换 → 启动，`DEPLOY_EXIT=0`。四项关卡全过：`codesign -v --strict` 通过、entitlements 双 key 在签名内、AOT 快照 `b1c18825…` → `428d5c6a…`、新实例 PID 5279 存活且词典桥监听 127.0.0.1:8797
