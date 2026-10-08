## Why

The AI Video Studio ("AI 短视频工坊") previously relied on hardcoded image generation options: a local stub placeholder engine and an isolated SiliconFlow engine requiring users to manually re-enter an API key inside the studio settings. At the same time, the system-wide AI configuration (`AiConfigStore`) supported slots for text, multimodal (vision/chat), tts, stt, and video, but lacked a dedicated standard slot for `image` (text-to-image). Users who already configured AI providers (such as SiliconFlow, OpenAI DALL-E, or SenseAudio) in the system-level AI Configuration center could not reuse those credentials for storyboard keyframe generation, forcing duplicate configuration and fragmented UX.

Introducing a standard `image` capability slot to the system AI configuration and synchronizing the AI Video Studio settings with it establishes a unified, coherent AI capability management experience across all tools.

## What Changes

- **System AI Configuration**: Add a standard `'image'` (Text-to-Image / 图像生成) capability slot alongside `text`, `multimodal`, `tts`, `stt`, and `video`.
- **Provider & Preset Expansion**: Add preset image models for SiliconFlow (e.g. `black-forest-labs/FLUX.1-schnell`, `black-forest-labs/FLUX.1-dev`, `stabilityai/stable-diffusion-3-5-large`) and OpenAI (`dall-e-3`, `dall-e-2`).
- **AI Settings UI**: Add an "图像生成 (Image)" capability slot card in `AiConfigPage` with candidate provider and model selection, priority reordering, and health status indicators.
- **Image Generation Adapter**: Add `SystemAiImageAdapter` implementing the standard OpenAI-compatible image generation API (`POST /v1/images/generations`), resolving credentials and endpoints dynamically from `AiConfigStore`.
- **Studio Settings Dialog**:
  - Add `system-image` ("跟随系统全局配置") as the recommended and default image generation engine.
  - Display the current system-configured image provider and model dynamically in the UI.
  - Provide a one-click connection test button for image generation.
  - Provide a direct navigation shortcut button to jump to the system "AI 能力配置" page.

## Capabilities

### Modified Capabilities
- `ai-configuration`: Expand capability slots to include `image` (Text-to-Image) with discovery, candidate management, priority ordering, and standard OpenAI `/v1/images/generations` dispatch support.

## Impact

- `lib/services/ai_config_store.dart`: Add `'image'` to standard slot lists, default configs, and provider presets.
- `lib/shell/ai_config_page.dart`: Add Image capability card in the slot configuration tab.
- `lib/tools/ai_video_studio/services/image_gen_adapter.dart`: Add `SystemAiImageAdapter`, register `system-image` in `ImageGenAdapterFactory`.
- `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`: Support `system-image`, status display, connectivity testing, and config navigation.
- Tests: Unit tests for image slot configuration and adapter resolution.
