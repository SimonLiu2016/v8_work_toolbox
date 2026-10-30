## Why

当前软件已积累了 AI 推理、TTS 语音合成、视频下载、代理网络等核心基础能力，但缺乏一套将这些能力串联起来、面向非专业创作者的 AI 短视频/连续短剧全流程制作工具。用户希望借助强大的 AI 能力，从最初的一个想法出发，独立完成连续短剧的创意构思、剧本编写、分镜生产、语音合成、视频生成与最终成片交付，而无需具备专业影视知识。

## What Changes

- **新增「AI 短视频工坊 (AI Video Studio)」工具模块**，作为独立工具页面集成到应用工具栏
- 新增**三层资产管理体系**：全局公共资料库 → 连续剧 IP 主库 → 单集制作区，支持跨剧引用与剧内继承
- 新增**创意孵化面板**：用户输入模糊想法，AI 提炼爆款剧情结构、主线走向与分集节奏建议
- 新增**结构化剧本工坊**：AI 在高度约束的模板框架内生成剧本分镜，精确控制景别、情绪、时长与台词字数
- 新增**角色资产卡系统**：自然语言 → 标准化生图 Prompt 翻译层，支持角色多形态版本化管理（默认/战损/觉醒等）
- 新增**分镜可视化看板**：景别/运镜方案由 AI 基于情绪基调自动推荐，用户"选一个"即可，无需专业知识
- 新增**声音设计与时序编排**：按角色卡绑定 TTS 音色批量生成对白，自动 SRT 对齐，BGM 情绪智能匹配与 Ducking 压混
- 新增**双轨合成交付**：FFmpeg 一键直接压制成品 MP4，以及一键导出剪映(CapCut)草稿工程，两者同时支持
- 新增**发布运营套件**：自动生成封面帧、候选标题文案、话题标签与下集钩子剧情简介
- 新增**制作类型管线预设**：支持真人剧情短剧、二次元/动态漫、图文解说/知识故事三种模式，新建项目时可选且影响整个制作界面与流程
- 新增**阶梯式 AI 引擎接口层（Engine Adapter）**：前期以免费方案（DeepSeek/智谱 GLM-Flash/Edge-TTS/硅基流动 Flux）起步，后续无缝切换国内商业 API（可灵/MiniMax/CosyVoice 等）
- 新增**跨集记忆传递机制**：新建后续剧集时自动注入前情摘要、人物状态与上集结尾钩子，确保剧情连贯性

## Capabilities

### New Capabilities

- `ai-video-studio`: AI 短视频工坊核心模块，含创意孵化、系列/剧集项目管理、分镜看板主界面与合成交付
- `ai-video-studio/series-asset-library`: 三层资产体系（全局公共库 / 连续剧 IP 主库 / 单集制作区），管理角色 DNA、场景、风格预设与跨集记忆
- `ai-video-studio/script-workshop`: 结构化剧本与分镜生成工坊，含 AI 约束引擎、Prompt 翻译层与跨集剧情上下文注入
- `ai-video-studio/shot-production`: 分镜可视化看板，含图片生成任务队列、运镜方案 AI 推荐与图生视频接口
- `ai-video-studio/sound-design`: 声音设计与时序编排模块，含多角色 TTS 批量合成、SRT 自动对齐、BGM 情绪匹配与 Ducking 压混
- `ai-video-studio/assembly-delivery`: 合成交付模块，含 FFmpeg 直出 MP4 管线与剪映 Draft JSON 导出器，以及发布运营套件生成

### Modified Capabilities

- `video-downloader`: 新增对 AI 生成视频素材的本地存储管理支持（下载路径统一纳入 video-studio 资产目录）

## Impact

- **新增工具模块**：`lib/tools/ai_video_studio/`（服务层 + UI 层），注册至 `lib/tools/registry.dart`
- **新增存储路径**：`AppSupportDir/video_studio/`（含 global_library / series_library 子目录层级），纳入 `lib/services/app_paths.dart` 统一管理
- **AI 服务层**：复用现有 `lib/services/ai_service.dart` 与 `lib/services/ai_config_store.dart`，新增多个专项 System Prompt 模板与结构化输出解析器
- **TTS 服务层**：复用现有 `lib/tools/reader/services/tts_engine.dart`，新增多角色音色映射与批量 TTS 任务调度
- **音视频处理**：新增 FFmpeg 封装服务（调用本机 FFmpeg），处理视频拼接、音频 Ducking、字幕压制与最终 MP4 输出
- **外部 API 依赖**：新增图像生成接口（硅基流动 Flux-schnell / 国内商业 API 适配器）、图生视频接口（可灵/MiniMax/Runway 适配器）
- **代理网络**：生成任务通过现有 Mihomo 代理网络透明路由，无需额外配置
