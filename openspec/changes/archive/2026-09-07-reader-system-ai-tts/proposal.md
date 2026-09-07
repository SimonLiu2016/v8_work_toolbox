## Why

In V8WorkToolbox, the central AI Infrastructure Configuration (`AiConfigStore`) manages multi-protocol AI providers, secure Keychain credentials, and capability slot bindings (including `tts`). Currently, the Document & Web Article Audio Reader's TTS settings modal requires users to manually input the API Endpoint, API Key, and Model name when using commercial AI TTS. This duplicates effort and exposes keys in plain form. Integrating the global AI configuration into the audio reader allows one-click adoption of existing AI credentials and models.

## What Changes

- Add "Use Global AI Configuration" as the default option when selecting Commercial AI TTS in the audio reader settings modal.
- Support automatic resolution of the system `tts` capability slot, preferred provider, and secure Keychain API key.
- Provide a provider dropdown to select among configured system AI providers or fall back to manual entry.
- Support custom voice IDs in addition to standard preset voices (e.g. for SiliconFlow, Minimax, or local TTS endpoints).
- Provide quick status display of the bound system provider and a shortcut button to jump to the "AI Infrastructure Configuration" page if unconfigured.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Extend commercial AI TTS requirement to support resolving credentials and endpoints from global `AiConfigStore` and custom voice IDs.

## Impact

- `lib/tools/reader/models/reader_models.dart`: Add `useSystemAiConfig`, `systemProviderId`, and custom voice fields to `TtsSynthesisConfig`.
- `lib/tools/reader/services/tts_engine.dart`: In `OpenAiTtsEngine.synthesize`, dynamically resolve endpoint and API key from `AiConfigStore` and `KeychainService` when `useSystemAiConfig` is true.
- `lib/tools/reader/ui/doc_audio_reader_page.dart`: Update `_SettingsModalContent` to display system AI binding status, provider selector, navigation button to AI Config, and custom voice ID input.
- `test/doc_audio_reader_test.dart`: Add tests for system AI resolution in TTS synthesis.
