## Why

程序员在等编译、等 CI、开会前的间隙想练"听懂海外研发会议英语"，但现有英语学习工具（可可、ELLO、BBC、CoderSlingo）都不匹配：通用英语内容稀释定位，CoderSlingo 虽精准覆盖 IT 会议场景却**全站零音频**（实测 14212 个页面无任何 mp3/wav/audio 元素），通用听力 App 缺少切片、逐句文稿与场景标注。本 change 在本工具箱内新增一个"IT 会议听力"工具：素材文本取自 CoderSlingo 的 CC-BY 听力内容，音频由应用自带的 AI TTS 槽位（`stepaudio-2.5-tts`）本地合成，播放走常驻悬浮窗 + 全局热键，满足"耳边一直播、眼睛始终在 IDE"的工作间隙场景。

## What Changes

- **新增 IT 会议听力工具**（`ToolRegistry` 注册一项，独立悬浮窗形态）：素材库 + 后台连续播放 + 全局热键控制 + 按需文稿/摘要
- **新增 CoderSlingo 内容抓取器**：抓取其 `/exercises/listening/` 下的 18 类听力场景，解析出带说话人标签的对话轮次
- **新增 TTS 素材烘焙管线**：抓取文本 → 破折号清洗 → 角色→音色映射 → 逐轮合成 → ffmpeg 拼接 → 落盘 mp3 + 对齐文稿 manifest
- **新增常驻迷你播放器窗口**：音乐播放器形态的悬浮条，全局热键播放/暂停/上下曲/变速，不抢焦点
- **新增素材浏览与精听视图**：按场景（站会/故障复盘/Sprint 规划/架构评审/圆桌…）分类，播放中按需展开逐句文稿与一句话摘要
- **新增术语收藏**：播放中选中一句话或一个术语可一键存入本地术语本（复用既有 `VocabEntries` 表，不新增表）

**BREAKING** 无。

### 不做的事（明确的非目标）

- 不做通用英语内容（不掺雅思/四六级/日常对话）
- 不做打卡、学习时长统计、积分、排行榜
- 不做浏览器插件形态（首版仅桌面端）
- 不做影子跟读打分
- 不修改既有 `EdgeTtsEngine`（其 400 故障属另一议题）

## Capabilities

### New Capabilities

- `it-meeting-listening-tool`: IT 会议听力工具的完整行为契约——素材库的来源与结构、场景分类、片段切分规则、音频合成与拼接、TTS 文本预处理、播放控制（后台/连续/变速/断点）、精听模式的文稿与摘要呈现、术语收藏、悬浮窗与全局热键交互
- `coderslingo-content-source`: CoderSlingo 作为内容来源的抓取与解析契约——栏目发现、页面抓取、说话人轮次切分、许可与出处标注、失败降级

### Modified Capabilities

- `app-shell`: 工具箱需支持新增一个"常驻独立悬浮窗 + 菜单栏入口"形态的工具（既有工具只有内嵌页或整页独立窗两种形态，本工具是第三种：极小常驻窗 + 后台播放）
- `vocab-book-live-update`: 术语本需支持从 IT 听力工具写入带"来源片段 + 上下文句子 + 音频时间戳"的术语条目，并在术语本页显示其出处

## Impact

**新增目录**

- `lib/tools/it_meeting_listening/` — 模型、服务、UI
  - `models/` 场景分类、片段模型、说话人模型
  - `services/` 抓取器、解析器、文本清洗、烘焙管线、播放器控制器、素材库
  - `ui/` 素材浏览页、迷你悬浮窗、精听面板
- `openspec/specs/it-meeting-listening-tool/spec.md`
- `openspec/specs/coderslingo-content-source/spec.md`

**改动文件**

- `lib/tools/registry.dart` — 注册新工具定义
- `lib/main.dart` — 子窗口分支（迷你悬浮窗走独立进程）、`WindowKind` 新增枚举
- `macos/Runner/AppDelegate.swift` — 菜单栏项、播放相关全局热键（Carbon `RegisterEventHotKey`）
- `lib/services/app_paths.dart` — 素材与缓存目录登记
- `lib/services/ai_config_store.dart` — 无需改动（复用既有 `tts` 槽位）
- `lib/tools/notebook/note_database.dart` — 术语表新增"来源"字段（迁移 v4 → v5）

**依赖**

- 无新增 pub 包。复用既有 `audioplayers`、`desktop_multi_window`、`window_manager`、`http`、`path`、`drift`
- 外部运行时依赖：ffmpeg（拼接，仓库既有 `ffmpeg_composer.dart` 已有路径探测逻辑）、CoderSlingo 站点可达、AI 配置的 `tts` 槽位可用

**数据与许可**

- CoderSlingo 文本：CC-BY 4.0（其 `/resources/open-dataset/` 明示），个人自用、保留出处标注、**不随应用分发**
- 合成音频：本地生成，存于用户本地应用数据目录
