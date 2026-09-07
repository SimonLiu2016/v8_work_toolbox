## Why

用户需要一个支持隐私防护的多功能影音播放与下载工具：既能播放本地音视频文件，又能解析和播放在线流媒体（包括 B站、YouTube、Pornhub、pornlulu.com、MissAV 等主流及特定站点），支持单视频与批量下载，并在播放过程中能够借助全局集成的 AI 能力（STT 语音识别）实时将音频转换为带时间戳的字幕进行同屏渲染与本地保存。由于该功能包含敏感和个人隐私流媒体，必须在最左侧独立开辟“隐私空间”栏目，并通过 6 位数字 PIN 码对子菜单和主界面实施严格隔离锁定。

## What Changes

- **新增“隐私空间”独立侧边导航与 PIN 密码锁**：
  - ActivityBar 最左侧新增“隐私空间”独立入口（Icons.shield_outlined / Icons.lock_rounded）。
  - 首次使用支持设置 6 位数字 PIN 码，后续访问必须校验 PIN 码才能解锁子工具菜单与主界面。
  - 隐私工具不出现在“全部工具”列表与全局搜索中，防止意外暴露。
  - 支持快捷锁定与闲置自动锁定。
- **新增“私密影音播放器”工具**：
  - 采用高性能多媒体引擎 media_kit + media_kit_video，全格式支持本地及在线音视频播放（MP4、MKV、MOV、FLV、WebM、TS、MP3、WAV、M4A 等）。
  - 提供完备播放控制（播放/暂停、快进/快退、进度滑动、音量、0.5x~3.0x 多档倍速、全屏、等比缩放切换）。
  - 提供播放历史记录（带上次播放时间戳与断点续播）与我的收藏夹。
- **集成在线视频解析与批量下载引擎**：
  - 充分利用本地 yt-dlp 与 ffmpeg 能力，支持 B站、YouTube、Pornhub、pornlulu.com、MissAV 及通用直链解析。
  - 智能提取画质规格与音视频流，支持在线即时流播放。
  - 支持单视频下载与多链接批量排队下载，显示实时进度、下载速度与剩余时间。
  - 默认保存至本地隐藏私密目录（~/Library/Application Support/V8WorkToolbox/PrivateMedia/），并提供“打开本地私密目录”快捷按钮直达 Finder。
- **集成 AI 语音识别生成字幕功能**：
  - 基于全局 AiConfigStore 中的 'stt' 语音识别槽位（如 OpenAI Whisper / Groq / SiliconFlow 等）。
  - 支持“按当前播放进度区间（如前后 10 分钟）按需分段生成”与“全量后台分片转录生成完整字幕”。
  - 播放器内置实时字幕渲染器，支持字幕开关 [CC]、时间轴同步高亮与字幕文件（.srt/.vtt）导出保存。

## Capabilities

### New Capabilities
- `privacy-space`: 隐私空间基础安全防护框架，包含 6 位 PIN 码设置/验证、内存解锁会话管理、自动锁屏、子工具导航与主视图隔离。
- `private-media-player`: 基于 media_kit 的私密影音播放器，具备本地/在线多格式音视频播放、控制条交互、播放历史与收藏管理。
- `video-downloader`: 跨平台在线视频解析与批量下载调度器，深度适配 B站、YouTube、Pornhub、pornlulu.com、MissAV，支持下载进度监控与私密存储。
- `ai-subtitles`: 集成系统 AI STT 槽位的语音转字幕引擎，支持按需区间生成与全量后台生成，提供播放器字幕图层渲染、开关与导出保存。

### Modified Capabilities

## Impact

- **系统依赖**：添加 media_kit、media_kit_video、media_kit_libs_macos_video 依赖包；调用本地已有的 yt-dlp 与 ffmpeg 命令执行工具。
- **界面架构**：扩展 ActivityBar、ToolCategory、AppShell，支持独立的隐私空间视图与锁屏拦截状态。
- **AI 槽位复用**：复用并激活全局 AiConfigStore.instance.slotBindings['stt'] 语音识别能力，并接入 AiLogger 统一审计与调试。
- **本地存储**：在 ~/Library/Application Support/V8WorkToolbox/PrivateMedia/ 建立隔离存储目录，管理私密视频、音频切片、历史记录、收藏夹与字幕文件。
