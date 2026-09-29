## Context

V8WorkToolbox 是一个 Flutter macOS 桌面应用，以托盘模式常驻后台，通过全局热键 `⌥Space` 唤起主窗口。原生层（Swift/AppDelegate）已具备：Carbon Event 全局热键注册基础设施、`FlutterMethodChannel`（`app_manager_channel`、`v8_work_toolbox/launcher`）、`apple-events` entitlement。Flutter 层已具备：Drift ORM（SQLite）、`desktop_multi_window`（子窗口）、`audioplayers`（音频播放）、`ai_service.dart`（AI 查询）、Notebook 存储与编辑器完整体系。

## Goals / Non-Goals

**Goals:**
- 通过 macOS NSServices 将「查词」和「保存笔记」注入任意外部 App 的右键菜单
- 以 `⌥D` / `⌥S` 作为高频用户的快捷触发路径
- 提供轻量置顶查词浮窗（NSPanel），展示词典 + AI 双引擎结果
- 独立生词本工具，Drift 新表，结构化存储
- 笔记捕获服务，AppleScript 自动读取浏览器 URL

**Non-Goals:**
- 移动端或 Windows/Linux 支持
- 在应用内置 WebView（外部文档场景不需要）
- SRS（间隔复习）系统——掌握程度字段留作未来扩展
- 词典 API 的付费账号管理

## Decisions

### D1：选区文字获取策略

**决策**：热键路径（`⌥D` / `⌥S`）使用「模拟 ⌘C → 读剪贴板」方案；Services 路径直接从 `NSPasteboard` 读取。

**原因**：macOS Accessibility API 读取前台 App 选区需要辅助功能权限且兼容性差（多数现代 App 限制了 AX 树暴露）。剪贴板方案无需额外权限，热键按下时先保存剪贴板旧内容，发送 ⌘C，等待 50ms 读取，恢复旧内容。

**替代方案**：Accessibility API → 已排除，权限摩擦大；要求用户手动复制 → 体验差。

---

### D2：查词浮窗窗口类型

**决策**：使用 `desktop_multi_window` 创建子窗口，在原生层将其配置为 `NSPanel` 并设置 `hidesOnDeactivate = false`、`level = .floating`。

**原因**：`NSPanel` 是 macOS 为工具悬浮窗设计的原生类型，自动置顶且不抢主窗口焦点。`desktop_multi_window` 已在项目中引入，无需增加新依赖。

**替代方案**：`window_manager` 新开窗口 → 配置更繁琐，无 NSPanel 语义；系统弹出菜单 → 内容展示空间受限。

---

### D3：词典 API 选择

