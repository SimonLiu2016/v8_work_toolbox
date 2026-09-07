## Context

当前 V8WorkToolbox 基于 Flutter 开发，拥有三栏式工作区（ActivityBar、ToolPanel、主工作区）以及完善的 AI 供应商与槽位管理体系（`AiConfigStore`，内建 `stt` 槽位）。
在 `/Users/simon/ClaudeWorkspace/V8VideoDownloader` 中已沉淀了针对 B站、YouTube、Pornhub、pornlulu.com、MissAV 等站点的 `yt-dlp` 规则与参数实践。本机环境已具备全局 `yt-dlp`（`/usr/local/Caskroom/miniconda/base/bin/yt-dlp`）与 `ffmpeg`（`/usr/local/bin/ffmpeg`）。
本设计将上述播放、下载与隐私安全需求以及基于全局 AI 语音识别的字幕生成能力系统化整合进工具箱中。

## Goals / Non-Goals

**Goals:**
- 提供带 6 位数字 PIN 码安全锁的独立“隐私空间”侧栏入口，确保隐私工具与播放记录完全隔离于主工作区。
- 基于 `media_kit` 实现跨格式本地及在线流媒体音视频播放器，具备全套播放控制、播放历史与收藏夹。
- 适配 B站、YouTube、Pornhub、pornlulu.com、MissAV 及通用链接的在线解析与批量下载。
- 基于全局 AI STT 槽位与 `ffmpeg`，实现“按当前播放进度区间（前后 10 分钟）按需分段生成”与“全量后台完整生成”双模式字幕，支持播放器同屏渲染与 `.srt` 导出。
- 将私密视频、音频切片与字幕存储于本地隐藏私密目录，并提供一键在 macOS Finder 中打开的快捷操作。

**Non-Goals:**
- 复杂的视频剪辑、滤镜或转码编辑（仅使用 ffmpeg 完成轻量音频抽取与分片）。
- 绕过受 DRM（如 Widevine L1/FairPlay）强加密保护的版权流媒体服务。

## Decisions

### 1. 播放引擎选型：采用 `media_kit` + `media_kit_video`
- **理由**：Flutter 官方 `video_player` 依赖 macOS 原生 `AVPlayer`，对 MKV、FLV、VP9/WebM、TS 等容器和编码格式兼容性差；而 `media_kit` 底层基于 `mpv`，经实测完美支持几乎所有主流多媒体格式、硬件加速、外挂字幕渲染与实时流缓冲。
- **备选方案**：纯原生 `AVPlayerView` 平台视图（格式支持极其有限，需大量转码，不可行）。

### 2. 安全锁方案：6 位纯数字 PIN 码 + macOS Keychain 持久化
- **理由**：6 位 PIN 码在桌面端输入迅速便捷（支持数字小键盘与软键盘），体验平滑；哈希（SHA-256 加盐）保存于 `KeychainService`，内存中仅保留会话级解锁布尔值，支持手动锁定与闲置自动锁定。
- **隔离机制**：私密工具在 `ToolRegistry` 中独立归属于 `ToolCategory.privacy`，在未解锁时不会被渲染在普通工具面板或全局搜索建议中。

### 3. 在线解析与下载策略：复用并优化 `yt-dlp` + `ffmpeg` 调度
- **理由**：视频平台的反爬与签名算法（如 YouTube JS Challenge、MissAV/PornLulu 反爬指纹）频繁变动，自研提取器维护成本极高。复用成熟的 `yt-dlp` 命令行接口：
  - YouTube：`--remote-components ejs:npm`
  - MissAV / PornLulu：`--force-generic-extractor --extractor-args generic:impersonate`
  - 解析时使用 `--dump-json`，下载时使用 `-f "bestvideo+bestaudio/best" --merge-output-format mp4`。
- **并发控制**：在 Dart 层实现 `DownloadQueueManager`，限制最大并发数为 2~3，通过管道读取标准输出实时解析下载百分比、速率与 ETA。

### 4. AI 字幕生成架构：双模式转录与标准 SRT 同步
- **理由**：整部超长视频（如 1~2 小时）全量发送转录耗时长、费用高；而用户往往只关注当前正在观看的部分。
  - **按需分段模式**：截取当前播放位置前后共约 10 分钟音频（例如 `max(0, current - 2min)` 至 `current + 8min`），抽取 16kHz 单声道轻量音频（约 1~2MB），在 3~8 秒内即可返回带时间戳的字幕并渲染。
  - **全量后台模式**：利用 `ffmpeg` 按 10 分钟自动分段，后台异步串行调用 AI STT 槽位，自动累加各分段起始时间偏移量，最终合并为完整的字幕列表。
- **AI 槽位契约**：直接调用 `AiConfigStore.instance.slotBindings['stt']` 所绑定的供应商，发起标准 OpenAI 规范请求：`POST /v1/audio/transcriptions`（`response_format: verbose_json`），解析 `segments` 中的 `start`, `end`, `text`。
- **同屏渲染**：播放器控制器在 `position` 变化时比对字幕区间，半透明悬浮在视频底端；支持 `[CC]` 开关及导出为 `.srt` 文件。

### 5. 存储与目录访问：私密目录 + Finder 快捷唤起
- **存储路径**：`~/Library/Application Support/V8WorkToolbox/PrivateMedia/`，子目录划分为 `downloads/`、`subtitles/`、`temp_audio/`、`cache/`。
- **Finder 直达**：提供“打开私密文件夹”按钮，通过 `Process.run('open', [dirPath])` 直接在 macOS Finder 中打开该文件夹。

## Risks / Trade-offs

- **[Risk] 用户系统未安装或卸载了 `yt-dlp` / `ffmpeg`**  
  → **Mitigation**: 启动或解析前执行快速路径检测（`which yt-dlp` / `which ffmpeg`），若缺失则在界面展示一键 Homebrew 安装提示命令，不发生硬崩溃。
- **[Risk] 音频切片过大超过商业 AI 25MB 上传限制**  
  → **Mitigation**: 提取音频时统一转为 16kHz 单声道 64kbps MP3，1 小时音频仅约 28MB；分段切片设定在 10 分钟（< 5MB），彻底消除超出 Payload 上限的风险。
- **[Risk] 在线平台需要登录 Cookie 才能获取高清画质**  
  → **Mitigation**: 在工具设置抽屉中提供 Cookie 文本输入与 `--cookies-from-browser` 选择项，调用 `yt-dlp` 时动态注入。
