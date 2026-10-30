## 1. AI Presets & Config Cleansing

- [x] 1.1 Update `QwenPreset.ttsModels` in `lib/shell/ai_config_page.dart` to valid models (`qwen-audio-3.0-tts-plus, qwen-audio-3.1-tts-plus, qwen-audio-3.1-tts-flash`)
- [x] 1.2 Add automatic config self-healing in `AiConfigStore` to upgrade legacy `qwen-audio-tts` and `cosyvoice-v1` slot bindings to `qwen-audio-3.0-tts-plus`

## 2. TTS Engine Multi-Protocol Support & DashScope Adaptation

- [x] 2.1 Refactor `OpenAiTtsEngine.resolveSystemModel` and voice mapping for DashScope (`longanlingxin` for female, `longanlufeng` for male)
- [x] 2.2 Implement DashScope native `SpeechSynthesizer` endpoint routing and payload formatting in `OpenAiTtsEngine`
- [x] 2.3 Implement response parsing for DashScope (URL download / base64 decode) to retrieve audio binary

## 3. Verification & Local Deployment

- [x] 3.1 Update unit tests in `test/tts_engine_provider_transparency_test.dart` to cover DashScope `SpeechSynthesizer` protocol and voices
- [x] 3.2 Run test suite to verify all unit and integration tests pass
- [x] 3.3 Execute `./scripts/deploy_local.sh` to build, sign, and deploy the updated application to `/Applications/V8WorkToolbox.app`
