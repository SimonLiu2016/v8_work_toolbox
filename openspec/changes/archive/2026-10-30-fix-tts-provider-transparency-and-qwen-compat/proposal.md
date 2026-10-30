## Why

When users switch the global TTS capability slot from StepFun (阶跃星辰) to Qwen (通义千问 / 阿里云百炼) in the AI Settings, business callers such as the Vocabulary Browser ("词汇表"发音播放) fail with:
`OpenAI TTS 合成失败 (HTTP 404): {"code":"InvalidParameter","message":"Model exist.","request_id":"..."}`.

This failure stems from two distinct defects:
1. `QwenPreset.ttsModels` in `ai_config_page.dart` recommended an invalid model identifier `qwen-audio-tts`, which does not exist on DashScope's OpenAI-compatible speech endpoint (`/compatible-mode/v1/audio/speech`). DashScope returns a broken English 404 error (`"Model exist."`, meaning "Model does not exist").
2. Business tools (such as `VocabularyStudyStore`) pass vendor-specific voice identifiers (e.g. StepFun's `zhixingjiejie`). When routing through Qwen, `OpenAiTtsEngine` failed to map or sanitize foreign voices, passing StepFun voice IDs to Qwen, and failed to normalize model aliases (such as `qwen-audio-tts`) to DashScope's supported OpenAI-compatible models (`cosyvoice-v1`, `cosyvoice-v2`, `cosyvoice-v3.5-flash`).

Business callers must experience transparent switching across TTS providers without vendor lock-in or runtime crashes.

## What Changes

- **Update Qwen Preset TTS Models**: Replace the non-existent `qwen-audio-tts` in `QwenPreset.ttsModels` with valid official DashScope speech models (`cosyvoice-v1, cosyvoice-v2, cosyvoice-v3.5-flash`).
- **Transparent Model Normalization in `TtsEngine`**:
  - In `resolveSystemModel` and `_synthesizeWithOpenAi`, detect invalid or alias models (such as `qwen-audio-tts`, `tts-1`, or legacy models) when targeting Qwen/DashScope and automatically map them to `cosyvoice-v1`.
  - Isolate provider candidate models so that switching active providers does not leak models from other providers (e.g., StepFun's `stepaudio-2.5-tts`) into Qwen or OpenAI.
- **Cross-Vendor Voice Sanitization and Adaptive Mapping**:
  - In `TtsEngine`, when dispatching to Qwen, inspect the requested voice. If it is foreign or incompatible (such as StepFun's `zhixingjiejie`, `cixingnansheng`, or OpenAI's `alloy`), automatically map it to a natural Qwen voice (`longxiaochun` for female, `longcheng` for male).
  - Provide similar safe fallback guards for StepFun, OpenAI, and MiMo to guarantee any caller-requested voice remains valid on the resolved provider.
- **Auto-healing of Existing Configuration**:
  - Automatically migrate or repair any existing slot binding in `ai_config.json` where a Qwen provider was bound to `qwen-audio-tts`, upgrading it to `cosyvoice-v1`.
- **Vocabulary Study Voice Decoupling**:
  - Allow `VocabularyStudyStore` to request synthesis without locking to a vendor-specific voice when using system AI config, relying on `TtsEngine`'s provider-adaptive voice resolution.

## Capabilities

### Modified Capabilities
- `ai-configuration`: Update Qwen quick-fill preset models and ensure slot candidate resolution preserves provider isolation and model validity.
- `ai-routing`: Require TTS capability routing and execution to transparently adapt model identifiers and voice names across distinct providers without breaking caller neutrality.

## Impact

- `lib/shell/ai_config_page.dart`: Updated `QwenPreset.ttsModels`.
- `lib/tools/reader/services/tts_engine.dart`: Added Qwen model normalization, cross-vendor voice mapping, and slot isolation.
- `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`: Decoupled default voice from StepFun hardcoding when using system AI config.
- Unit and regression tests for TTS provider switching and voice adaptation.
