## 1. Agnes Video Adapter Optimization & Image Preprocessing

- [x] 1.1 Implement keyframe image compression helper (`_prepareKeyframeDataUri`) using `image` package to resize and compress input frames to ~120KB JPEG Data URIs
- [x] 1.2 Implement dynamic mode selection (`keyframe` when image exists, `text` when no image exists) and clean up payload attributes
- [x] 1.3 Add exponential backoff retry logic (up to 4 retries) for HTTP 429 ("当前分组上游负载已饱和") in `AgnesVideoAdapter._post` with progress logging

## 2. Verification & Automated Deployment

- [x] 2.1 Verify unit/integration tests for `AgnesVideoAdapter` with compressed Data URI payload
- [x] 2.2 Run `./scripts/deploy_local.sh` to compile Release build, re-sign, and update the local desktop app
- [x] 2.3 Verify in-app video generation from the Storyboard Board
