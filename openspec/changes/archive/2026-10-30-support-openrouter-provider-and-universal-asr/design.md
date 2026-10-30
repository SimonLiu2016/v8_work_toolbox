## Context

当前系统支持 `openai`、`anthropic`、`gemini`、`agnes`、`stepfun` 五种供应商协议，但在 `stt` 槽位与实时会议翻译工具中，`LiveTranslatorCoordinator` 强行过滤 `provider.protocol == AiProtocolType.stepfun`，并将客户端实现硬绑定在 `StepFunAsrClient`。用户在 OpenRouter 等主流聚合供应商上使用 `qwen/qwen3-asr-0.6b` 等先进语音识别模型时，因缺乏协议分支与统一适配器而报错中断。

## Goals / Non-Goals

**Goals:**
- 在供应商体系中正式支持 `openrouter` 协议类型与快捷预设；
- 抽象统一的 `LiveAsrClient` 接口，解耦业务协调器与具体底层 ASR 协议；
- 实现 `OpenRouterAsrClient`，在纯 Dart 内存中高效完成 PCM 到 WAV 的封包与 OpenRouter REST STT 请求调用；
- 改造 `LiveTranslatorCoordinator`，完全遵从 `slotBindings['stt']` 的配置，实现多供应商动态路由。

**Non-Goals:**
- 重构 VadChunker 的音频切分算法；
- 修改 StepFun ASR SSE 的既有通信实现；
- 引入 ffmpeg 外部进程进行 PCM 转 WAV（直接纯内存构造标准 44 字节 RIFF 头）。

## Decisions

### 1. 抽象通用 `LiveAsrClient` 接口
- **决策**：创建 `abstract interface class LiveAsrClient`，将统一签名规范为：
  ```dart
  Stream<AsrEvent> transcribe(
    List<int> pcm, {
    String language = 'zh',
    List<String> hotwords = const [],
    bool enableTimestamp = true,
    String? model,
  });
  ```
- **理由**：既有的 `LiveTranslatorCoordinator._onChunk` 消费 `Stream<AsrEvent>`（处理 delta、done、error），该抽象能同时兼容 StepFun（SSE 增量推送）与 OpenRouter（REST 单块定稿返回），协调器无需任何改动即可无缝运行。

### 2. 内存级 PCM -> WAV 封包算法
- **决策**：在 `OpenRouterAsrClient` 内部编写轻量级 `pcmToWav` 助手函数，为 16kHz 16-bit 单声道 PCM 数据追加标准 44 字节 RIFF/WAVE 头部并转为 Base64。
- **理由**：避免任何外部命令行调用或重量级音频编解码库依赖，内存开销仅几十 KB，耗时 < 1ms。

### 3. OpenRouter 协议与通用 OpenAI 管道集成
- **决策**：
  - 在 `AiProtocolType` 增加 `openrouter`；
  - `AiService` 的 `discoverModels`、`chat` 以及测试连通性逻辑中，将 `AiProtocolType.openrouter` 与 `openai` 共享同一执行分支；
  - 构造 `OpenRouterAsrClient` 时，Base URL 默认解析为 `https://openrouter.ai/api/v1/audio/transcriptions`。

### 4. 槽位优先的动态 ASR 解析策略
- **决策**：`LiveTranslatorCoordinator._buildAsrClient()` 遍历 `slotBindings['stt']` 中的 candidates：
  1. 若匹配供应商的 protocol 为 `stepfun` 或模型名包含 `stepaudio`，返回 `StepFunAsrClient`；
  2. 若匹配供应商的 protocol 为 `openrouter`、`openai`，或 Base URL 包含 `openrouter.ai`，或模型名类似 `qwen3-asr` / `whisper`，返回 `OpenRouterAsrClient`；
  3. 未配置时抛出清晰异常：“未配置可用的语音识别 (STT) 供应商...”。

## Risks / Trade-offs

- **[Risk]** OpenRouter 是基于 HTTP REST 的单块返回，没有 StepFun 逐字的 SSE delta 流。
  - **缓解**：`LiveTranslatorCoordinator` 本身每 2 秒或遇停顿切一块，单块在 OpenRouter 识别完成后直接 emit `AsrEvent.done(text)`，界面依然会每 2 秒实时刷新出一段完整的识别与翻译结果，完全符合实时会议翻译交互预期。
