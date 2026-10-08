## 1. Multi-modal SenseAudio Provider Preset

- [x] 1.1 Update `lib/shell/ai_config_page.dart` preset button for SenseAudio to include both video models and image models (`senseaudio-image-2.0-260319`, `doubao-seedream-5-0-260128`, `sensenova-u1-fast`)
- [x] 1.2 Verify `AiProviderConfig` holds both video and image model lists under a single provider and persists to storage correctly

## 2. SenseAudio Image Adapter & Resolution Snapping

- [x] 2.1 Implement dimension snapping utility `snapToSupportedSenseAudioSize` in `lib/tools/ai_video_studio/services/image_gen_adapter.dart`
- [x] 2.2 Implement `SenseAudioImageAdapter` supporting `/v1/image/sync` direct out and `/v1/image/async` with `/v1/image/pending` polling
- [x] 2.3 Support encoding local reference images to base64 Data URI and transmitting in the `reference` parameter
- [x] 2.4 Integrate full `AiLogger` tracing into `SenseAudioImageAdapter` and `SystemAiImageAdapter`

## 3. Factory Routing & Video Studio Integration

- [x] 3.1 Update `ImageGenAdapterFactory` to dynamically dispatch to `SenseAudioImageAdapter` when SenseAudio is configured, falling back to OpenAI protocol otherwise
- [x] 3.2 Add unit and mock integration tests covering SenseAudio sync/async, dimension snapping, error parsing, and logger records
- [x] 3.3 Verify full test suite passes and build/deploy local application
