## Why

Importing novel text into AI Video Studio (`_importNovelFile`) triggers a two-pass deep deconstruction: extracting master assets (worldview, characters, scenes) followed by whole-series episode segmentation. With complex long-form reasoning models (such as `step-5-preview`), these intensive passes routinely take 60 to 90+ seconds. Because `AiConstraintEngine.run` was hardcoded with a 120-second timeout, slight network jitter or model load causes a `TimeoutException after 0:02:00.000000`, causing the novel import to fail completely. Additionally, the import UI lacks an elapsed-time indicator, leaving users unaware of progress during lengthy processing.

## What Changes

- **Adaptive Task Timeout**: Increase the default timeout for heavy long-form tasks (`novelMasterExtraction` and `novelEpisodeSegmentation`) from 120 seconds to 240 seconds (4 minutes) in `AiConstraintEngine`.
- **Elapsed Timer & Status Updates**: Enhance `idea_incubator_panel.dart` to run an elapsed ticker timer during `_importNovelFile`, showing live seconds (e.g. `Pass 1/2, 已耗时 45s`) to provide clear execution feedback.
- **Resilient Retry for Heavy Timeouts**: Provide a 1-time in-place retry before declaring slot failure when heavy tasks encounter a transient edge timeout.

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: Enhance novel full-text deconstruction resilience and timeout tolerances for long-form reasoning models.

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: Task timeout configuration.
- `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`: Elapsed progress ticker and state management.
- `test/ai_constraint_engine_test.dart` (or related test): Verification of timeout parameters.
