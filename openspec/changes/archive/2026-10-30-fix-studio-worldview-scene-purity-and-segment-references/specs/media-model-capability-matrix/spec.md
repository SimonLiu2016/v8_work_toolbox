## ADDED Requirements

### Requirement: Agnes 视频模型多参考图上限

系统对 Agnes 专用协议与 `agnes-video-2.5`、`agnes-video-2.5-flash` 视频模型的能力声明中，其 `maxReferenceImages`（可接受参考图数量上限）SHALL 统一声明为 8 张。系统适配器 SHALL 支持将不超过 8 张的参考图片集合转化为 data URI 并装入请求体中的 `images` 数组正常提交。

#### Scenario: 携带 4 到 8 张参考图提交大段生成
- **WHEN** 用户在分镜看板对携带 4 张参考图（3个出场角色 + 1个场景）的片段触发视频生成
- **THEN** 规整层判定参考图数量未超出 8 张上限，请求正常通过规整并提交至云端，不抛出 `MediaCapabilityException`。

### Requirement: 官方模型预设优先与本地声明自愈

在解析模型能力声明时（`MediaCapabilityResolver.resolve`），若本地持久化配置中已声明的模型能力在关键限制指标（如 `maxReferenceImages`、支持模式）上低于系统内置的官方最新预设能力，系统 SHALL 自动对齐并升格使用官方最新预设，以规避历史旧配置残留导致的低上限误拦截；同时，在系统配置界面中保存供应商时，系统 SHALL 自动同步并刷新为官方预设的完整能力矩阵。

#### Scenario: 规整层自动对齐旧配置中残留的低上限
- **WHEN** 用户本地 `ai_config.json` 中对某模型历史记录了 `max_reference_images: 1`，而官方内置预设已更新为 `8`
- **THEN** 系统在解析能力时自动升格为 8 张上限，允许 4 张参考图顺利通过规整。
