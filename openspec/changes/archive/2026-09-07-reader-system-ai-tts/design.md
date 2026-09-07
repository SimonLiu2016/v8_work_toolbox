## Context

See `proposal.md` for motivation.
V8WorkToolbox provides a central `AiConfigStore` managing multi-protocol AI providers, candidate slot bindings, and secure credential storage via macOS `KeychainService`. The Document Audio Reader currently has its own isolated `TtsSynthesisConfig` in `reader_models.dart` and `_SettingsModalContent` in `doc_audio_reader_page.dart`. This design bridges the Document Audio Reader to the global AI configuration store while preserving standalone custom inputs when desired.

## Goals / Non-Goals

**Goals:**
- Seamlessly resolve TTS endpoint, model, and API Key from `AiConfigStore` (prioritizing `tts` slot, falling back to enabled OpenAI providers).
- Allow users to select specific configured providers from a dropdown or toggle back to manual input.
- Allow entering custom voice IDs for non-standard speech engines.
- Add an intuitive UI in `_SettingsModalContent` showing binding status and providing a shortcut to AI Infrastructure Configuration.
- Ensure Keychain API keys are read on demand asynchronously and never saved in plain text files.

**Non-Goals:**
- Modifying the core architecture of `AiConfigStore` or `KeychainService`.
- Supporting non-OpenAI-compatible audio speech protocols (e.g. Anthropic does not provide speech APIs; Gemini speech uses different REST schemas, which are out of scope for now).

## Decisions

1. **Extend `TtsSynthesisConfig`**:
   - Add `bool useSystemAiConfig` (defaults to `true`).
   - Add `String? systemProviderId` (null indicates auto-resolving default `tts` slot).
   - Add `String? customVoiceId` for third-party providers with non-standard voice names.
   - *Rationale*: Keeps configuration immutable and serialized cleanly while backward compatible.

2. **Resolution Hierarchy in `OpenAiTtsEngine.synthesize()`**:
   - If `config.useSystemAiConfig` is true:
     1. If `config.systemProviderId` is non-empty, look up that provider in `AiConfigStore.instance.providers`.
     2. Otherwise, check `AiConfigStore.instance.slotBindings['tts']`. If candidate exists, use its `providerId` and `model`.
     3. Otherwise, fall back to the first active provider with `protocol == AiProtocolType.openai`.
     4. Resolve API key via `await KeychainService.instance.readKey(provider.keychainKeyId)`.
   - If `config.useSystemAiConfig` is false:
     Use `config.customEndpoint` and `config.customApiKey`.
   - *Rationale*: Maximum resilience without breaking existing setups.

3. **UI/UX in `_SettingsModalContent`**:
   - When Commercial AI TTS is selected, display a SegmentedButton / Radio between "跟随系统 AI 配置 (推荐)" and "自定义手动配置".
   - When system AI is selected, display provider dropdown, active binding card with status badge, and jump-to-config button.
   - For voice selection, display standard preset voices and a "自定义音色 ID" text input.

## Risks / Trade-offs

- [Risk] User has not configured any AI provider or Keychain key is missing.
  → *Mitigation*: Show clear descriptive warning card in settings sheet with a direct action button to open AI Configuration; throw helpful user-facing exception if synthesis is attempted without configuration.
- [Risk] Audio cache collisions between different AI providers or models.
  → *Mitigation*: Audio cache key calculation already incorporates voiceId, speed, and text. Cache keys remain isolated.
