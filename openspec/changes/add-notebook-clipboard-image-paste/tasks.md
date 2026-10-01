## 1. 剪贴板图片服务（独立于 UI，可单测）

- [x] 1.1 新建 `lib/tools/notebook/services/clipboard_image_service.dart`：封装 macOS 剪贴板位图探测（`osascript` + `class PNGf`，写临时文件后读回），带 5s 超时；探测不到位图时返回 null 让调用方试下一种来源，探测过程本身异常才返回 `bitmapReadFailed`
- [x] 1.2 同一服务内实现图片 URL 识别与下载：只认扩展名就是图片的 URL，下载后校验 content-type 或魔数、限 32MB、20s 超时；`httpClientFactory` 可注入（`flutter_test` 会把全局 HttpOverrides 换成恒返 400 的 mock，不注入就注入不到真实响应）
- [x] 1.3 单测：位图探测三条路径——成功（含 `ownedByService: true`）、无位图（回落而非报错）、进程崩溃（`bitmapReadFailed`）。`osascript` 用注入的进程执行器，不打真实系统剪贴板
- [x] 1.4 单测：URL 分支四条——真 PNG 成功、404 带状态码细节、`text/html` 冒充图片被拒、扩展名不匹配根本不去下载。原计划的本地 `HttpServer` 改为 `MockClient`：`flutter_test` 拦 HttpClient 恒返 400，起真服务器也拿不到正确状态码
- [x] 1.5 单测：本地图片路径分支三条——存在的 `.png` 成功且 `ownedByService: false`（用户原件不许删）、非图片扩展名、不存在的路径

## 2. 接管编辑器粘贴命令

- [x] 2.1 给 `note_editor.dart` 的 `AppFlowyEditor` 显式传 `commandShortcutEvents`：`standardCommandShortcutEvents.filter((e) => e != pasteCommand && e != pasteTextWithoutFormattingCommand)` 追加我们自己的 `⌘V`。按身份过滤而非下标：包升级时符号不存在是编译错误而不是静默行为改变
- [x] 2.2 删除 `note_editor.dart` 的 `CallbackShortcuts` 死绑定（它是当前失效的直接原因，留着会误导后来者），原处留注释说明粘贴改从命令表接管
- [x] 2.3 在新 handler 里实现接管后的纯文本粘贴：`deleteSelectionIfNeeded()` → 继承 `getDeltaAttributesInSelectionStart()` → URL/电话识别并经 `transaction.formatText` 写 `href`（与接管前包内写法一致，该方法在 Transaction 上而非 EditorState 上）→ 按行拆 `paragraphNode` → `pasteSingleLineNode`/`pasteMultiLineNodes`
- [x] 2.4 单测（`test/note_editor_paste_text_test.dart`，9 例）：单行续写、空段整段替换、多行合并当前段再拆、CR 剥除与尾空格修剪、URL 保持纯文本、选区属性继承、选中区被替换。断言全部来自读接管前包内实现得出的契约（`pasteSingleLineNode` 的"空段才整替换"、`pasteMultiLineNodes` 的"当前段并入首节点"），**不是跑出来的**——那个 handler 是包内私有的，调不到。契约与实际行为的分歧见下
- [ ] 2.5 `⌘⇧V` 随 `pasteTextWithoutFormattingCommand` 一并移除，落到同一 handler（design Decision 3：剪贴板只能读到文本，两个命令本就等价）

## 3. 图片粘贴接入笔记

- [x] 3.1 新 handler 的分派顺序：`_handlePaste` 先 `readImage()`，拿到图就走图片分支并 `return`；`notAnImage` 才落到 `_pastePlainText`。图片优先于文本
- [x] 3.2 拿到的图片经 `NoteStore.saveAttachment` 落盘（与「插入图片」按钮同一个 API、同一个扁平目录），插入用 `imageNode(url: path)`，不用附件块
- [x] 3.3 用 handler 收到的 `state` 参数插入，不是 `_editorState` 字段——顺手消掉一处隐式耦合
- [x] 3.4 图片归属当前打开的笔记（`widget.note!.id`），不是上一次打开的笔记

## 4. 工具栏按钮与失败反馈

- [x] 4.1 `note_editor_toolbar.dart` 新增「粘贴图片」按钮（`content_paste` 图标 + tooltip「粘贴剪贴板中的图片 (同 Cmd+V)」），点击走与 `⌘V` 完全相同的 `_handlePaste(state)`
- [x] 4.2 四类失败各有各的话：`nothingPasteable` 静默（用户可能就想粘文字，交给文本分支）、`bitmapReadFailed` 提示授权、`downloadFailed` 带原因、`tooLarge` 说上限；落盘失败单独一条。`_describeImageFailure` 单点持有文案
- [x] 4.3 失败路径都不碰文档——`_insertImageAtCursor` 只在 `saveAttachment` 成功返回后才调；失败即 return，正文保持原状
- [x] 4.4 图片 URL 下载不走应用代理（design Decision 5），服务层已注释原因，避免后来者误判为 bug

## 5. 测试与验证

- [x] 5.1 单测：剪贴板同时有位图与图片 URL 时，取位图（spec 的优先级场景）。加在 `clipboard_image_service_test.dart` 的 bitmap 组，两路剪贴板都 stub 上
- [x] 5.2 运行 `flutter analyze` 与全量测试，确认无回归——`flutter analyze lib/` 零 error；全量 `+1005 ~3 -13`。失败集合与本次改动前**逐字相同**（10 个文件、13 个用例，全是既有的 notebook 编辑器渲染/表格交互/doc_audio 落盘失败），通过数从 976 涨到 1005，新增的 29 个用例全过、零回归
- [ ] 5.3 实机验证：微信截图后 `⌘V` 进笔记 → 图片内联显示、关闭重开仍在、和「插入图片」按钮的结果在存储位置上找不出差别
- [ ] 5.4 实机验证：浏览器复制图片 → `⌘V` → 同样内联显示
- [ ] 5.5 实机验证：剪贴板无图片时 `⌘V` → 文字粘贴行为与接管前一致（多行、链接识别、选区属性）
- [ ] 5.6 实机验证：断开网络后从浏览器复制的图片 URL `⌘V` → snackbar 说明拉取失败且正文未被改坏
- [ ] 5.7 实机验证：`⇧⌘4` 系统截图、Preview 复制、QQ 截图三种来源各试一次，结果一致

## 6. 部署

- [x] 6.1 运行 `./scripts/deploy_local.sh` 并重新启动应用——构建、签名、替换、启动全部通过，新实例存活
- [x] 6.2 核对新构建的 AOT 快照已变化、strict 签名校验通过——AOT `6667bf1b` → `74e29632`，strict 校验通过，词典桥仍监听 8797（启动链未被本次改动破坏）
