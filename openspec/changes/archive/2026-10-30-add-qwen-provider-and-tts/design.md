## Context

当前系统已有针对 `Agnes`、`StepFun`、`OpenRouter` 的预设集成，以及通用的 `OpenAiTtsEngine`（处理标准 `/v1/audio/speech` 与 Chat Audio `/v1/chat/completions`）。
千问 AI 平台（`platform.qianwenai.com`）拥有两种服务形态：Token Plan（包月/订阅套餐，通过 `token-plan.maas.qianwenaiapi.com` 端点接入）与通用 API（按量计费，通过 `maas.qianwenaiapi.com` 端点接入）。两者对外均支持标准 OpenAI 兼容模式。

## Goals / Non-Goals

**Goals:**
- 在系统 AI 供应商配置中提供 `千问 (Token Plan)` 与 `千问 (通用 API)` 两套一键预设，自动填入官方推荐的文本、语音识别（STT）和语音合成（TTS）模型。
- 在 `OpenAiTtsEngine` 中建立对千问平台及 CosyVoice/Qwen-Audio-TTS 模型的特征探测与音色防御机制。
- 确保当用户在听力练习、文档朗读或会话中选用千问 TTS 时，即便音色未指定或留存有 OpenAI 的 `alloy` 等音色，也能安全自愈回退到千问默认音色（`longxiaochun`），避免 400 失败。

**Non-Goals:**
- 不重构全局 AI 存储数据模型；复用既有 `AiProviderConfig` 结构。
- 不引入 WebSocket 实时语音推流协议，保持纯 HTTP REST 语意清晰。

## Decisions

### 1. 采用对等双预设（Token Plan vs 通用 API）
- **选择**：在 `QwenPreset` 中同时定义 `tokenPlanBaseUrl` 与 `baseUrl`，并在界面提供两个独立的预设 Chip。
- **理由**：用户持有 Token Plan 时必须使用 `token-plan.maas.qianwenaiapi.com` 才能扣除订阅包额度；普通用户使用官方 API Key 则使用 `maas.qianwenaiapi.com`。双 Chip 设计与既有 `StepFun (开放平台)` / `StepFun (Step Plan)` 保持完全一致的交互心智。
- **备选项**：单一预设让用户手动改 URL（体验割裂，易拼错）。

### 2. 在 `OpenAiTtsEngine` 中增加千问特征探测器 `isQwenModel`
- **选择**：
  ```dart
  static bool isQwenModel(String model, {String? baseUrl, String? providerName}) {
    final m = model.toLowerCase();
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();
    return m.contains('cosyvoice') ||
           m.contains('qwen-audio') ||
           m.contains('qwen-tts') ||
           url.contains('qianwenaiapi.com') ||
           url.contains('dashscope.aliyuncs.com') ||
           name.contains('千问') ||
           name.contains('qwen');
  }
  ```
- **理由**：不仅识别显式的模型名称，还识别服务商域名与供应商名称，确保无论用户是自定义模型名还是从预设选择，都能准确捕获。

### 3. 音色防御策略：拦截 OpenAI 默认音色并自动回退
- **选择**：
  千问 CosyVoice 官方系统音色包括 `longxiaochun`（默认标准女声）、`longanyang`（阳光男声）等。如果用户配置中的音色为空，或者音色依然是 OpenAI 体系的音色（`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`），自动替换为 `longxiaochun`。
- **理由**：由于历史配置或切换供应商时容易残留 `alloy`，千问如果收到 `voice: "alloy"` 会报错拒绝请求。前置兜底消除了跨供应商切换后的参数陷阱。

## Risks / Trade-offs

- **[Risk]** 用户使用旧版阿里云通用 DashScope 域名（`dashscope.aliyuncs.com`）而非新版平台域名。
  - **Mitigation**：探测器同时将 `dashscope.aliyuncs.com` 与 `qianwenaiapi.com` 视为千问同源平台，均享受相同的端点拼接与音色防御。
- **[Risk]** 离线或弱网环境下的配置测试。
  - **Mitigation**：测试层完全基于本地注入与 Mock，保证自动化测试不受远程网络与配额波动影响。
