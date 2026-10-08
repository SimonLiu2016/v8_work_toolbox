## 1. System AI Configuration & Preset Models

- [x] 1.1 Add `image` capability slot to `AiCapabilitySlot` and standard slot lists in `lib/services/ai_config_store.dart`
- [x] 1.2 Add preset image models for SiliconFlow (Flux Schnell, Flux Dev, SD 3.5 Large) and OpenAI (DALL-E 3, DALL-E 2) in provider definitions
- [x] 1.3 Add "图像生成 (Image)" capability slot card with model selection and priority reordering in `lib/shell/ai_config_page.dart`
- [x] 1.4 Write unit tests in `test/services/ai_config_store_test.dart` verifying `image` slot serialization, migration, and default bindings

## 2. Image Generation Adapter Implementation

- [x] 2.1 Implement `SystemAiImageAdapter` in `lib/tools/ai_video_studio/services/image_gen_adapter.dart` using standard OpenAI `/v1/images/generations` protocol
- [x] 2.2 Support dynamic active candidate resolution from `AiConfigStore`, decoding URL and Base64 responses
- [x] 2.3 Update `ImageGenAdapterFactory` to register `system-image` engine and handle resolution fallback
- [x] 2.4 Add unit tests for `SystemAiImageAdapter` and `ImageGenAdapterFactory` in `test/tools/ai_video_studio/image_gen_adapter_test.dart`

## 3. Video Studio Settings UI Integration

- [x] 3.1 Update `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart` to support `system-image` as the default/recommended image engine
- [x] 3.2 Display real-time system image provider and model information banner in the settings dialog
- [x] 3.3 Implement "测试连通性" button for image generation testing in the dialog
- [x] 3.4 Provide direct navigation button to the system "AI 能力配置" page
- [x] 3.5 Run full test suite and verify build/deployment
