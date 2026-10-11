## Context

See `proposal.md` and Agnes official docs: https://wiki.agnes-ai.cn/zh-Hans/docs/agnes-video-25.
In `mode: keyframe`, passing `image` causes gateway proxy adapters to create `images: [image]`, which violates Agnes's rule: `首尾帧素材与参考素材不能同时使用`.

## Goals / Non-Goals

**Goals:**
- Eliminate payload conflict by sending only `first_frame` in keyframe mode.
- Keep the proven image resizing (720x1280 JPEG 80) and gateway retry mechanisms.

**Non-Goals:**
- Supporting reference video or audio reference inputs at this stage.

## Decisions

### Decision 1: Payload cleanliness
- **Choice**: When `isKeyframe == true`, assign only `payload['first_frame'] = dataUri`. Omit `image` and `image_url`.
- **Rationale**: Tested with live probe against New API gateway, completely eliminating the 400 conflict error.
