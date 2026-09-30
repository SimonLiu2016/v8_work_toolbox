## 1. 剪贴板图片服务（独立于 UI，可单测）

- [x] 1.1 新建 `lib/tools/notebook/services/clipboard_image_service.dart`：封装 macOS 剪贴板位图探测（`osascript` + `class PNGf`，写临时文件后读回），带 5s 超时；探测不到位图时返回 null 让调用方试下一种来源，探测过程本身异常才返回 `bitmapReadFailed`
- [x] 1.2 同一服务内实现图片 URL 识别与下载：只认扩展名就是图片的 URL，下载后校验 content-type 或魔数、限 32MB、20s 超时；`httpClientFactory` 可注入（`flutter_test` 会把全局 HttpOverrides 换成恒返 400 的 mock，不注入就注入不到真实响应）
- [x] 1.3 单测：位图探测三条路径——成功（含 `ownedByService: true`）、无位图（回落而非报错）、进程崩溃（`bitmapReadFailed`）。`osascript` 用注入的进程执行器，不打真实系统剪贴板
- [x] 1.4 单测：URL 分支四条——真 PNG 成功、404 带状态码细节、`text/html` 冒充图片被拒、扩展名不匹配根本不去下载。原计划的本地 `HttpServer` 改为 `MockClient`：`flutter_test` 拦 HttpClient 恒返 400，起真服务器也拿不到正确状态码
- [x] 1.5 单测：本地图片路径分支三条——存在的 `.png` 成功且 `ownedByService: false`（用户原件不许删）、非图片扩展名、不存在的路径

## 2. 接管编辑器粘贴命令

- [ ] 2.1 给 `note_editor.dart:849` 的 `AppFlowyEditor` 显式传 `commandShortcutEvents`：`standardCommandShortcutEvents` 滤掉 `pasteCommand` 与 `pasteTextWithoutFormattingCommand`，追加我们自己的 `⌘V` 命令
- [ ] 2.2 删除 `note_editor.dart:573` 的 `CallbackShortcuts` 死绑定（它是当前失效的直接原因，留着会误导后来者）
- [ ] 2.3 在新 handler 里实现接管后的纯文本粘贴：`deleteSelectionIfNeeded()` → 继承 `getDeltaAttributesInSelectionStart()` → URL/电话识别并写入 `href` 属性 → 按行拆 `paragraphNode` → `pasteSingleLineNode`/`pasteMultiLineNodes`
- [ ] 2.4 单测：纯文本粘贴不退化——多行结构、URL 识别、电话识别、选区属性继承、选中区被替换，逐条对着接管前的行为断言
- [ ] 2.5 确认 `⌘⇧V` 落到同一 handler（与 design Decision 3 一致：内容只有文本，两个命令本就等价）

## 3. 图片粘贴接入笔记

- [ ] 3.1 新 handler 的分派顺序：剪贴板有位图 → 图片；无位图但是图片 URL → 下载后走同一条路；否则文本粘贴。图片优先于文本
- [ ] 3.2 拿到的图片经 `NoteStore.saveAttachment` 落盘（与「插入图片」按钮同一个 API、同一个扁平目录），插入用 `imageNode(url: path)`，不用附件块
- [ ] 3.3 用 handler 收到的 `editorState` 而不是 `_editorState` 字段插入——顺手消掉一处隐式耦合
- [ ] 3.4 图片归属当前打开的笔记（`widget.note!.id`），不是上一次打开的笔记

## 4. 工具栏按钮与失败反馈

- [ ] 4.1 `note_editor_toolbar.dart` 新增「粘贴图片」按钮（图标 + tooltip 说明它读剪贴板），点击走与 `⌘V` 完全相同的那条插入链路
- [ ] 4.2 每个失败阶段都有 snackbar：认不出图片 / 下载失败（含原因）/ 落盘失败；文案说明是哪一步，不共用一句「操作失败」
- [ ] 4.3 失败时编辑器保持原状，不在正文里留下半个引用
- [ ] 4.4 图片 URL 下载不走应用代理（design Decision 5），并在代码注释里写清原因，避免后来者误判为 bug

## 5. 测试与验证

- [ ] 5.1 单测：剪贴板同时有图片与文本时，插入的是图片（spec 的优先级场景）
- [ ] 5.2 运行 `flutter analyze` 与全量测试，确认无回归（重点关注编辑器相关测试）
- [ ] 5.3 实机验证：微信截图后 `⌘V` 进笔记 → 图片内联显示、关闭重开仍在、和「插入图片」按钮的结果在存储位置上找不出差别
- [ ] 5.4 实机验证：浏览器复制图片 → `⌘V` → 同样内联显示
- [ ] 5.5 实机验证：剪贴板无图片时 `⌘V` → 文字粘贴行为与接管前一致（多行、链接识别、选区属性）
- [ ] 5.6 实机验证：断开网络后从浏览器复制的图片 URL `⌘V` → snackbar 说明拉取失败且正文未被改坏
- [ ] 5.7 实机验证：`⇧⌘4` 系统截图、Preview 复制、QQ 截图三种来源各试一次，结果一致

## 6. 部署

- [ ] 6.1 运行 `./scripts/deploy_local.sh` 并重新启动应用
- [ ] 6.2 核对新构建的 AOT 快照已变化、strict 签名校验通过
