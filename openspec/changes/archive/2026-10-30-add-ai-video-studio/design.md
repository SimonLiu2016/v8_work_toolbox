## Context

本项目已具备以下基础能力（见 proposal.md - Why）：
- `AiService.chat()` — 多提供商 AI 路由与故障转移（OpenAI/Anthropic/Gemini/DeepSeek 兼容接口）
- `TtsEngine` 抽象层 — Edge-TTS / OpenAI TTS / macOS 原生 TTS 三种实现，可扩展
- `PrivatePlayerController` + `YtdlpVideoParser` — 视频下载与本地播放基础
- `AiSubtitleService` — SRT/VTT 时间轴解析与对齐
- Mihomo 代理进程 — 所有出站网络请求自动代理，海外 AI API 无需额外配置
- `AppPaths` — 统一 AppSupportDir 路径管理

AI Video Studio 是在这些基础之上叠加的**工作流编排层**，不改变底层服务，只引入新的协调逻辑、数据模型和 UI 模块。

## Goals / Non-Goals

**Goals:**
- 以单一 Flutter 工具模块（`lib/tools/ai_video_studio/`）实现创意孵化 → 剧本 → 分镜生产 → 声音设计 → 成片交付的全链路
- 所有核心功能在零付费 API Key 的情况下可运行（使用本地/免费引擎）
- 连续剧跨集资产与记忆的完整生命周期管理
- 支持三种制作类型管线，切换不改变架构，只切换配置和策略

**Non-Goals:**
- 不实现视频编辑器（时间轴精剪、特效、滤镜 — 由剪映承接）
- 不实现角色面部替换（换脸/DeepFake）技术
- 不实现多用户协作或云端同步
- 不优化底层 AI 路由（复用现有 AiService，不改动其内部）
- 不支持横屏（16:9）格式输出（仅限 9:16 竖屏短视频）

## Decisions

### D1：模块目录结构 — 服务层与 UI 层分离

```
lib/tools/ai_video_studio/
├── services/
│   ├── studio_project_manager.dart   # 项目/系列/集数 CRUD，管理 AppSupportDir/video_studio/
│   ├── ai_constraint_engine.dart     # System Prompt 模板库 + JSON Schema 强制解析
│   ├── prompt_assembler.dart         # 角色DNA + 风格锁 + 运镜词 → 最终生图 Prompt
│   ├── image_gen_adapter.dart        # Engine Adapter：硅基流动/可灵/MiniMax/本地 stub
│   ├── video_gen_adapter.dart        # Engine Adapter：Kling I2V/MiniMax/本地 FFmpeg Ken Burns
│   ├── studio_tts_service.dart       # 包装 TtsEngine，支持多角色批量合成 + 时长记录
│   ├── bgm_matcher.dart              # 情绪标签 → BGM 推荐逻辑
│   ├── ffmpeg_composer.dart          # FFmpeg 封装：拼接/Ducking/字幕/转场/MP4 输出
│   └── jianying_exporter.dart        # 剪映草稿 JSON 序列化
└── ui/
    ├── studio_shell.dart             # 工作台主框架（左侧资产抽屉/中间看板/右侧预览）
    ├── project_list_page.dart        # 剧集库列表页
    ├── idea_incubator_panel.dart     # 创意孵化面板
    ├── storyboard_board.dart         # 分镜可视化看板
    ├── sound_design_panel.dart       # 声音设计与时序面板
    └── delivery_panel.dart           # 合成交付与发布套件页
```

**为何如此拆分**：各 adapter 和服务单文件职责单一，便于单独替换引擎实现（如把硅基流动换成 Stability AI）而不触碰 UI 层。

### D2：AI 约束引擎 — 强制 JSON Schema 输出而非自由文本

所有 AI 生成任务（剧本拆镜、Prompt 翻译、BGM 推荐、标题生成）均通过 `AiConstraintEngine` 执行，该引擎：
1. 根据任务类型从模板库中选取 System Prompt（包含精确字段约束、禁止词、输出 Schema 示例）
2. 在 `AiService.chat()` 调用时注入 System Prompt
3. 将 AI 返回的文本按预定义 JSON Schema 解析，失败则自动 retry（最多 3 次）
4. retry 耗尽后返回 `ConstraintParseError`，UI 层显示原始文本备用

**为何不用自由文本**：非专业用户无法手动纠正 AI 格式错误；结构化输出是看板渲染和后续自动化（SRT 对齐、Ducking 时序）的前提。

