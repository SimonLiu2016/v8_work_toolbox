## Context

The application centralizes AI capabilities through `AiConfigStore` and capability slots (`text`, `multimodal`, `tts`, `stt`). Business features (e.g. `VocabularyStudyStore`, `DocAudioReader`, and audio tools) call `OpenAiTtsEngine.synthesize` with `useSystemAiConfig: true`.

Live API probes revealed:
1. Alibaba Cloud Bailian (Model Studio / DashScope / `token-plan.maas.qianwenaiapi.com`) does NOT expose Text-to-Speech models under OpenAI-compatible `/compatible-mode/v1/audio/speech`. Sending requests to that path produces `HTTP 404: Model not exist.` or `HTTP 400: url error`.
2. DashScope hosts high-quality speech models (e.g. `qwen-audio-3.0-tts-plus`) on its native HTTP API: `POST /api/v1/services/audio/tts/SpeechSynthesizer`.
3. Models on this endpoint require specific "longan" voice identifiers (such as `longanlingxin` for female and `longanlufeng` for male). CosyVoice legacy voices (`longxiaochun`) fail with `HTTP 400: [cosyvoice:]Engine error [411]`.
4. The response payload of `SpeechSynthesizer` returns JSON containing `output.audio.url` (or SSE chunks), which requires fetching the final audio binary.

## Goals / Non-Goals

**Goals:**
- Provide complete multi-protocol transparency: seamlessly route TTS requests across OpenAI Audio Speech, StepFun Audio Speech, Xiaomi MiMo Chat Audio, and DashScope SpeechSynthesizer.
- For Qwen / DashScope providers:
  - Normalize endpoint to `POST .../api/v1/services/audio/tts/SpeechSynthesizer`.
  - Format request payload according to DashScope specifications:
    ```json
    {
      "model": "qwen-audio-3.0-tts-plus",
      "input": {
        "text": text,
        "voice": voice,
        "format": "mp3"
      }
    }
    ```
  - Parse DashScope response: extract audio URL from `output.audio.url` (or base64 `data`) and retrieve audio binary bytes.
  - Map foreign voices to DashScope's native voices: `longanlingxin` for female / default, `longanlufeng` for male.
- Update presets and self-heal user configuration to `qwen-audio-3.0-tts-plus`.

**Non-Goals:**
- WebSocket real-time audio duplex streaming (REST HTTP is optimal for sentence and vocabulary playback).

## Decisions

### Decision 1: DashScope Native Protocol Branch in `OpenAiTtsEngine`
In `_synthesizeWithOpenAi`:
When `isQwenModel` is true:
- Construct the DashScope SpeechSynthesizer endpoint:
  If `endpoint` contains `/compatible-mode/v1` or `/v1`, replace with `/api/v1/services/audio/tts/SpeechSynthesizer`.
  Otherwise append `/api/v1/services/audio/tts/SpeechSynthesizer`.
- Transmit DashScope JSON payload:
  `{"model": model, "input": {"text": text, "voice": voice, "format": "mp3"}}`
- On response (HTTP 200):
  Parse JSON:
  - If `output['audio']['data']` is present and non-empty: decode base64.
  - Else if `output['audio']['url']` is present and non-empty: download binary bytes via HTTP GET.
  - Throw formatted error if status != 200.

### Decision 2: Model & Voice Adaptation for DashScope
- Model:
  If model is `qwen-audio-tts`, `cosyvoice-v1`, `tts-1`, or blank: resolve to `qwen-audio-3.0-tts-plus` (or the provider's active TTS model).
- Voice:
  - Female / Default (including StepFun `zhixingjiejie`, OpenAI `alloy`, `nova`, `shimmer`): map to `longanlingxin`.
  - Male (including StepFun `cixingnansheng`, OpenAI `echo`, `onyx`): map to `longanlufeng`.
  - If already a valid `longan` voice (`longanlufeng`, `longanlingxin`): preserve as-is.

### Decision 3: Preset & Config Self-Healing
- In `QwenPreset.ttsModels`: update to `qwen-audio-3.0-tts-plus, qwen-audio-3.1-tts-plus, qwen-audio-3.1-tts-flash`.
- In `AiConfigStore`: upgrade legacy `cosyvoice-v1` and `qwen-audio-tts` to `qwen-audio-3.0-tts-plus`.

## Migration Plan

1. Update `QwenPreset` and `AiConfigStore` self-healing.
2. Implement DashScope native synthesis branch in `tts_engine.dart`.
3. Update unit tests to verify DashScope endpoint resolution, payload construction, and response parsing.
4. Execute `./scripts/deploy_local.sh`.
