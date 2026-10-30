## Context

详见 `proposal.md`。工坊中生成三视图、角色形态及场景/分镜图像时，调用方均会传入由 `CharacterTurnaroundPrompt` 或 `ScenePromptBuilder` 生成的负向提示词。对于通用 OpenAI 兼容协议或 SiliconFlow，`negative_prompt` 是常见或兼容字段；但对于 Agnes 图像模型（`agnes-image-2.0-flash`、`agnes-image-2.1-flash`、`agnes-image-2.5-flash`），后端文生图队列服务严格校验参数白名单，收到 `negative_prompt` 即抛出 HTTP 400 错误。

## Goals / Non-Goals

**Goals:**
- 在 `SystemAiImageAdapter` 中针对 `isAgnes` 分支彻底剔除 `negative_prompt`，确保三视图、角色形态及所有图像生成请求正常出图。
- 在 `MediaModelCapability` 中增加 `supportsNegativePrompt` 字段，并在 `agnesImage` 能力声明中显式标记为 `false`。
- 在能力规整与适配调用时增加必要的日志留痕，让“负向词被安全忽略”对开发者排查可见。
- 补充单元测试，验证在有负向提示词输入时，Agnes 图像请求体中绝不包含 `negative_prompt`。

**Non-Goals:**
- 不修改 `CharacterTurnaroundPrompt`、`ScenePromptBuilder` 等提示词生成器输出的负向词本身（当用户切换到支持负向词的图像引擎如 SD/SiliconFlow 时负向词依然生效）。
- 不修改视频生成适配器（`AgnesVideoAdapter` 本身不接收 `negative_prompt`）。

## Decisions

### 1. `SystemAiImageAdapter` 请求体精简化
- **现状**：当前在 `isAgnes` 为 `true` 时，在顶层和 `extra_body` 两处均写入了 `negative_prompt`。
- **决策**：完全删除这两处 `negative_prompt` 的注入。
- **保留字段**：`model`、`prompt`、`size`、`ratio`、`extra_body.response_format` 以及在图生图模式下的 `extra_body.image`。

### 2. `MediaModelCapability` 扩展 `supportsNegativePrompt`
- **声明扩展**：在 `MediaModelCapability` 类中添加 `final bool supportsNegativePrompt`，默认值为 `true`（向后兼容通用引擎）。
- **Agnes 声明**：在 `MediaModelCapability.agnesImage` 中显式指定 `supportsNegativePrompt: false`。
- **替代方案考虑**：仅在 `image_gen_adapter.dart` 中硬编码 if 判断。
  - *排除理由*：与工坊现有的能力矩阵规范（spec: 模型能力声明 / 请求参数规整）脱节。统一纳入能力矩阵可为后续其他不带负向词模型（如 DALL-E 3、FLUX 原生接口）提供统一的能力查询与展示。

## Risks / Trade-offs

- [Risk] Agnes 图像模型在缺乏负向提示词时是否会降低画面纯净度（如三视图背景不够纯白）？
  → Mitigation: `CharacterTurnaroundPrompt.build` 正向提示词中已具备强力的正向纯白底约束（`solid pure white background, completely blank white studio backdrop`）和防须/防环境约束，正向提示词足以有效引导现代流匹配模型生成高保真三视图。
