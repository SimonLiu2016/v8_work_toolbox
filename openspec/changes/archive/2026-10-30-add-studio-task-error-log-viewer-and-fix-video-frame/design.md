## Context

当前短视频工坊中：
1. 分镜卡片（`_ShotCard`）和队列抽屉（`_QueueDrawer`）对失败任务的错误信息仅展示 `maxLines: 1` 或 `2`，超出直接截断，且不可划选、不可复制。
2. 图像生成适配器已接入全局日志系统 `AiLogger`，但视频适配器（`VideoGenAdapter`）全系缺失 `AiLogger`，导致生视频调用时的状态与错误完全没有持久化记录。
3. `AgnesVideoAdapter` 采用 `data:image/png;base64,...` 作为 `first_frame`，遇到部分上游网关时易被判为非法或被限流饱和阻断。

## Goals / Non-Goals

**Goals:**
- 提供通用任务报错详情弹窗 `_TaskErrorDetailDialog`，支持完整报错展开展示、划选与一键复制到剪贴板。
- 在 `_ShotCard` 的失败提示和 `_QueueDrawer` 的列表项上添加快速交互，点击即可调出弹窗。
- 在 `AgnesVideoAdapter` 中完整接入 `AiLogger` 记录日志，并改善 `first_frame` 兼容性参数透传。

**Non-Goals:**
- 不修改既有的任务状态流或取消逻辑架构。

## Decisions

### 1. 通用报错详情对话框组件 (`_TaskErrorDetailDialog`)
- 在 `storyboard_board.dart` 中实现弹窗，传入 `StudioTask` 或错误信息、任务标题。
- 采用 `SelectableText` 展示 `error`，提供 `Icons.copy` 按钮，通过 `Clipboard.setData(ClipboardData(text: ...))` 写入系统剪贴板，并提示用户已复制成功。

### 2. 视频适配器接入 `AiLogger`
- 在 `AgnesVideoAdapter._post` 与 `generateVideo` 中：
  - 发送请求前调用 `AiLogger.logRequest(providerName: 'Agnes', protocol: 'openai-video', model: _model, endpoint: createUrl, promptSummary: promptText)`；
  - 请求成功时记录 `AiLogger.logResponse`；
  - 请求失败时记录 `AiLogger.logError(errorMsg, providerName: 'Agnes')`。

## Risks / Trade-offs

- **[Risk]** 上游网关偶发限流（如 `429 负载已饱和`） → **Mitigation**: 详细日志记录并在弹窗中清晰完整展示，让用户能够明确得知当前是并发排队或网关状态。
