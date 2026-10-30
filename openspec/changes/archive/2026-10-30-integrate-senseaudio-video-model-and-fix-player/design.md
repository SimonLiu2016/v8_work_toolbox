## Context

见 `proposal.md`。当前应用缺乏系统级视频生成模型支持，`AiConfigStore` 仅有 4 个槽位，`VideoGenAdapterFactory` 仅支持可灵与本地 FFmpeg。同时，在分镜看板点击缩略图调用 `_MediaPreviewDialog` 时，`media_kit` 缺乏约束和异常兜底，且缺乏退出保底快捷键，容易造成界面灰屏卡死。

## Goals / Non-Goals

**Goals:**
- 在系统 `AiConfigStore` 与 `ai_config_page.dart` 中建立标准 `video` 视频模型槽位与 `videoModels` 配置能力；
- 预设并支持 SenseAudio 视频开放平台（提供 Seedance-2.0 模型支持，BaseUrl: `https://api.senseaudio.cn`）；
- 在短视频工坊中实现 `SenseAudioVideoAdapter`，实现首帧图片上传、异步任务创建、百分比轮询与成片下载落盘；
- 重构分镜媒体预览弹窗 `_MediaPreviewDialog`，修复灰屏卡死问题，提供 AspectRatio 约束、错误降级展示、ESC 快捷返回及大返回按钮。

**Non-Goals:**
- 不自建图床服务器（利用 SenseAudio 官方原生支持的 Base64 Data URL 提交首帧图像）；
- 不在此变更中修改音频/音乐生成相关逻辑。

## Decisions

### 1. 系统配置层：扩展 `video` 槽位与 `videoModels`
- **选择**: 在 `AiProviderConfig` 中新增 `List<String> videoModels`，并在 `AiConfigStore._slotBindings` 中常驻 `'video'` 键。
- **替代方案**: 仅在短视频工坊内部增加私有 Key 配置。
  - *理由*: 用户明确要求“增加系统视频模型的配置，然后，在'AI 短视频工坊'中引用”，与 TTS/LLM/STT 保持一致的全局管理体验，便于多个工具复用。

### 2. SenseAudio 适配器：Base64 编码的首帧图生视频
- **选择**: 将本地已生成的关键帧（PNG）通过 `base64Encode` 封装为 `data:image/png;base64,...`，作为 `first_frame` 传给 `POST https://api.senseaudio.cn/v1/video/create`。
- **替代方案**: 搭建第三方对象存储上传公网 URL。
  - *理由*: 本地应用开箱即用，SenseAudio 官方明确支持 Data URL，免去用户额外配置 S3/OSS 图床的极高门槛。

### 3. 异步轮询与取消集成
- **选择**: 在 `SenseAudioVideoAdapter` 中实现 `CancellableVideoGenAdapter`。创建任务后获取 `task_id`，每 5 秒发起一次 `GET /v1/video/status?id=<task_id>`，并将 `progress` 百分比通过 `onProgress` 回调给工坊任务队列 UI；任务完成后直接流式下载 mp4 到 `episodeClipsDir/shot_N.mp4`。

### 4. 播放器容错与安全返回重构
- **选择**:
  - 外层使用 `Focus` + `onKeyEvent` 监听按键，用户按下 `LogicalKeyboardKey.escape` 即可瞬间关闭对话框；
  - 顶部显式增加 `IconButton` 和「← 返回看板」文字按钮；
  - 视口内使用 `AspectRatio`（默认 9:16 或 16:9）包裹 `Video`，并监听 `player.stream.error` 和 `player.stream.buffering`；
  - 若视频加载报错，自动在原位置展示关键帧图片并显示提示，不发生 UI 崩溃。

## Risks / Trade-offs

- **[大图 Base64 请求体较大]** → 关键帧 1080x1920 PNG 约为 1~2MB，Base64 后约 2~3MB，在宽带下传输需 1-2 秒，`onProgress(0.05)` 提示正在上传首帧；
- **[云端生成耗时较长 (30s~120s)]** → 设置 10 分钟轮询超时，全程支持在任务队列中一键取消，避免卡住后台并发。
