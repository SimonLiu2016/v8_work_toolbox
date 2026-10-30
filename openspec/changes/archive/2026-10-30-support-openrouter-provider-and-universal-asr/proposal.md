## Why

当前系统在“AI能力配置”中缺少主流的模型聚合供应商类型 `openrouter` 与快捷预设；同时在“实时会议翻译”中写死了仅允许 `stepfun` 供应商，导致用户在 `stt` 语音识别槽位中绑定了 OpenRouter 的 ASR 模型（如 `qwen/qwen3-asr-0.6b`）时报错无法启动。本变更引入 OpenRouter 供应商支持，并将 ASR 识别客户端抽离为统一抽象，支持按槽位绑定的具体供应商动态路由。

## What Changes

- **新增 OpenRouter 协议类型与预设**：在 `AiProtocolType` 中添加 `openrouter` 类型，并在“添加模型供应商”对话框提供包含 `https://openrouter.ai/api/v1`、预置文本模型及 `qwen/qwen3-asr-0.6b` 语音识别模型的快捷预设。
- **AiService 对 OpenRouter 兼容支持**：使 `AiService` 的模型发现与对话调用对 `AiProtocolType.openrouter` 平滑走 OpenAI 兼容管线。
- **抽象通用 LiveAsrClient 接口**：定义通用的 `LiveAsrClient`，规定 `Stream<AsrEvent> transcribe(...)` 统一签名，解耦具体供应商底层传输差异。
- **实现 OpenRouterAsrClient**：在内存中纯 Dart 将 16kHz PCM 音频切片包装为规范的 WAV 字节流，按官方协议请求 OpenRouter `POST /api/v1/audio/transcriptions` 并产出识别事件。
- **ASR 客户端按槽位自适应构建**：重构 `LiveTranslatorCoordinator._buildAsrClient()`，根据 `stt` 槽位当前所绑定的供应商协议类型与模型名称，自适应构建 `StepFunAsrClient` 或 `OpenRouterAsrClient`。

## Capabilities

### New Capabilities

- `openrouter-provider-and-stt`: OpenRouter 供应商类型支持与基于能力槽位的通用 ASR 客户端契约。

## Impact

- `lib/services/ai_config_store.dart`: `AiProtocolType` 枚举增加 `openrouter`。
- `lib/services/ai_service.dart`: 兼容 `openrouter` 协议的发现与会话调用。
- `lib/shell/ai_config_page.dart`: 添加 OpenRouter 预设常量与 ActionChip。
- `lib/tools/live_translator/services/live_asr_client.dart`: 新增统一接口与 OpenRouter ASR 实现。
- `lib/tools/live_translator/services/stepfun_asr_client.dart`: 实现统一接口。
- `lib/tools/live_translator/services/live_translator_coordinator.dart`: 槽位自适应解耦。
