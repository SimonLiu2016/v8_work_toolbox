## Context

参见 `proposal.md`。
在短视频工坊中，`AgnesVideoAdapter` 负责调用中转站/上游 Agnes 视频生成端点。实机联调表明：
- Agnes 视频模型对 `mode: "keyframe"` 校验严格，但请求体中的 `'size': '720P'` 会触发网关解析为非法的插件参数枚举，返回 `HTTP 400: plugin usage enum is not an allowed value`。
- `storyboard_board.dart` 的 `_Thumbnail` 组件中，`_frameFile` 是一个 getter。在异步写回触发多次连续 build 周期中，通过 `!` 非空断言取值引发了 `Null check operator used on a null value`。

## Goals / Non-Goals

**Goals:**
- 规范化 `AgnesVideoAdapter` 的 Payload 构建，移除硬编码的非法 `'size': '720P'`。
- 在 `storyboard_board.dart` 的 `_Thumbnail` 中使用不可变局部变量安全解构 `_frameFile` 与 `_clipFile`，彻底消除运行时 `!` 空崩溃。
- 防御性审计并加固 `_CameraMoveSheet` 与 `_MediaPreviewDialog` 等关键组件的空安全逻辑。

**Non-Goals:**
- 不重写视频生成的轮询机制（已验证兼容 `/v1/videos/$taskId` 与 `/agnesapi`）。
- 不更改既有的本地 KenBurns 动效备选通道。

## Decisions

### 1. Agnes 视频请求体字段对齐
- **决策**：构造 payload 时只保留必需有效字段：
  ```dart
  final payload = {
    'model': _model,
    'prompt': promptText,
    'mode': 'keyframe',
    'seconds': durationSeconds,
    'aspect_ratio': '9:16',
    'first_frame': dataUri,
  };
  ```
- **备选方案**：
  - 传 `'size': '1280x720'`：虽然上游网关不报错，但 Agnes 官方视频 flash 模型通过 `aspect_ratio`（如 `9:16`、`16:9`）即可确定比例与输出分辨率，不传冗余的 `size` 最稳健。

### 2. 缩略图渲染局部变量缓存模式
- **决策**：在 `_Thumbnail.build` 开头将可空 getter 缓存至局部不可变变量：
  ```dart
  final frameFile = _frameFile;
  final clipFile = _clipFile;
  final hasFrame = frameFile != null && frameFile.existsSync();
  final hasClip = clipFile != null && clipFile.existsSync();
  ```
  在组件中仅在 `hasFrame` 为 true 的分支使用 `frameFile`，避免重复 getter 调用和任何 `!` 强断言。

## Risks / Trade-offs

- **[Risk]** 部分极端网络下 Agnes 任务可能排队上游饱和 → **Mitigation**: 保留任务失败或饱和时的可读错误信息提示，便于用户知晓并重试。
