## 1. Agnes Video Gateway Payload Compatibility

- [x] 1.1 In `AgnesVideoAdapter.generateVideo`, inject redundant payload keys (`image`, `image_url`) alongside `first_frame` when in keyframe mode
- [x] 1.2 Update unit tests to verify that `first_frame`, `image`, and `image_url` are properly included in the serialized request map

## 2. Gateway Retry and Upstream Rotation

- [x] 2.1 Refactor `AgnesVideoAdapter._post` to identify retriable gateway errors (HTTP 429, HTTP 502/503/504, and HTTP 400 with missing first_frame/last_frame)
- [x] 2.2 Implement exponential backoff with jitter and max retries (up to 4 retries / 5 attempts total)
- [x] 2.3 Provide informative log messages and progress reporting for retry state transitions

## 3. Verification and Deployment

- [x] 3.1 Run unit tests (`flutter test test/senseaudio_video_adapter_test.dart`) to ensure passing suite
- [x] 3.2 Run `./scripts/deploy_local.sh` to compile, re-sign, and redeploy the macOS app
