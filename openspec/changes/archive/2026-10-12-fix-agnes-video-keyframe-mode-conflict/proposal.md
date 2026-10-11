## Why

Agnes Video 2.5 Flash strictly enforces generation mode separation: in `mode: keyframe`, reference media fields (`images`, `audios`, `videos`) are strictly prohibited. Conversely, when redundant `image` fields are sent, intermediary gateways (like New API / One API) automatically map `image` into `images: [image]`, causing upstream Agnes API to reject the request with HTTP 400 (`"首尾帧素材与参考素材不能同时使用"`). We need to strictly align payload parameters with Agnes official specifications by exclusively passing `first_frame` for keyframe requests.

## What Changes

- **Remove conflicting `image` and `image_url` fields**: In `AgnesVideoAdapter.generateVideo`, provide only `first_frame: dataUri` when in keyframe mode, completely omitting `image` to prevent gateway auto-mapping into `images`.
- **Update Unit Tests**: Ensure tests verify that only `first_frame` is present in keyframe mode, and neither `image` nor `images` is sent.

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: Strictly conform to Agnes video generation mode rules, disallowing reference media fields in keyframe mode.

## Impact

- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: Request payload generation in `AgnesVideoAdapter`.
- `test/senseaudio_video_adapter_test.dart`: Agnes payload verification test suite.
