## Why

用户在参加海外会议、观看外语技术演讲、或跨语言协作时，需要**实时**看到双语字幕才能跟上内容——但现有工具都不匹配：系统级字幕工具（如 macOS 自带字幕）仅支持特定 App 且无翻译；离线字幕工具（`ai-subtitles` capability）只能处理已下载的视频文件，无法捕获实时系统音频；会议软件内置字幕受限于该软件本身且多数无翻译。本工具箱需要一个"旁路"工具：无论音频来自会议软件、浏览器直播还是本地播放器，都能实时捕获系统输出、流式识别、可选翻译，并以常驻悬浮窗展示双语字幕。

## What Changes

- **新增实时会议翻译工具**（`ToolRegistry` 注册一项，常驻悬浮窗形态）：捕获系统音频输出（Soundflower 内录）→ 本地 VAD 分块 → StepFun ASR SSE 流式识别 → 可选逐句翻译 → 双语悬浮字幕
- **新增音频内录捕获服务**：基于 FFmpeg + Soundflower 的 PCM 16kHz 单声道流式捕获，复用仓库现有 FFmpeg 路径探测
- **新增本地 VAD + 音频分块器**：能量阈值静音检测，累积 2 秒语音块（0.5s 重叠），跳过无声段以降低无效请求与成本
- **新增 StepFun ASR SSE 客户端**：HTTP + SSE 流式识别，解析 `transcript.text.delta` / `transcript.text.done` 事件，支持热词、ITN、时间戳
- **新增 AI 供应商类型 `stepfun`**：`ai_config_store` 增加协议分支，走 `https://api.stepfun.com/v1/audio/asr/sse` 端点，供 `stt` 槽位使用
- **新增逐句流式翻译**：ASR 完成一句后走 `text` 槽位翻译，支持中英日韩四语互译，可开关
- **新增常驻双语字幕悬浮窗**：透明无边框置顶、可拖动、字号可调、多说话人角色配色、手动切换说话人（全局热键）
- **新增字幕记录与导出**：手动"开始/停止记录"，导出带说话人标签与双语内容的标准 SRT / VTT 文件（含时间轴）

**BREAKING** 无。

### 不做的事（明确的非目标）

- 不做自动说话人分离（speaker diarization）——v1 仅手动热键切换说话人；API diarization 成本高且 StepFun 不支持
- 不做本地 Whisper 离线 ASR——实测/评估延迟不可接受，仅走云端 StepFun
- 不做麦克风（说话人自身）输入捕获——仅捕获系统音频输出（内录）
- 不做 WebSocket 流式 ASR——StepFun 仅提供 SSE，不为更低延迟引入第二家 ASR 供应商
- 不做历史字幕的自动录音（进程启动即录）——记录由用户显式开始/停止，避免不可控的累积与成本
- 不做浏览器插件形态（首版仅桌面端）

## Capabilities

### New Capabilities

- `live-audio-capture`: 系统音频内录捕获契约——Soundflower 设备选择与枚举、FFmpeg PCM 流式捕获、本地 VAD 静音检测、固定时长分块与重叠、捕获生命周期（启动/暂停/停止）与设备不可用时的降级
- `live-asr-streaming`: StepFun ASR SSE 流式识别契约——供应商协议分支、SSE 事件解析（delta/done/error）、热词与语言配置、识别结果与时间戳、断线重连与错误归因
- `live-translation-streaming`: 逐句流式翻译契约——ASR 完成句触发翻译、中英日韩目标语言选择、翻译开关、双语字幕单元的数据结构
- `live-caption-overlay`: 常驻双语字幕悬浮窗契约——透明置顶可拖动、字号调节、说话人角色配色与手动切换（全局热键）、字幕滚动与清空、开关菜单入口
- `subtitle-export-with-speakers`: 字幕记录与导出契约——显式开始/停止记录、带说话人标签的双语 SRT/VTT 导出、时间轴对齐、文件命名与保存位置

### Modified Capabilities

- `app-shell`: 工具箱需支持新增一个"常驻独立悬浮字幕窗 + 菜单栏入口"形态的工具（与既有 it-listening-mini 的迷你播放窗同属"第三种形态"但承载不同职责）
- `ai-routing`: `stt` 槽位需支持 `stepfun` 供应商类型的协议分发（SSE 端点），与既有 OpenAI Whisper multipart、MiMo chat completions 并列

## Impact

**新增目录**

- `lib/tools/live_translator/`
  - `models/` 字幕单元、说话人状态、捕获配置模型
  - `services/` 音频捕获（FFmpeg）、VAD 分块器、StepFun ASR SSE 客户端、翻译服务、字幕记录器、导出器
  - `ui/` 双语悬浮字幕窗、说话人切换控制
- `openspec/specs/live-audio-capture/spec.md`
- `openspec/specs/live-asr-streaming/spec.md`
- `openspec/specs/live-translation-streaming/spec.md`
- `openspec/specs/live-caption-overlay/spec.md`
- `openspec/specs/subtitle-export-with-speakers/spec.md`

**改动文件**

- `lib/tools/registry.dart` — 注册新工具定义
- `lib/tools/tool_definition.dart` — 新增工具标识常量
- `lib/main.dart` — 新增 `WindowKind.liveCaption` 枚举与子窗口启动分支；`WindowServices.required` 登记所需服务
- `lib/services/ai_config_store.dart` — 新增 `stepfun` 供应商协议类型
- `macos/Runner/AppDelegate.swift` — 菜单栏项、说话人切换全局热键（Carbon `RegisterEventHotKey`，⌥1/⌥2/⌥3）、字幕开关热键
- `lib/services/app_paths.dart` — 字幕导出目录登记

**复用（不改动）**

- `lib/tools/private_player/services/ai_subtitle_service.dart` — 参考其 FFmpeg 路径探测与音频切片逻辑
- `lib/tools/lookup_panel/ui/lookup_window.dart` — 透明无边框置顶浮窗现成原型
- `lib/services/ai_config_store.dart` 的 `text` 槽位 — 翻译复用既有绑定

**依赖**

- 无新增 pub 包。复用既有 `http`（扩展 SSE 解析）、`desktop_multi_window`、`window_manager`、`path`
- 外部运行时依赖：FFmpeg（仓库已有路径探测逻辑）、Soundflower 虚拟声卡（用户本机已安装）

**数据与存储**

- 字幕记录：仅当用户显式"开始记录"后在内存累积，导出时写入 SRT/VTT 文件到用户选定位置；不做持久化数据库、不做自动落盘
- 音频：全程内存流处理，不落盘
