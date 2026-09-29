## 1. 原生层：macOS Services + 热键基础设施

- [x] 1.1 在 `macos/Runner/Info.plist` 的 `NSServices` 数组中注册「查词 — V8」和「保存笔记 — V8」两条服务，配置 `NSSendTypes`（`NSStringPboardType`）和 `NSMessage` 回调方法名
- [x] 1.2 在 `AppDelegate.swift` 中实现 `@objc func handleLookupService(_:userData:error:)` 和 `@objc func handleSaveNoteService(_:userData:error:)` 两个 Services 回调方法，从 `NSPasteboard` 读取选区文字
- [x] 1.3 新增 `FlutterMethodChannel`（`v8_work_toolbox/context_services`），通过该通道向 Flutter 层发送 `lookup` 和 `saveNote` 事件及文字载荷
- [x] 1.4 在 `AppDelegate.swift` 的热键注册逻辑中新增 `⌥D`（keyCode: 2, mod: optionKey）和 `⌥S`（keyCode: 1, mod: optionKey）热键注册，处理函数读取剪贴板并通过 `context_services` 通道分发
- [x] 1.5 实现热键触发时的「保存剪贴板 → 模拟 ⌘C → 等待 60ms → 读取 → 恢复剪贴板」逻辑，封装为 `SimulatedCopy` 辅助函数

## 2. 原生层：AppleScript URL 读取

- [x] 2.1 在 `AppDelegate.swift` 中实现 `getFrontBrowserURL()` 方法：检测前台 App bundle ID，匹配 Chrome（`com.google.Chrome`）/Safari（`com.apple.Safari`）/Firefox（`org.mozilla.firefox`），执行对应 AppleScript，返回 URL 字符串或 nil
- [x] 2.2 将 `getFrontBrowserURL()` 结果通过 `context_services` 通道暴露为 `getBrowserUrl` 方法供 Flutter 调用

## 3. Flutter 层：上下文服务桥接

- [x] 3.1 新建 `lib/services/context_services_bridge.dart`，监听 `v8_work_toolbox/context_services` 通道，将 `lookup` 和 `saveNote` 事件分发至对应处理器
- [x] 3.2 在 `main.dart` 或应用初始化中注册 `ContextServicesBridge`，确保应用在后台托盘模式下也能接收事件

## 4. 数据库扩展

- [x] 4.1 在 `lib/tools/notebook/note_database.dart` 的 `VocabEntries` Drift 表定义中新增所有字段（id、word、phonetic、audioUrl、partOfSpeech、definitions、examples、phrases、sourceContext、masteryLevel、tags、addedAt），并更新 `SchemaVersion`
- [x] 4.2 在现有 Notebooks 表中新增 `isDefaultForCapture` 整数字段（DEFAULT 0），编写相应 Drift migration
- [x] 4.3 运行 `dart run build_runner build` 重新生成 `note_database.g.dart`

## 5. 查词服务

- [x] 5.1 新建 `lib/tools/lookup_panel/services/dictionary_service.dart`：封装 Free Dictionary API（`https://api.dictionaryapi.dev/api/v2/entries/en/<word>`）调用，解析 JSON 返回 `DictionaryResult` 模型（含 phonetic、audioUrl、meanings 列表）
- [x] 5.2 新建 `lib/tools/lookup_panel/services/youdao_service.dart`：封装有道词典 API 调用，提供英中翻译补充
- [x] 5.3 在 `lib/tools/lookup_panel/services/lookup_coordinator.dart` 中实现选词路由逻辑：输入词 token 数 ≤3 → 先走词典 API，失败/无结果 → fallback 至 AI；>3 词 → 直接走 AI 翻译；缓存近期查词结果（`Map<String, DictionaryResult>` 内存缓存，上限 100 条 LRU）
- [x] 5.4 实现 AI 翻译调用（复用 `ai_service.dart`），构建结构化 prompt 请求翻译与词义解析

## 6. 查词浮窗 UI

- [x] 6.1 新建 `lib/tools/lookup_panel/ui/lookup_window.dart`：通过 `desktop_multi_window` 创建子窗口，在原生层将其窗口 class 配置为 `NSPanel`，设置 `floatingPanel` 级别，尺寸约 420×560
- [x] 6.2 实现查词面板主体 `LookupPanelView`：搜索栏（上方）、结果内容区（滚动）、底部操作栏（「添加生词本」「问 AI」「保存笔记」按钮）
- [x] 6.3 实现结果内容区各展示块：词头 + 音标 + 发音按钮、词性分组 + 释义列表、例句区、词组区、AI 翻译区（条件显示）
- [x] 6.4 实现发音按钮：点击时调用 `audioplayers` 播放 `audioUrl`；URL 为空时按钮置灰
- [x] 6.5 实现「已添加」状态：查词面板打开时检查当前词是否已在生词本，若已存在则「添加生词本」按钮显示「已在生词本」
- [x] 6.6 处理浮窗的 Escape 关闭和失焦自动关闭行为

