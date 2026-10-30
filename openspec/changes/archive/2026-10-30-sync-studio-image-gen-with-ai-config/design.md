## Context

See `proposal.md` for motivation.
Currently, `AiConfigStore` defines capability slots: `text`, `multimodal`, `tts`, `stt`, and `video`. In `lib/tools/ai_video_studio/services/image_gen_adapter.dart`, `LocalStubImageAdapter` and `SiliconFlowImageAdapter` are used, but `SiliconFlowImageAdapter` requires an independent API key and does not integrate with `AiConfigStore`.

By introducing `'image'` as a first-class capability slot, all tools (including the AI Video Studio and future tools) can share a centralized image generation engine configuration.

## Goals / Non-Goals

**Goals:**
- Add `'image'` to `AiCapabilitySlot` and default configuration structures in `AiConfigStore`.
- Add preset image models for SiliconFlow (e.g., `black-forest-labs/FLUX.1-schnell`, `black-forest-labs/FLUX.1-dev`, `stabilityai/stable-diffusion-3-5-large`) and OpenAI (`dall-e-3`, `dall-e-2`).
- Render an "图像生成 (Image)" slot card in `AiConfigPage` with candidate management and status display.
- Introduce `SystemAiImageAdapter` in `image_gen_adapter.dart` that dynamically calls OpenAI-compatible `POST /v1/images/generations` using the active provider from `AiConfigStore`.
- Update `StudioSettingsDialog` to support `system-image` as the default engine, display live provider/model info, and provide connectivity testing and shortcut navigation.

**Non-Goals:**
- Building custom image editing / inpainting canvas inside AI Video Studio (this change focuses on prompt-to-image keyframe generation).
- Supporting proprietary non-HTTP local SD WebUI sockets without an HTTP OpenAI-compatible bridge.

## Decisions

### Decision 1: Standard OpenAI-Compatible `/v1/images/generations` Protocol
- **Rationale**: SiliconFlow, OpenAI, SenseAudio, and many other gateway providers implement `POST /v1/images/generations` with JSON payload `{ model, prompt, size, n }` and response `{ data: [ { url: "..." } ] }` or `{ data: [ { b64_json: "..." } ] }`.
- **Alternatives considered**: Writing provider-specific custom endpoints for SiliconFlow. Using standard `/v1/images/generations` avoids vendor lock-in and allows seamless switching between SiliconFlow, OpenAI DALL-E, etc.

### Decision 2: `SystemAiImageAdapter` Dynamically Resolving Active Slot Provider
- **Rationale**: When `system-image` is selected, `SystemAiImageAdapter` queries `AiConfigStore.instance.getActiveCandidate(AiCapabilitySlot.image)` or `aiConfigStore.candidateSlots['image']`. If configured, it pulls the provider's `baseUrl` and Keychain API key at call time.
- **Alternatives considered**: Passing static credentials into the adapter at creation time. Dynamic resolution ensures that when the user updates credentials in the AI Configuration page, the Studio immediately reflects the change without app restart.

### Decision 3: Studio Settings UX Symmetry with Video Generation
- **Rationale**: Mirroring the exact pattern developed for video generation (`system-video`) — displaying dynamic status pills, connectivity test results, and a "前往 AI 能力配置" button — creates a consistent and intuitive experience for the user.

## Risks / Trade-offs

- **[Risk] Base URL path suffix variance (`/v1` vs bare host)**:
  - *Mitigation*: Reuse URL normalization logic (`normalizeEndpointUrl`) to ensure `/v1/images/generations` is constructed cleanly without duplicate `/v1/v1`.
- **[Risk] Response format variance (Image URL vs Base64 JSON)**:
  - *Mitigation*: In `SystemAiImageAdapter`, check for both `item['url']` and `item['b64_json']`. If base64 is returned, decode and write to temporary file or return data URL.
- **[Risk] Unconfigured system image slot**:
  - *Mitigation*: If `system-image` is selected but no provider/model is active in the `image` slot, the Studio settings displays a warning and the adapter returns a friendly error with a hint to configure it in AI Settings.
