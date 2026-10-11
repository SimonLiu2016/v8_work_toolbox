## Why

When generating videos via Agnes AI (`agnes-video-2.5-flash`) in Storyboard Board, requests fail with `HTTP 400: keyframe 模式需要 first_frame 或 last_frame` or upstream rate limit `HTTP 429: 当前分组上游负载已饱和`.
Investigation revealed that storyboard keyframe PNG files (~1.4MB) encode to over 1.87MB Base64 Data URIs. When transmitted as JSON payloads to the New API proxy gateway (`http://119.29.249.154:3356/v1/videos`), reverse proxies and Go JSON decoders truncate or discard the massive field, causing the upstream Agnes service to perceive `first_frame` as missing. Furthermore, shared upstream gateway channels frequently return 429 rate limits without client retry, causing frequent task failures.

## What Changes

- **Image compression & lightweight encoding for video generation**: Implement an image preprocessor that downscales and compresses input keyframe frames (e.g. to 720P JPEG/WebP under 150KB) before Base64 encoding. This reduces payload size by ~90%, preventing gateway body truncation and guaranteeing `first_frame` integrity.
- **Dynamic mode selection**: Automatically select video generation mode:
  - If a valid keyframe image exists, use `mode: "keyframe"` with the compressed `first_frame`.
  - If no keyframe image is present, automatically fallback to `mode: "text"` (text-to-video) instead of submitting an invalid keyframe request.
- **Exponential backoff retry for upstream 429 rate limits**: Enhance `AgnesVideoAdapter` to catch `HTTP 429` responses ("当前分组上游负载已饱和") and perform exponential backoff retry (up to 4 attempts) with user-friendly progress reporting before giving up.
- **Strict parameter sanitization**: Ensure no prohibited or unrecognized parameter enums (such as `size: "720P"`) are attached to video generation requests.

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: Expand the video generation payload contract to mandate image payload compression, dynamic mode negotiation (`keyframe` vs `text`), and transient error exponential backoff.

## Impact

- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: Add image compression preprocessor, dynamic mode resolution, and 429 backoff retry loop in `AgnesVideoAdapter`.
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: Ensure progress feedback reflects retry states gracefully.
- Upstream network stability and video generation success rate substantially improved.
