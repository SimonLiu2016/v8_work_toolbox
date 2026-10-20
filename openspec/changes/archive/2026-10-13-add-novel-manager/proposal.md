## Why

当前工作台缺少结构化长文本与小说资源的管理中枢。用户在进行小说阅读、内容整理，尤其是短视频创作与视频脚本制作（如“AI短视频工坊”及其相关创作 SKILL）时，亟需可靠的小说资产库支持。现存采集手段缺乏断点续采与防反爬能力，外部文本（TXT/EPUB）导入缺乏规范的章节结构化与 AI 智能填充机制。引入“小说管理器”能够建立统一的小说资产规范，实现多站点幂等增量采集、智能格式转换、AI 改写续写，并深度赋能短视频脚本与多模态创作生态。

## What Changes

- **新增小说管理器 (Novel Manager) 独立模块**：
  - 规范化小说元数据管理（标题、作者、类型标签、背景设定、热度、阅读量、推荐指数、状态等）。
  - 小说章节管理：按章节检索/导出、整书检索/导出，支持统一格式（TXT / Markdown / EPUB / JSON）。
  - 章节内容编辑器：支持人工查看/编辑章节，支持 AI 单章改写、润色、视角切换与新章节生成/插入。
- **采集站点管理与双模幂等采集器**：
  - 站点源规则管理（列表页/目录页/正文提取规则）。
  - 双模采集引擎：轻量级规则 HTTP 抓取 + 反爬穿透抓取（集成 Firecrawl / 原生 WebView 会话复用，应对类似 Cloudflare Turnstile 挑战）。
  - 定时调度与手动触发：集成后台定时器，支持章节级事务提交与断点续采，保证已采章节幂等不重复。
- **多格式导入与 AI 智能清洗填充管道**：
  - 支持 `.txt` 与 `.epub` 格式导入。
  - 正则规则优先切分，遇混乱或缺失文本时自动调用 AI 智能断章、拟题，并提炼填充小说元数据（背景、作者、标签、简介）。
- **短视频工坊联动生态**：
  - 在“AI短视频工坊”创建剧集/分集界面新增“从小说库选择”弹窗，支持勾选整书或指定章节直接注入剧本/分镜生成流。
- **注册工具箱主导航与工具定义**：将小说管理器纳入桌面端侧边栏与工具注册表。

## Capabilities

### New Capabilities
- `novel-manager`: 提供小说与章节元数据存储、章节编辑、导入解析、AI 改写续写、导出格式化及站点采集管理。

### Modified Capabilities
- `ai-video-studio/novel-import`: 扩展短剧创作前置输入能力，在创意孵化与分集面板中增加直接从小说管理器的“小说库”检索并选择小说/章节的入口，复用已解析的章节与元数据。

## Impact

- **新增代码**：
  - `lib/tools/novel_manager/`（数据模型、SQLite/文件存储层、采集引擎、导入管道、AI 编排、UI 页面）。
  - `lib/tools/novel_manager/services/novel_scraper_service.dart`、`novel_import_service.dart`、`novel_repository.dart` 等。
- **修改代码**：
  - `lib/tools/registry.dart`、`lib/tools/tool_definition.dart`：注册小说管理器工具。
  - `lib/tools/ai_video_studio/ui/`（`series_page.dart`、`idea_incubator_panel.dart`）：接入小说章节选择器对话框。
  - `lib/services/app_paths.dart`：新增小说资产持久化存储目录 (`AppPaths.novelLibraryDir`)。
- **依赖项**：
  - 评估并引入 `epubx` 或 Dart 原生归档解析工具以支持 EPUB；字符集探测工具以支持 GBK/GB2312 TXT 文本。