**决策**：英英释义使用 [Free Dictionary API](https://api.dictionaryapi.dev/)（免费、无需 Key）；英中翻译使用有道词典 API（免费配额）作为补充。两者均支持发音 MP3 链接。AI 翻译调用已有 `ai_service.dart`。

**原因**：Free Dictionary API 返回结构化 JSON（音标、词性、定义、例句、发音 URL），完全符合浮窗展示需求，且无流控风险。

**替代方案**：Oxford / Cambridge 付费 API → 引入账号管理复杂度；全部走 AI → 返回非结构化文本，音标/发音无法获取。

---

### D4：网页 URL 获取策略

**决策**：主路径用 AppleScript（已有 `apple-events` entitlement）读取 Chrome/Safari/Firefox 前台 URL；失败时回退至弹出用户手填 URL 的小对话框。

AppleScript 模板：
```applescript
-- Chrome
tell application "Google Chrome" to get URL of active tab of front window
-- Safari  
tell application "Safari" to get URL of current tab of front window
-- Firefox（通过 osascript 执行，Firefox 支持有限，可能回退）
```

原生层识别当前前台 App 的 bundle ID，匹配浏览器后执行对应脚本；其他 App 直接进入回退路径。

**替代方案**：Accessibility API 读地址栏文本 → 兼容性差，各浏览器 AX 树不同；要求用户手动粘贴 → 体验差。

---

### D5：富文本格式转换策略

**决策**：Services 路径从 `NSPasteboard` 尝试读取 `html` 类型；热键路径模拟 ⌘C 后同样检查剪贴板是否含 HTML 数据。若有 HTML，用轻量解析器（在 Flutter 层实现）将 H1-H6、p、strong、em、ul/ol/li、code、pre、table、img 转换为 Markdown；无 HTML 则按纯文本处理，保留换行。不依赖外部 HTML 解析库，自行实现 ~200 行的有限集解析器，避免增加依赖。

---

### D6：生词本数据模型（Drift）

在现有数据库文件中新增 `vocab_entries` 表：

```dart
class VocabEntries extends Table {
  TextColumn get id => text()();                      // UUID
  TextColumn get word => text()();                    // 词/短语
  TextColumn get phonetic => text().nullable()();     // /fəˈnetɪk/
  TextColumn get audioUrl => text().nullable()();     // 发音 MP3 URL
  TextColumn get partOfSpeech => text().nullable()(); // "noun", "verb"...
  TextColumn get definitions => text()();             // JSON array
  TextColumn get examples => text()();                // JSON array
  TextColumn get phrases => text()();                 // JSON array
  TextColumn get sourceContext => text().nullable()();// 查词时的原句
  IntColumn get masteryLevel => integer().withDefault(const Constant(0))();
  TextColumn get tags => text().withDefault(const Constant('[]'))(); // JSON array
  DateTimeColumn get addedAt => dateTime()();
}
```

`definitions`、`examples`、`phrases`、`tags` 以 JSON 字符串存储，避免额外关联表。

---

### D7：Notebook 数据库扩展

在现有 Notebook 表（`note_database.dart`）中新增字段 `isDefaultForCapture INTEGER NOT NULL DEFAULT 0`。通过 Drift migration 添加，不影响现有数据。新增唯一约束在应用层（非 DB 层）强制：设置新默认时，先 UPDATE 所有行为 0，再 UPDATE 目标行为 1（单事务）。

---

### D8：新增 MethodChannel 名称

`v8_work_toolbox/context_services`：处理 Services 回调（`lookup`、`saveNote`）和热键调度（`hotkey_lookup`、`hotkey_save_note`）。避免修改现有 `app_manager_channel` 以保持关注点分离。

## Risks / Trade-offs

- **剪贴板污染**：⌥D/⌥S 使用剪贴板中转，可能短暂替换用户剪贴板内容（约 50–100ms）。缓解：保存 → 恢复旧内容；若模拟 ⌘C 后剪贴板未变化（App 阻止）则弹出空搜索框。
- **AppleScript 权限**：首次调用 AppleScript 时系统可能弹出权限对话框（隐私 → 自动化）。缓解：在设置页面提前引导用户授权；失败优雅回退。
- **Free Dictionary API 限速**：免费 API 无官方速率文档，高频查询可能被限流。缓解：本地缓存查过的词（Map 内存缓存，冷启动不持久化）；限流时自动 fallback 至 AI。
- **HTML 解析覆盖率**：自研轻量 HTML→Markdown 转换器只覆盖常用标签，复杂 DOM 结构（嵌套 table、shadow DOM 等）可能退化为纯文本。这是可接受的 trade-off，比引入重量级 HTML 解析库更合适。

## Migration Plan

1. Drift schema migration（`SchemaVersion` +1）：`ALTER TABLE notebooks ADD COLUMN is_default_for_capture INTEGER NOT NULL DEFAULT 0`；新增 `vocab_entries` 表。
2. Info.plist 变更在下次构建后自动生效，用户需在系统设置 → 隐私 → 自动化中授权 AppleScript（首次触发时系统自动提示）。
3. 新热键 `⌥D` / `⌥S` 在 AppDelegate 初始化时注册，若冲突（用户系统已占用）则静默跳过并在日志中记录。

## Open Questions

- 有道词典 API 是否有配额限制需要用户配置 AppKey？→ 可在实现时评估，若需要则在 AI 配置页面新增有道 AppKey 字段，不影响核心流程。
