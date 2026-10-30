## Why

用户在阅读英文文档或网页时，常需要快速查词、翻译句子、积累生词、以及保存感兴趣的内容片段。目前这些操作都需要切换到外部工具，割裂了阅读体验。通过 macOS Services + 全局热键将这三类能力注入系统右键菜单，可以在任意外部 App（浏览器、PDF 阅读器、文本编辑器等）中一键触发，而无需离开当前文档。

## What Changes

- **新增 macOS Services 集成**：在 `Info.plist` 注册两条系统服务，使「查词」和「保存笔记」出现在任意 macOS App 的右键 → 服务子菜单中；在 `AppDelegate.swift` 实现服务处理方法并通过 `MethodChannel` 桥接至 Flutter。
- **新增全局热键**：`⌥D` 触发查词浮窗（D = Define），`⌥S` 触发保存笔记（S = Save），与现有 `⌥Space` 热键并列注册。
- **新增查词浮窗（Lookup Panel）**：一个常驻置顶的轻量 `NSPanel` 子窗口，展示词典查询结果（音标、发音、词性、释义、例句、词组）；选中 ≤3 个单词时优先调用词典 API，>3 个词时优先调用已有 AI 服务进行翻译；两种场景均提供切换另一来源的按钮。
- **新增生词本工具（Vocabulary Book）**：独立工具入口，使用独立 Drift 表存储结构化词条（word、phonetic、partOfSpeech、definitions、examples、phrases、sourceContext、masteryLevel、tags 等）；支持从查词浮窗一键添加，以及手动增删词条；工具设置中可指定「保存查词结果的默认笔记本」。
- **新增笔记捕获（Note Capture）**：在保存笔记时，自动通过 AppleScript 读取前台浏览器（Chrome / Safari / Firefox）地址栏 URL 并附加到笔记；对非浏览器来源，弹出小对话框提示用户选填 URL；内容尽量保留 Markdown 格式（标题、段落、粗斜体、列表、代码块）；图片以引用链接方式保存（本地文档图片转 base64 附件，网页图片保留远端 URL）。笔记保存的目标笔记本可在设置中「设为默认」。

## Capabilities

### New Capabilities

- `context-menu-services`: macOS Services 集成层——Info.plist 服务注册 + AppDelegate 处理 + MethodChannel 桥接，是查词和保存笔记两条服务的共享基础设施。
- `lookup-panel`: 查词浮窗——轻量悬浮子窗口，展示词典 API + AI 双引擎查询结果，支持播放发音、一键添加生词本、一键保存笔记。
- `vocab-book`: 生词本独立工具——结构化词条存储、列表管理、按掌握程度/标签筛选、设置默认笔记本。
- `note-capture`: 笔记捕获服务——从选区文本构建带格式笔记，附加 URL 来源（AppleScript 自动获取或手动填写），保存至用户指定默认笔记本。

### Modified Capabilities

- `notebook-tool`: 新增「设为默认笔记本（用于笔记捕获）」入口，笔记本列表支持标记一个笔记本为 Note Capture 默认目标。

## Impact

- **原生层**：`macos/Runner/AppDelegate.swift` 新增热键注册和 Services 处理；`macos/Runner/Info.plist` 新增 `NSServices` 数组；entitlements 已有 `apple-events`，无需变更。
- **Flutter 层**：新增 `lib/tools/lookup_panel/`、`lib/tools/vocab_book/`、`lib/services/note_capture_service.dart`。
- **数据库**：在现有 Drift 数据库中新增 `vocab_entries` 表；Notebook 数据模型新增 `isDefaultForCapture` 字段。
- **依赖**：查词 API 使用免费的 Free Dictionary API（英英）+ 有道 API（英中）；发音复用现有 `audioplayers`；AI 翻译复用现有 `ai_service.dart`；`desktop_multi_window` 已引入，用于浮窗渲染。
