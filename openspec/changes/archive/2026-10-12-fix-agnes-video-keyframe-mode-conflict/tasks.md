## 1. Eliminate Payload Parameter Conflict

- [x] 1.1 In `AgnesVideoAdapter.generateVideo`, remove `image` and `image_url` from keyframe mode payload, keeping only `first_frame`
- [x] 1.2 Update unit tests to verify that `image` is not included in the payload

## 2. Verification and Deployment

- [x] 2.1 Run unit tests (`flutter test test/senseaudio_video_adapter_test.dart`)
- [x] 2.2 Run `./scripts/deploy_local.sh` to compile, re-sign, and deploy
