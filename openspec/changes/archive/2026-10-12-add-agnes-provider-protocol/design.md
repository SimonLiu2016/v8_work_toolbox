## Context

当前系统支持 `openai`、`anthropic` 与 `gemini` 协议。图像生成与视频生成适配器在集成 Agnes 系列模型时，早期版本强制添加了官方特定字段（如 `size: 2K`, `ratio: 9:16`, `extra_body`），导致通过标准 OpenAI 代理/NewAPI 中转站（如 `http://119.29.249.154:3356`）调用时触发 400/401 失败。

## Goals / Non-Goals

**Goals:**
- 在 `AiProtocolType` 枚举中增加 `agnes`，UI 提供明确协议选项与快速模板预设。
- 图像生成：当模型或协议判定为 Agnes 时，固定请求地址为 `POST $baseUrl/v1/images/generations`，请求体采用精简兼容入参 `{"model": "...", "prompt": "..."}`。
- 视频生成：视频任务创建固定为 `POST $baseUrl/v1/videos`，轮询接口同时支持 `$baseUrl/v1/videos/{id}` 与官方 fallback。
- 保持向后兼容：已配置的中转站只需修改协议类型为 `agnes`，无需重新填写或清除 API Key。

**Non-Goals:**
- 不重写整个视频或图像排队调度层。
- 不影响 SenseAudio、Kling 或 SiliconFlow 的既有逻辑。

## Decisions

### 1. 协议枚举扩展与对话对齐
- **决策**: `AiProtocolType.agnes` 在 `AiService` 的文本对话（`chat`）和模型探测（`discoverModels`）中完全复用标准 `openai` 逻辑（`POST /v1/chat/completions` 与 `GET /v1/models`）。
- **理由**: 中转站本质上使用统一的 OpenAI 规范转发各类型请求，文本部分无需额外差异化。

### 2. 图像适配器精简参数
- **决策**: 对于 Agnes 图像模型，默认只向 `/v1/images/generations` 发送 `{"model": targetModel, "prompt": prompt}`，参考图（垫图）仅在存在且存在相应支持时以通用形式透传。移除会引发网关报错的顶层 `extra_body`。
- **替代方案**: 继续维持官方 `extra_body`。劣势：导致第三方中转代理抛错。

### 3. 视频生成与轮询适配
- **决策**: `AgnesVideoAdapter` 规范化任务创建地址为 `$baseUrl/v1/videos`，轮询优先请求 `$baseUrl/v1/videos/$taskId`。

## Risks / Trade-offs

- **[Risk]** 直连官方 Agnes Hub 与中转站返回字段结构略有差异 → **Mitigation**: 在响应解析中同时提取 `data[0].url`、`data[0].b64_json` 以及顶层 `url`，多层解包容错。
