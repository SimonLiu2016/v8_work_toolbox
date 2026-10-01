## 1. 深链协议：mode 参数 + vocab host

- [x] 1.1 `macos/Runner/AppDelegate.swift` 的 `case "lookup"` 解析 `mode` 查询参数，与 `text` 一起经 `contextServicesChannel` 透传（保持 `text` 仍可用 —— 旧格式兼容）
- [x] 1.2 同文件新增 `case "vocab"`：取 `text`，透传 `addToVocab` 方法调用（不打开任何窗口）
- [x] 1.3 `lib/services/context_services_bridge.dart`：`onLookup` 改为带 `mode` 具名参数（默认 `'dict'`）；新增 `onAddToVocab`
- [x] 1.4 `lib/main.dart`：`onLookup` 转发 `mode` 给 `LookupWindowLauncher.open`；`onAddToVocab` 走 `VocabStore` 加词（先 `existsWord` 判重）
- [x] 1.5 `LookupWindowLauncher.open(query, {mode})`：把 mode 编进子窗口 arguments（如 `lookup:ai:<text>`），保持 `lookup:` 前缀可供匹配
- [x] 1.6 `LookupPanelView` 接 `initialMode`：`initState` 按 mode 选 `_doLookup` 或 `_forceAi`；未知 mode 回落 dict
- [x] 1.7 单测（`test/lookup_start_mode_test.dart`，5 例全过）：`ai`→AI、缺省/空/null→dict、未知值回落、大小写与空格容错单测：mode 解析 —— `ai` 走 `_forceAi`、缺省走 `_doLookup`、未知值回落 dict（把"该调哪个方法"抽成可测的纯函数而非在 initState 里分支）

## 2. 扩展侧两个按钮

- [x] 2.1 `content.js` 的「问 AI 深度解析」深链改为 `v8toolbox://lookup?text=…&mode=ai`，并注释说明少了这个参数会发生什么
- [x] 2.2 `content.js` 的「加入词本」深链改为 `v8toolbox://vocab?text=…`
- [x] 2.3 同步按钮的确认文案：「加入词本」改为"已加入生词本 ✓"，不再写"已呼起生词本"（原文案描述了一个不存在的动作）
- [x] 2.4 `node --check` 两个 js 文件均通过
- [x] 2.5 顺带修正 spec 与 design 均未回答的问题：深链加进来的词条只有单词、无释义（spec 原只写"the word is added"，没说释义）。决策记为 Decision 1a —— 不加词典查询（既违背 spec 的"不查词典"，且入口本就是"词典未收录"，再查也是空），UI 上标"待补充"留给后续 change

## 3. AI 结果渲染

- [ ] 3.1 `lookup_window.dart` 的 AI 深度解析区块：`Text(res.aiTranslation!)` → `AppMarkdownView(data: …, baseStyle: …)`
- [ ] 3.2 保持容器样式（底色、边框、标题行）不变，只换内容控件
- [ ] 3.3 确认 `AppMarkdownView` 的默认 `selectable: true` 在浮窗里可用（AI 文本要能选中复制）

## 4. 子窗口尺寸表

- [x] 4.1 改对方向：包 `onWindowCreated` 回调只给 `FlutterViewController`，`CustomWindow.init(configuration:)` 收了 config 却不存，NSWindow 上也拿不到 `arguments` —— 原生侧**无法知道自己在给哪种窗口定尺寸**，Swift 尺寸表这条死路已在 design Decision 3 记明（含"为何初稿误判 window_manager 不可靠"：项目自己 `_setupWindowStyle()` 就在子进程用了它 4 次）
- [ ] 4.2 `macos/Runner/MainFlutterWindow.swift` 的 `setOnWindowCreatedCallback`：删掉无条件 `setFrame(screen.visibleFrame)`，保留透明标题栏 / `fullSizeContentView` / `isMovableByWindowBackground` / `minSize` 等样式设置
- [ ] 4.3 Dart 侧各窗口入口自己 `windowManager.setSize(...)`：`lookup:` 420×520、`note:` 900×650、`notebook` 1100×700、`ops-tool` 1200×800、`password-vault` 900×600
- [ ] 4.4  declarate 尺寸要与窗口内容密度匹配，不是拍脑袋 —— 浮窗本就设计成 420×520（`configureLookupWindow` 一直在用这个值），其余按主窗口 1100×700 的比例与各工具面板宽度推

## 5. 测试与验证

- [ ] 5.1 运行 `flutter analyze` 与全量测试，确认零回归（失败集合应与改动前逐字相同）
- [ ] 5.2 实机：浏览器选中未收录词 → 点「问 AI 深度解析」→ 窗口**直接**出 AI 分析，无"词典中未收录"中间态
- [ ] 5.3 实机：点「加入词本」→ 不开窗，词直接进生词本（切回主窗口的生词本页能看到 —— 实时刷新属另一个 change，本项只验"确实加进去了"）
- [ ] 5.4 实机：AI 结果含 markdown（列表/加粗/代码）时渲染为格式化文本，无裸语法字符
- [ ] 5.5 实机：查词浮窗 420×520 不再铺满屏幕；笔记本/密码/运维/单篇笔记子窗口尺寸符合各自声明值
- [ ] 5.6 实机：`⌘D` 热键路径的浮窗行为与深链一致（都 420×520，热键那条仍跟随光标）

## 6. 部署

- [ ] 6.1 运行 `./scripts/deploy_local.sh` 并重新启动应用
- [ ] 6.2 核对新构建 AOT 快照已变化、strict 签名校验通过
- [ ] 6.3 浏览器侧需重载扩展（`extensions/` 改了）
