## Why

当用户在角色卡中点击「生成三视图」或生成形态/分镜图像时，如果全局图像模型槽位配置了 Agnes 图像模型（如 `agnes-image-2.5-flash`），后端 API 会直接抛出 `HTTP 400 Bad Request: {message: negative_prompt不是文生图队列支持的字段}` 导致出图失败。
这是因为 `SystemAiImageAdapter` 在构建 Agnes 图像请求体时，无论在顶层还是 `extra_body` 中，都向其注入了 `negative_prompt` 参数，而 Agnes 的文生图队列服务严格校验入参白名单并不支持负向提示词字段。

## What Changes

- **适配器层清洗 (`SystemAiImageAdapter`)**：
  - 在 `isAgnes` 协议分支下，移除向顶层及 `extra_body` 发送 `negative_prompt` 字段的逻辑。
  - 保留 `prompt`、`size`、`ratio`、`extra_body.response_format` 与 `extra_body.image` 等合法字段。
- **能力矩阵与模型支持 (`media-model-capability-matrix`)**：
  - 在 `MediaModelCapability` 中增加 `supportsNegativePrompt` 声明（默认为 `true`，`agnesImage` 显式声明为 `false`）。
  - 在规整或适配调用层检测模型负向词能力，若不支持则安全阻断向网关发送负向词并打标日志留痕，避免直接发生 400 失败。
- **自动化测试**：
  - 增加针对 `SystemAiImageAdapter` 在包含 `negativePrompt` 时调用 Agnes 协议的拦截断言，确保 payload 中坚决不包含 `negative_prompt`。

## Capabilities

### Modified Capabilities
- `media-model-capability-matrix`: 在图像模型能力声明与请求规整中加入 `supportsNegativePrompt` 维度，声明 Agnes 等模型不支持负向词，确保请求提交前剔除非法字段。

## Impact

- `lib/tools/ai_video_studio/services/image_gen_adapter.dart`: 修复 `SystemAiImageAdapter.generate` 中的 Agnes 请求体组装。
- `lib/services/media_capability.dart`: 在 `MediaModelCapability` 中引入 `supportsNegativePrompt` 并在 `agnesImage` 中显式设为 `false`。
- 测试文件更新：`test/agnes_studio_pipeline_test.dart`、`test/media_capability_matrix_test.dart` 等。
