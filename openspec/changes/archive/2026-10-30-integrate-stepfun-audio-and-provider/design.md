## Context

`AiProtocolType.stepfun` 已经在底层枚举中定义，且 `AiProviderConfig` 具有 `sttModels` 与 `ttsModels` 字段。然而在 `lib/shell/ai_config_page.dart` 的前端配置界面中，缺少 StepFun 的快捷预设入口，且编辑弹窗仅暴露了文本、视频、图像模型的输入框，使得音频相关的模型列表无法通过界面直接维护。

在调用链路侧，实时会议翻译依赖 `StepFunAsrClient` 与 `stepaudio-2.5-asr` 模型，但目前缺少启动前的 ASR 客户端可用性校验，且官方文档（`https://platform.stepfun.com/docs/zh/step-plan/integrations/audio-api`）明确指出了 Step Plan 专属路径（`/step_plan/v1`）与开放平台常规路径（`/v1`）并存的现状。

## Goals / Non-Goals

**Goals:**
- 在 `lib/shell/ai_config_page.dart` 中建立 `StepFunPreset` 标准，提供快捷预设 Chip。
- 在供应商编辑弹窗中补齐“语音识别模型 (STT)”与“语音合成模型 (TTS)”两个文本输入字段，打通界面的读取与保存。
- 保证 `stt` 槽位与 `tts` 槽位在添加候选时优先过滤对应类型的模型。
- 在 `LiveTranslatorCoordinator` 中支持兼容开放平台与 Step Plan 两种前缀的 `/audio/asr/sse` 端点拼接。
- 在实时会议翻译点击“开始识别”时实现 Fail-Fast 预检，若无有效 StepFun ASR 客户端立即拦截并弹窗引导。

**Non-Goals:**
- 本次暂不实现基于 WebSocket 的 `stepaudio-2.5-realtime` 双向对话，维持基于 HTTP + SSE 的流式 ASR 架构。
- 不修改底层的 Keychain 凭证存储机制。

## Decisions

### 决策 1：参考 `AgnesPreset` 模式建立 `StepFunPreset`

- **选择**：在 `ai_config_page.dart` 中定义：
  ```dart
  abstract final class StepFunPreset {
    static const String displayName = 'StepFun (阶跃星辰)';
    static const String baseUrl = 'https://api.stepfun.com/v1';
    static const String stepPlanBaseUrl = 'https://api.stepfun.com/step_plan/v1';
    static const String textModels =
        'step-2-16k, step-1-8k, step-1-flash, step-1v-8k, stepaudio-2.5-chat';
    static const String sttModels = 'stepaudio-2.5-asr';
    static const String ttsModels = 'stepaudio-2.5-tts';
  }
  ```
- **原因**：保持工程已有设计模式一致，为用户提供准确官方在售型号，避免手动输入的拼写错误。

### 决策 2：编辑弹窗全面补全音频模型维护维度

- **选择**：在编辑供应商弹窗中新增 `sttModelsCtrl` 与 `ttsModelsCtrl`，不仅对 StepFun 有效，其他提供语音服务的供应商（如 OpenAI Whisper、SenseAudio 等）也能一并维护。
- **原因**：`AiProviderConfig` 底层数据字段已支持 `sttModels` 和 `ttsModels`，补齐 UI 闭环是体系化的最佳设计。

### 决策 3：端点解析支持 Step Plan 与开放平台自适应

- **选择**：`_buildAsrClient` 提取 `provider.baseUrl`：
  - 若包含 `/step_plan`（如 `https://api.stepfun.com/step_plan/v1`），解析为 `https://api.stepfun.com/step_plan/v1/audio/asr/sse`；
  - 若为标准 `/v1`，解析为 `https://api.stepfun.com/v1/audio/asr/sse`；
  - 若为裸域名，默认追加 `/v1/audio/asr/sse`。
- **原因**：避免因 Step Plan 用户填写文档指定的专属前缀而导致 404 错误。

### 决策 4：启动识别时 Fail-Fast 预检

- **选择**：`LiveTranslatorCoordinator.start()` 首先调用 `_buildAsrClient()`。若返回 `null`，立即抛出明确异常或更新 `state.lastError`，并在 UI 侧弹出提示“未配置可用的 StepFun ASR 供应商，请前往 AI 设置绑定 STT 槽位”。
- **原因**：杜绝静默假启动、给用户制造“无声无反应”的困惑。

## Risks / Trade-offs

- **[Risk] 用户直接填写 Step Plan 的 WebSocket 路径**
  - **Mitigation**: Base URL 提示文案与预设明确说明填入 HTTP API 根路径 `https://api.stepfun.com/step_plan/v1` 或 `https://api.stepfun.com/v1`。
