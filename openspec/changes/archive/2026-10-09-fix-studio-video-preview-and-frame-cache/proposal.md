## Why

在 AI 视频工坊的「分镜看板」中，点击已生成的视频预览时，弹窗出现整片灰屏遮挡整个窗口；同时点击「关键帧」重新生成图片时，长时间转圈圈且无法及时显示新图片，必须关闭并重新打开工坊窗口后新图片才展示。
根本原因在于：
1. `MediaKit.ensureInitialized()` 仅在主窗口分支中被调用，以独立子窗口运行的 AI 视频工坊子进程未能初始化原生 libmpv 视频解码与渲染纹理管线，导致内嵌视频无法解码渲染且弹窗缺少严格尺寸约束。
2. 关键帧生成后同名覆盖本地 `shot_{n}.png`，但 Flutter `ImageCache` 依据路径强缓存且未被淘汰驱逐（evict），导致界面即使重新触发 setState 仍命中旧内存图片或空视图。

## What Changes

- **初始化层**：将 `MediaKit.ensureInitialized()` 提升至 `main()` 函数的最顶层，确保在分支任何子窗口（如 `ai-video-studio`）之前全局初始化原生多媒体解码运行时。
- **缓存淘汰与即时刷新**：在 `ImageGenTask` 生成并落盘新关键帧图片时，主动调用 `FileImage(outputFile).evict()` 驱逐 Flutter 内存中的图片缓存；同时在分镜卡片缩略图组件中使用带时间戳/版本号的 Key 或显式图像提供者，确保生成完成后界面即时更新。
- **媒体预览弹窗体验优化**：为 `_MediaPreviewDialog` 提供合理的尺寸与比例限制，修复播放器初始化异常时的友好容错展示（展示关键帧大图并支持系统播放器打开），避免灰屏铺满整个窗口。

## Capabilities

### Modified Capabilities
- `private-media-player`: 增强全局原生多媒体引擎生命周期保障（在主窗口和各类多窗口子进程中均具备硬件解码与原生纹理渲染能力），确保多窗口工具（如 AI 视频工坊）下的媒体播放正常运作。

## Impact

- `lib/main.dart`: 启动入口提前初始化 `MediaKit`，覆盖主窗口与各独立子窗口。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: 图片落盘后执行 `FileImage.evict()` 清理内存缓存。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 优化分镜卡片关键帧图片响应式加载 Key 与 `_MediaPreviewDialog` 播放容错展示。