**为何不用 OpenAI function calling / response_format**：现有 `AiService` 支持多家提供商，DeepSeek/智谱 GLM 等免费模型不全支持 structured output API，Schema 约束在 System Prompt 中统一实现更具通用性。

### D3：Engine Adapter 模式 — 免费与付费引擎平滑切换

`ImageGenAdapter` 和 `VideoGenAdapter` 各自为抽象接口，对上层提供统一的 `Future<File> generate(ImageGenRequest req)` / `Future<File> generateVideo(VideoGenRequest req)` 接口。内置实现：

| 能力 | 免费实现 | 付费实现 |
|------|----------|----------|
| 文本生成 | DeepSeek-chat / 智谱 GLM-Flash（复用 AiService） | 通义千问 / GPT-4o（已支持） |
| 图像生成 | 硅基流动 Flux-schnell（每日免费额度） | 可灵图像 / MiniMax 图像 |
| 视频生成 | 本地 FFmpeg Ken Burns 动效 | 可灵 Kling I2V / MiniMax 视频 |
| TTS | Edge-TTS（复用现有 TtsEngine） | MiniMax 语音 / CosyVoice |

用户在工坊设置中为每种能力类型配置 API Key 后，对应 adapter 在下次调用时自动切换至付费实现，无需重启应用。

### D4：本地数据存储 — 纯文件系统 + JSON，不引入新数据库

剧集主库的元数据（`series_profile.json`）、角色资产卡（`characters/<id>/config.json`）、分镜脚本（`storyboard.json`）均以 JSON 文件存储于 `AppSupportDir/video_studio/` 下的固定目录层级中。

**为何不用 SQLite**：
- 素材文件（图片、音频、视频）天然以文件系统管理
- 剧集元数据体量小（百KB级），JSON 读写性能足够
- 用户可通过 Finder 直接访问/备份/迁移原始素材，无需导出工具
- 避免引入额外的数据库依赖和迁移复杂度

**数据一致性保障**：写入操作先写临时文件再原子 rename，防止断电或崩溃导致 JSON 损坏。

### D5：FFmpeg 依赖策略 — 使用本机已安装的 FFmpeg

项目已通过 Mihomo 代理注入机制验证了调用本机二进制的可行性。FFmpeg 合成调用同样检测本机 `ffmpeg` 路径（`/usr/local/bin/ffmpeg` / `/opt/homebrew/bin/ffmpeg`），不内置打包。若用户未安装 FFmpeg，系统在首次触发合成时显示安装引导（Homebrew 命令一键复制）。

**为何不内置打包**：FFmpeg 静态编译包约 80-100 MB，显著增加应用体积；绝大多数开发者/创作者环境已有 FFmpeg。

### D6：剪映草稿协议 — 逆向现有草稿格式

剪映 Mac 版草稿存储在 `~/Movies/JianyingPro/User Data/Projects/com.lveditor.draft/<uuid>/draft_content.json`。`JianyingExporter` 基于逆向分析的 JSON 结构写入轨道数据，包含：视频片段时间码、音频片段时间码、字幕时间码与文本。草稿格式可能随剪映版本升级而变化，因此 `JianyingExporter` 内部维护版本号字段，便于后续修复。

## Risks / Trade-offs

- **[Risk] 硅基流动免费额度耗尽** → 系统在调用前检查剩余配额（如 API 支持），耗尽时提示用户切换付费引擎或降级至本地占位图（纯色块 + 分镜文字）
- **[Risk] 图生视频 API 响应时间长（30-120 秒）** → 所有 I2V 任务异步入队，用户可在队列面板查看进度，不阻塞 UI
- **[Risk] 剪映草稿格式随版本升级失效** → `JianyingExporter` 维护兼容版本号，提供降级为 SRT + 素材文件夹打包的备用导出方式
- **[Risk] 连续剧前情上下文 Token 过多（集数多时）** → 剧情记忆库仅保留各集 200 字以内的精炼摘要，不注入完整剧本，控制上下文 Token 数在 2000 以内
- **[Risk] FFmpeg 未安装导致合成失败** → 首次启动工坊时预检测 FFmpeg 可用性，缺失时在工坊首页顶部展示安装引导横幅

## Open Questions

- 硅基流动 Flux-schnell 的免费额度策略是否会变化？若变化是否有其他稳定的免费图像生成 API 替代？（不影响当前架构，adapter 可随时替换实现）
- 剪映草稿中是否支持字幕样式（字体、颜色、描边）的自动写入？需在实现阶段验证草稿格式。
