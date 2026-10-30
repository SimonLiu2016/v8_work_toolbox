## Why

用户在配置和使用“实时会议翻译”或语音能力时，缺少对官方 StepFun（阶跃星辰）提供商的原生支持与引导：在 AI 供应商配置弹窗中，缺少 StepFun 快捷预设，且界面缺乏语音识别（STT）与语音合成（TTS）模型的维护字段；此外，StepFun 音频模型官方接入文档区分了 Step Plan 专属路径（`/step_plan/v1/...`）与开放平台常规路径（`/v1/...`），同时在启动实时翻译时缺少 ASR 供应商可用性的前置校验，导致用户在未正确绑定 StepFun 供应商时静默启动失败。

本 change 正式将 StepFun 供应商及其音频模型接入规范集成到系统 AI 基础设施及实时会议翻译中，补全音频模型配置维度，并提供健壮的路径适配与启动拦截。

## What Changes

- **AI 供应商配置增强**：
  - 新增 `StepFunPreset` 标准定义（包含开放平台默认地址 `https://api.stepfun.com/v1`、Step Plan 地址 `https://api.stepfun.com/step_plan/v1`、官方文本模型 `step-2-16k, step-1-8k, stepaudio-2.5-chat`、语音识别模型 `stepaudio-2.5-asr`、语音合成模型 `stepaudio-2.5-tts`）。
  - 在“AI 能力配置”弹窗新增 **`StepFun` 预设快捷按钮**，支持一键填入官方协议 `AiProtocolType.stepfun`、地址及默认模型。
  - 供应商编辑弹窗补齐 **语音识别模型 (STT)** 与 **语音合成模型 (TTS)** 两个配置输入框，支持从界面维护 `sttModels` 与 `ttsModels` 并持久化落盘。
  - 槽位候选选择逻辑完善：添加 `stt` 槽位候选时优先展示供应商配置的 `sttModels`，添加 `tts` 槽位候选时优先展示 `ttsModels`。
- **StepFun 音频 API 端点自适应适配**：
  - 依据官方文档（`https://platform.stepfun.com/docs/zh/step-plan/integrations/audio-api`），增强 ASR 与 TTS 路径解析：无论用户填写 `https://api.stepfun.com/v1` 还是 `https://api.stepfun.com/step_plan/v1`，系统自动准确解析并拼接 `/audio/asr/sse` 及 `/audio/speech`。
- **实时会议翻译 ASR 前置预检与引导**：
  - 点击“开始识别”前，预检当前 `stt` 槽位是否成功解析出可用的 StepFun ASR 客户端。
  - 若未绑定或密钥/端点缺失，立即通过 SnackBar / 错误条给出清晰的指引（“未配置 StepFun ASR，请在 AI 设置中添加 StepFun 供应商并绑定 STT 槽位”），杜绝静默假启动。

## Capabilities

### Modified Capabilities

- `ai-configuration`: 扩展多协议供应商管理，增加 StepFun 原生协议与预设支持，并在供应商配置中支持语音识别（STT）与语音合成（TTS）模型维度的维护与候选槽位绑定。

### New Capabilities

- `live-asr-streaming`: 规范 StepFun ASR SSE 端点适配（兼容开放平台与 Step Plan 路径）、参数封装（PCM 16k 单声道、时间戳、热词、语言代码）以及启动识别前的前置供应商预检与错误提示机制。

## Impact

**改动代码**：
- `lib/shell/ai_config_page.dart`：新增 `StepFunPreset`、预设 Chip、以及 `sttModels` 与 `ttsModels` 输入框和槽位展示联动。
- `lib/tools/live_translator/services/live_translator_coordinator.dart`：优化 `_buildAsrClient` 端点匹配，支持 Step Plan 前缀与更稳健的自适应探测。
- `lib/tools/live_translator/ui/live_translator_page.dart`：启动识别前调用协调器进行 ASR 客户端可用性前置校验，失败时给出可操作提示。
- `test/live_translator_test.dart` / AI 单元测试：补充针对 StepFun 预设模型解析与 ASR 路径拼接的测试用例。

**依赖/数据**：
- 无新增 pub 依赖；复用既有 `AiProviderConfig` 的 `sttModels` / `ttsModels` 字段，配置文件向后兼容。
