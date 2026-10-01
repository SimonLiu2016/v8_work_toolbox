## Why

浏览器划词查词这条链上有四处断裂，暴露的是同一类问题：**意图在传递途中被丢掉**。

用户在浏览器里已经明确表达了意图——「我要 AI 分析这个词」「把这个词加进生词本」——但深链只带一个 `text` 参数，桌面端收到后一律当"普通查词"处理。于是：

- 点「问 AI 深度解析」打开窗口，转几圈后显示"词典中未收录此词"，下面又给一个「使用 AI 深度解析」按钮。用户点了两次 AI，中间还被强迫看一次词典查询的结果。
- 点「加入词本」打开的是查词窗口——按钮文案描述的动作（直接加入生词本）从来不存在，AppDelegate 里没有 vocab 深链 host。

另外两处是渲染与尺寸：

- AI 返回的是 Markdown，浮窗用 `Text()` 直接渲染，`**`、`##` 全裸在用户眼前。项目里 `AppMarkdownView` 已经是四处共用的标准组件，唯独查词浮窗没用它。
- 浮窗铺满整个屏幕可见区（实测 1680×921，屏幕逻辑分辨率 1680×1050）。根因是 `MainFlutterWindow.swift` 的 `setOnWindowCreatedCallback` 对**所有**子窗口无条件执行 `setFrame(screen.visibleFrame)`。这不是查词浮窗一个窗口的问题——笔记本、密码工具、运维工具、单篇笔记四个子窗口全被撑满，只是查词浮窗设计成 420×520 的贴口气泡，落差最明显。

## What Changes

- **给查词深链加意图参数**：`v8toolbox://lookup?text=…&mode=ai`（默认 `mode=dict`，保持既有调用方行为不变）。浏览器气泡的「问 AI 深度解析」按钮发 `mode=ai`，「在桌面端打开」「右键查词」仍发默认。
- **新增 vocab 深链**：`v8toolbox://vocab?text=…`。浏览器气泡的「加入词本」走它——只加词、不开窗、不查词典。这是两个 change 合入后第一个可用的"零 UI 打扰"入口。
- **AI 结果改用共享 Markdown 组件**：查词浮窗的 AI 深度解析区块从 `Text()` 换成 `AppMarkdownView`，与 AI 助手、资讯快报、磁盘报告、笔记问答一致。
- **子窗口各自声明尺寸**：`MainFlutterWindow.swift` 的创建回调不再无条件 `setFrame(screen.visibleFrame)`，只保留样式设置；尺寸改由每个窗口的 Dart 入口自己 `windowManager.setSize(...)` 声明（`lookup:` 420×520、`note:` 900×650、`notebook` 1100×700、`ops-tool` 1200×800、`password-vault` 900×600）。没有原生尺寸表的原因很实在：包的 `onWindowCreated` 回调只给 `FlutterViewController`，拿不到 `arguments`，原生侧根本不知道自己在给哪种窗口定尺寸。

## Capabilities

### New Capabilities

- `browser-lookup-deep-link`: 浏览器伴侣与桌面端之间的查词/生词深链协议——`mode` 参数表达"直接问 AI"的意图，`vocab` host 表达"只加词不开窗"；以及深链打开的子窗口必须落在为该前缀声明的尺寸上，而不是铺满屏幕。

### Modified Capabilities

- `browser-companion-extension`: 「问 AI 深度解析」按钮发 `mode=ai`；「加入词本」改走 `vocab` 深链，不再打开查词窗口。

（两处更正：① 初稿把「AI 结果做 Markdown 渲染」归给 `lookup-panel`——该能力不存在，渲染要求已并入本次新建的 `browser-lookup-deep-link`。② 初稿把 `context-menu-services` 列为 Modified——查过主 spec，**没有任何能力描述过 `v8toolbox://` 深链协议**，`v8_work_toolbox/context_services` 通道也不在 specs 里。深链从未被规范化，所以它的要求（mode 参数、vocab host、子窗口尺寸）一并放进 `browser-lookup-deep-link`，而不是再造一个孤立能力。）

## Impact

- **原生层**：`macos/Runner/MainFlutterWindow.swift`（删掉无条件 `setFrame(screen.visibleFrame)`，保留样式）、`macos/Runner/AppDelegate.swift`（`lookup` 解析并透传 `mode`；新增 `vocab` case）。
- **Flutter 层**：`lib/services/context_services_bridge.dart`（`onLookup` 带 `mode`、新增 `onAddToVocab`）、`lib/main.dart`（接线）、`lib/tools/lookup_panel/ui/lookup_window.dart`（`initialMode` + `AppMarkdownView`）、`lib/main.dart` 或合适的桥接点（vocab 加词实现）。
- **扩展层**：`extensions/v8-browser-companion/content.js`（两个按钮的深链）。
- **依赖**：无新增。`AppMarkdownView` 已在项目中。
- **数据**：无 schema 变更。生词本插入复用既有 `VocabStore.insertFromDictionary`。
- **非目标**：不做"真·实时跨窗口刷新"（那是 `refresh-vocab-book-on-window-focus` 的范围）；不做词典/Markdown 内容本身的质量优化；不改 `⌘D` 热键路径的窗口定位逻辑（它已经跟随光标且正确）。
