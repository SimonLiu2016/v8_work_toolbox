## 1. Data Model & Engine Resolution

- [x] 1.1 Update `TtsSynthesisConfig` in `lib/tools/reader/models/reader_models.dart` to support `useSystemAiConfig`, `systemProviderId`, and `customVoiceId` with backwards-compatible JSON serialization.
- [x] 1.2 Enhance `OpenAiTtsEngine.synthesize()` in `lib/tools/reader/services/tts_engine.dart` to dynamically resolve endpoint, model, and API Key from `AiConfigStore` and `KeychainService`.

## 2. Settings Modal UI Enhancement

- [x] 2.1 In `_SettingsModalContent` in `lib/tools/reader/ui/doc_audio_reader_page.dart`, add source toggle ("使用全局 AI 配置" vs "自定义独立配置") and system provider dropdown selector.
- [x] 2.2 Add current binding status card, shortcut button to open AI Configuration, and custom voice ID input in `_SettingsModalContent`.

## 3. Testing & Verification

- [x] 3.1 Add unit tests in `test/doc_audio_reader_test.dart` covering system AI provider resolution, TTS slot priority, Keychain key fetching, and fallback behaviors.
- [x] 3.2 Run `flutter test` and compile release build to verify zero regressions.
