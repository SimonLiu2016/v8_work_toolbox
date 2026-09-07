## Context

See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Guarantee that when `useSystemAiConfig` is true, the model bound to the TTS slot in `AiConfigStore.instance.slotBindings['tts']` is used for synthesis.
- Provide intelligent fallback across all provider models (detecting any model containing `tts`) when slot candidate has no explicit model name.
- Guarantee that Xiaomi MiMo calls never send `tts-1`.
- Keep `_TtsSettingsDialog` synchronized with the active slot model name.

**Non-Goals:**
- Overwriting manually entered custom model names when `useSystemAiConfig` is false.

## Decisions

### Decision 1: Two-Phase Provider and Model Resolution
- **Choice**: Separate provider resolution from model resolution:
  1. Determine `provider` via `systemProviderId` -> slot candidate -> first enabled provider.
  2. With `provider` determined, extract `model` from:
     - Matching candidate in `slotBindings['tts']` where `cand.providerId == provider.id && cand.model.isNotEmpty`
     - First candidate in `slotBindings['tts']` if it has a non-empty model
     - `provider.ttsModels.first` if not empty
     - First model in `provider.models.values` containing `tts`
     - If provider is MiMo (`isMimoModel`), default to `mimo-v2.5-tts`
     - Fallback to `customModel` or `tts-1`.
- **Rationale**: Eliminates the fragile nesting where slot candidate lookup was guarded by `if (provider == null)`.

## Risks / Trade-offs

- **[Risk]** Overriding user's custom manual model in custom mode → **Mitigation**: Only applied when `config.useSystemAiConfig` is true.