## 7. 生词本：数据层

- [x] 7.1 新建 `lib/tools/vocab_book/services/vocab_store.dart`：基于 Drift 提供 `VocabEntry` 的 CRUD 操作（insertEntry、deleteEntry、deleteEntries、updateMasteryLevel、queryAll、queryByTag、existsWord）
- [x] 7.2 新建 `lib/tools/vocab_book/models/vocab_entry.dart`：定义 `VocabEntry` 数据类（含 JSON 序列化辅助方法处理 definitions/examples/phrases/tags 字段）
- [x] 7.3 在 `VocabStore` 中实现「从 DictionaryResult 构建 VocabEntry 并插入」的便捷方法

## 8. 生词本：UI

- [x] 8.1 新建 `lib/tools/vocab_book/ui/vocab_book_page.dart`：三栏布局（标签/筛选侧边栏 + 词条列表 + 词条详情），整体风格与 Notebook 工具保持一致
- [x] 8.2 实现词条列表：显示 word、词性缩写、掌握程度色标；支持点击选中、右键删除
- [x] 8.3 实现词条详情面板：展示完整词条信息（音标 + 发音按钮、词性释义、例句、词组、来源上下文、掌握程度调节器）
- [x] 8.4 实现「添加词条」入口：点击「+」按钮弹出搜索框，输入词后查询 API 并预填表单，用户确认保存
- [x] 8.5 实现批量删除：Checkbox 多选 + 底部操作栏「删除所选（N）」按钮
- [x] 8.6 实现标签筛选和掌握程度筛选侧边栏
- [x] 8.7 实现生词本设置面板（在工具页面右上角「设置」图标触发）：展示笔记本下拉列表 + 「设为默认」按钮，选择后保存至 `settings_store.dart` 中的 `vocabDefaultNotebookId` 键

## 9. 笔记捕获服务

- [x] 9.1 新建 `lib/services/note_capture_service.dart`：实现 `captureNote({required String text, required String sourceApp})` 方法，协调 HTML→Markdown 转换、URL 获取、笔记写入
- [x] 9.2 实现轻量 HTML→Markdown 转换器 `lib/services/html_to_markdown.dart`：支持 H1-H6 → `#`、p → 段落、strong/b → `**`、em/i → `*`、ul/ol/li → 列表、code → `` ` ``、pre → `` ``` ``、table → Markdown 表格、img → `![alt](src)`；其余标签剥离保留文字
- [x] 9.3 在 `NoteCaptureService` 中调用 `context_services` 桥接方法获取浏览器 URL；源 App 为浏览器时追加「来源：URL」至笔记末尾；非浏览器时弹出 URL 输入对话框
- [x] 9.4 实现「首次使用引导」：若 `captureDefaultNotebookId` 未配置，弹出笔记本选择对话框并持久化设置后再继续保存
- [x] 9.5 笔记保存成功后通过系统托盘发送通知（复用现有 `launcher_service.dart` 或原生 `NSUserNotification`/`UNUserNotificationCenter`）

## 10. 笔记本工具：设为默认捕获目标

- [x] 10.1 在 Notebook 数据模型和 `NoteStore` 中加入 `isDefaultForCapture` 字段的读写支持
- [x] 10.2 在笔记本列表右键菜单中新增「设为笔记捕获默认」选项；实现单事务：清零所有 → 设置目标为 1
- [x] 10.3 在笔记本列表中为默认捕获笔记本添加「📥」图标标注

## 11. 工具注册与入口

- [x] 11.1 在 `lib/tools/registry.dart` 中注册「生词本」工具（图标：`Icons.menu_book_rounded`，标题：「生词本」）
- [x] 11.2 在笔记捕获设置面板中提供独立的「默认笔记本」配置入口（与生词本设置并列，但存储不同键 `captureDefaultNotebookId`）

## 12. 验证

- [x] 12.1 在系统偏好设置 → 键盘 → 键盘快捷键 → 服务中确认「查词 — V8」和「保存笔记 — V8」已出现
- [ ] 12.2 在 Chrome 中选中英文单词，右键 → 服务 → 「查词 — V8」，验证查词浮窗弹出并展示词典结果
- [ ] 12.3 在 Safari 中选中中文段落，按 `⌥S`，验证笔记保存成功且 URL 自动附加
- [ ] 12.4 在 Preview（PDF）中选中文字，按 `⌥S`，验证 URL 输入对话框弹出
- [ ] 12.5 在查词浮窗中点击「添加至生词本」，打开生词本工具验证词条已存在
- [x] 12.6 验证 Drift migration 在升级后不丢失已有笔记数据
