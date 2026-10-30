## Why

目前应用在短视频制作流程中存在两项关键阻碍：
1. **分镜看板视频预览灰屏卡死且无法退出**：在分镜看板点击视频预览时，播放器容器缺乏尺寸约束和解码缓冲监听，且未捕获错误与绑定键盘退出事件，导致界面变灰无响应且无法正常返回看板；
2. **缺乏系统级视频生成模型支持**：当前系统尚未集成云端商用视频模型（`AiConfigStore` 仅有 text/multimodal/tts/stt 四个槽位），短视频工坊无法直接配置并调度现代文生视频/图生视频 API（如 SenseAudio 的 Seedance-2.0 模型）。

通过在全局配置中引入视频模型槽位与 SenseAudio 异步视频生成链路，并重构分镜媒体播放组件，可彻底跑通端到端的视频生成与全屏丝滑预览体验。

## What Changes

- **系统级 AI 配置层扩展 (`ai-configuration`)**:
  - `AiProviderConfig` 新增 `videoModels` 字段，支持保存供应商支持的视频生成模型；
  - `AiConfigStore` 新增 `video` 槽位，并纳入默认槽位与候选列表持久化序列；
  - 在「AI能力配置」页面（`ai_config_page.dart`）中展示视频模型槽位，提供 SenseAudio 预设支持（BaseUrl: `https://api.senseaudio.cn`，默认模型 `doubao-seedance-2-0-260128`）。
- **短视频工坊视频生成适配层 (`ai-video-studio/shot-production`)**:
  - 新增 `SenseAudioVideoAdapter`，实现基于 SenseAudio 官方规范的异步图生视频/文生视频任务创建 (`/v1/video/create`)、进度状态轮询 (`/v1/video/status`) 与成片下载落盘；
  - `VideoGenAdapterFactory` 优先读取系统 `video` 槽位配置的视频引擎，支持首帧 base64/URL 提交，并保持对本地 Ken Burns 动效的兜底；
  - 未配置视频模型且无本地 FFmpeg 时，在点击生成视频时弹出友好配置引导，防止任务静默失败。
- **分镜媒体播放器健壮性与交互重构 (`ai-video-studio/shot-production`)**:
  - `_MediaPreviewDialog` 增加 `AspectRatio` 约束与缓冲指示，监听播放器错误流，发生解码异常时优雅回退显示关键帧大图；
  - 增强返回机制：支持按 `ESC` 键关闭、支持点击外部遮罩关闭、顶部常驻明显的「← 返回分镜看板」按钮；
  - 在视频加载和首帧渲染完成前展示分镜关键帧垫底，消除灰屏/黑屏感。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 在系统 AI 配置中扩展 `video` 视频生成模型槽位与供应商 `videoModels` 管理。
- `ai-video-studio/shot-production`: 分镜视频生成适配器接入系统视频模型（SenseAudio 等）并在看板弹窗中提供容错播放与安全返回交互。

## Impact

- **数据层**: `AiProviderConfig.toJson` 与 `fromJson` 升级，向后兼容现有 `models` JSON；
- **配置界面**: `ai_config_page.dart` 新增「视频模型」卡片与模型候选分配；
- **工坊引擎**: `lib/tools/ai_video_studio/services/video_gen_adapter.dart` 新增 SenseAudio 适配类并重构工厂选择逻辑；
- **工坊看板**: `lib/tools/ai_video_studio/ui/storyboard_board.dart` 重构 `_MediaPreviewDialog` 弹窗。
