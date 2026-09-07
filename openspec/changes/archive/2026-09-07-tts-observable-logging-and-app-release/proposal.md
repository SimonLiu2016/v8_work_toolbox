## Why

Currently, TTS synthesis in the Document Audio Reader operates without emitting structured events to `AiLogger`. When a synthesis request fails or behaves unexpectedly, users cannot inspect request parameters, target endpoints, response codes, or error details in the in-app AI Log Viewer. Furthermore, the newly introduced Xiaomi MiMo Chat Audio Completions support needs to be compiled and deployed to `/Applications/V8WorkToolbox.app` so that users run the authentic, updated application binary.

## What Changes

- **TTS Observable Logging**: Connect `OpenAiTtsEngine` and `EdgeTtsEngine` to `AiLogger`, logging every request (provider name, model, endpoint, voice, and text summary), response (HTTP status, latency in milliseconds, payload size), and detailed failure message.
- **Production Rebuild & Deployment**: Build the macOS release application bundle using `flutter build macos` and update `/Applications/V8WorkToolbox.app` with the latest binary.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Connects TTS speech synthesis engines to the system AI logging infrastructure to provide full observability and diagnostic visibility in the in-app AI Log Viewer.

## Impact

- `lib/tools/reader/services/tts_engine.dart`: Added `AiLogger` telemetry calls on request, response, and error.
- Application binary: `/Applications/V8WorkToolbox.app` updated with fresh release build.
- Unit tests: Verified logging behavior in test suite.
