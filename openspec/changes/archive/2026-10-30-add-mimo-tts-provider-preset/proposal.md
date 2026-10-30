## Why

AI 基础设施配置页缺少小米 MiMo 的快速预设入口。MiMo 的语音合成走 OpenAI Chat Audio Completions 规范，TTS 引擎（`OpenAiTtsEngine`）已具备完整的 MiMo 识别与路由分支（`isMimoModel` / `isChatAudioModel` / `adaptVoiceForProvider` / `resolveSystemModel`），音色清单也已在 `reader_models.dart` 定义——但配置页没有任何 `MimoPreset`，用户必须手查文档填 Base URL、协议、模型才能让引擎识别它。补齐预设后，用户一键即可配齐 MiMo 的 TTS/文本/STT 三槽位模型。

## What Changes

- 在 `lib/shell/ai_config_page.dart` 新增 `MimoPreset` 常量类（对齐既有 `AgnesPreset` / `StepFunPreset` / `QwenPreset` 模式），提供：
  - `displayName = 'Mimo (小米)'`
  - `baseUrl = 'https://api.xiaomimimo.com/v1'`（**API 模式**，按量计费，`sk-` 前缀 Key）
  - `textModels = 'mimo-v2.6-flash, mimo-v2.6-pro'`（替代 2026-10-21 已下线的 v2.5/v2.5-pro 文本系列）
  - `ttsModels = 'mimo-v2.5-tts'`（真机验证出音，`/v1/models` 仍在线）
  - `sttModels = 'mimo-v2.5-asr'`
- 在「快速填充预设」`Wrap` 中新增一个 Mimo 快捷 `ActionChip`，点击后按上述常量预填名称、协议类型（OpenAI Compatible）、Base URL、文本/TTS/STT 模型。
- 协议类型选 `AiProtocolType.openai`（MiMo 是 OpenAI 兼容），**不新增 `AiProtocolType` 枚举值**，避免扩散到 `ai_service.dart` 三处 switch 与 `media_capability.dart` 的 `forProtocolId`。
- **不接入 Token Plan**：官方订阅条款明确「Token Plan 套餐额度仅可在编程工具中使用，禁止以 API 调用形式用于自动化脚本、自定义应用后端等明显非 Coding 场景」，违者停服/封 Key。本 App 是个人工具箱（阅读器 TTS / 同传 ASR / 字幕），属条款划定的违规滥用范围，故本轮不提供 Token Plan 预设入口，仅在风险说明中标注。

## Capabilities

### New Capabilities
<!-- 无：MiMo 预设归属于既有 ai-configuration capability，是新增 requirement 而非新 capability。 -->

### Modified Capabilities
- `ai-configuration`: 在「Multi-protocol AI provider management」与「Builtin Agnes Provider Candidate」之后，新增一条 `Builtin Mimo Provider Candidate` requirement（对齐既有 per-provider-preset requirement 模式），规定 MiMo API 模式预设的预填内容与约束，并约束预设不得提供 Token Plan 入口。

## Impact

- **代码**：`lib/shell/ai_config_page.dart`（新增 `MimoPreset` 常量类 + 一个 `ActionChip`）；无引擎改动（`tts_engine.dart`、`reader_models.dart` 已就绪）。
- **测试**：`test/tts_engine_provider_transparency_test.dart` 的「Presets & Config Self-Healing」组新增断言，校验 `MimoPreset` 常量正确、预填不含 Token Plan 地址、TTS 模型为 `mimo-v2.5-tts`。
- **依赖**：无新增依赖。
- **已知边界（Non-goals）**：
  1. **Token Plan 模式不接**（合规风险，见 What Changes）；`token-plan-cn/-sgp/-ams.xiaomimimo.com` 地址与 `tp-` 前缀 Key 不预填。
  2. **STT 本轮不接**：`live_translator_coordinator._buildAsrClient()` 无 MiMo 分支，`mimo-v2.5-asr` 走 `chat/completions` 的接入需新增 `MimoAsrClient`，属独立后续改动。
  3. **「测试连接」按钮的已知雷区**：`AiService.testConnection` 阶段 2 用 `textModels.first` 发 `user`-role 的 `ping`，MiMo 的 TTS 模型要求 `assistant`-role（否则 400），文本模型 `mimo-v2.6-*` 在当前 `sk-` Key 下返回 402（余额不足）。预设只负责预填，不改变测试连接语义；该行为不因本 change 修复，仅记录。
