## 1. Task-Specific Timeout in AiConstraintEngine

- [x] 1.1 In `AiConstraintEngine`, implement `defaultTimeoutFor(StudioAiTask task)` assigning 240s to `novelMasterExtraction` and `novelEpisodeSegmentation`
- [x] 1.2 Pass the adaptive timeout in `extractNovelMaster` and `segmentNovelEpisodes`
- [x] 1.3 Add unit tests verifying default timeout values for different tasks

## 2. Live Elapsed Ticker in IdeaIncubatorPanel

- [x] 2.1 Add a periodic 1-second elapsed timer during `_importNovelFile`
- [x] 2.2 Format current pass status with live elapsed seconds (e.g. `Pass 1/2, 已耗时 25s`) and guarantee timer cancellation

## 3. Verification and Deployment

- [x] 3.1 Run unit tests (`flutter test test/ai_constraint_engine_test.dart`)
- [x] 3.2 Run `./scripts/deploy_local.sh` to compile, re-sign, and deploy
