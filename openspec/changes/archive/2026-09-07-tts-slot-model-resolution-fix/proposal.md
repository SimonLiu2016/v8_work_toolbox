## Why

When users configure the Document Audio Reader to follow system AI settings ("跟随系统AI配置"), the synthesis engine incorrectly sends `model: "tts-1"` to third-party providers (such as Xiaomi MiMo) instead of the actual model configured in the system TTS slot (`mimo-v2.5-tts`).

This occurs due to a branching flaw in `OpenAiTtsEngine.synthesize`: when `systemProviderId` is matched, the slot candidate model extraction logic was placed inside an `if (provider == null)` block and was skipped. Furthermore, the fallback logic inspected only `provider.ttsModels`, which is empty when discovered models are categorized under `text`. Consequently, `tts-1` was transmitted, causing Xiaomi MiMo to return `HTTP 400: Unsupported model tts-1`.

## What Changes

- **Priority Slot Model Resolution**: In `OpenAiTtsEngine.synthesize`, decouple provider resolution from slot model extraction. Ensure that whenever `useSystemAiConfig` is true, the active TTS slot bindings in `AiConfigStore.instance.slotBindings['tts']` are queried for the matched provider to extract its configured model (e.g., `mimo-v2.5-tts`).
- **Comprehensive Provider Model Fallback**: If the slot binding does not explicitly assign a model, search all models across the provider (including `models['text']`) for any identifier containing `tts`.
- **MiMo Defensive Model Default**: If the target provider is Xiaomi MiMo and no model is specified or it remains `tts-1`, default directly to `mimo-v2.5-tts` rather than generic OpenAI `tts-1`.
- **UI Settings Dialog Model Synchronization**: In `_TtsSettingsDialog`, ensure the displayed active model label updates to the slot-configured model when switching providers or toggling system configuration.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Guarantees that system TTS slot model bindings and provider-specific voice models are resolved with top priority, preventing default placeholder model substitution.

## Impact

- `lib/tools/reader/services/tts_engine.dart`: Reordered and hardened model resolution logic.
- `lib/tools/reader/ui/doc_audio_reader_page.dart`: Synchronized active slot model resolution in settings dialog.
- `test/doc_audio_reader_test.dart`: Added test cases verifying slot binding model extraction when `systemProviderId` is specified and when provider `ttsModels` list is empty.
