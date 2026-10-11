## Why

When generating videos via Agnes AI (`agnes-video-2.5-flash`) through the multi-channel gateway (New API), requests intermittently fail with HTTP 400 (`{"code":"invalid_request","message":"keyframe 模式需要 first_frame 或 last_frame"}`). Probe investigation confirms this error originates from bad upstream routing channels that fail to forward the `first_frame` payload parameter, while healthy channels respond with valid task queuing or HTTP 429/503 queue saturation. Additionally, the client currently aborts on HTTP 400 without retry, causing premature failure. This change provides gateway-level resilience, multi-field payload redundancy, and transparent user retry status.

## What Changes

- **Retry Transient Gateway Inconsistencies**: Expand the client-side retry recovery loop in `AgnesVideoAdapter._post` to catch transient gateway dispatch errors, specifically `HTTP 400` with `first_frame 或 last_frame`, `HTTP 502/503/504`, and `HTTP 429`, applying exponential backoff with jitter to rotate to a healthy upstream channel.
- **Redundant Keyframe Parameter Payloads**: Provide multi-field compatibility in the request JSON (`first_frame`, `image`, and `image_url`) so that downstream gateway plugins and reverse proxies extracting any of these image fields will successfully bind the first frame.
- **Queue Saturation and Retry Visibility**: Surface informative progress messages during gateway retries (e.g. queue saturation or route rotation) so users understand system status instead of seeing immediate failures.

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: Add resilient gateway retry and redundant payload bindings for Agnes video generation.

## Impact

- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: Request payload generation and HTTP error handling / retry loop.
- `test/senseaudio_video_adapter_test.dart`: Unit tests verifying payload schema and retry mechanisms.
