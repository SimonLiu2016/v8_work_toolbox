## Why

AI Video Studio currently exhibits several functional gaps and state-management bugs that degrade generation quality and user experience:
1. In `storyboard_board.dart`, clicking the segment "重新生成" button causes all segment regenerate buttons to show loading spinners, and causes the first shot (#1) in that segment to spin its thumbnail. This is caused by `StudioSegment.fromJson` failing to recognize `segment_id` emitted by LLM script breakdown (resulting in empty string IDs across all segments) and `StudioTaskQueue.tasksForShot` failing to filter out `StudioTaskKind.segment` tasks.
2. In `AssetLibraryPage`, users cannot zoom/lightbox preview images, cannot trigger video playback, and cannot reveal files in Finder or export/download them to local directories.
3. Character generations often suffer from inconsistent styles and an artificial "AI plastic/wax doll" appearance. This stems from an outdated 2022-era prompt baseline (`masterpiece, best quality`) that triggers aggressive smoothing in modern models, coupled with an absence of texture/skin pore tokens and negative anti-plastic constraints.
4. Storyboard generation underutilizes existing script metadata: single-shot video generation (`VideoGenTask`) omits `promptZh` context, and shot duration is constrained to 3~5s with no user-configurable duration selector despite underlying models supporting 2~12s.

Fixing these issues restores storyboard stability, provides full asset inspection and export workflows, elevates visual consistency, and empowers creators with duration and context control.

## What Changes

- **Segment Task & State Isolation**:
  - Update `StudioSegment.fromJson` to accept both `id` and `segment_id` (fallback to stable unique ID) to ensure segments have distinct identifiers.
  - Refactor `StudioTaskQueue.tasksForShot(int shotNumber)` to exclusively match shot-level task kinds (`frame`, `video`), preventing segment-level tasks from bleeding into shot thumbnails.
- **Asset Library Interactive Inspection & Local Export**:
  - Add interactive lightbox zoom dialog for image assets in `AssetLibraryPage` with pan/zoom gestures.
  - Add click-to-play video preview dialog for video assets.
  - Add action buttons on asset cards to reveal files in macOS Finder (`open -R`) and export/save assets to any local file path via system save picker.
- **Anti-AI-Glaze Style Tokens & Consistency Locks**:
  - Overhaul `PromptAssembler._qualityBaseline` to eliminate outdated `masterpiece, best quality` clichés that trigger smooth plastic dolls.
  - Introduce texture-anchoring positive tokens (`raw skin texture, subtle pores, natural matte finish, cinematic soft lighting, 35mm film grain`) and anti-plastic negative constraints (`plastic skin, smooth doll, airbrushed, wax figure, 3d render doll, glossy smooth, uncanny valley`).
  - Align character turnaround injection and production type styles to ensure texture consistency.
- **Storyboard Information Utilization & Duration Control**:
  - Enrich single-shot `VideoGenTask` by passing the shot's prompt/action description (`promptZh`) to the video engine rather than generating blindly from a raw keyframe.
  - Provide a duration dropdown or adjustment control on shot cards conforming to the active video model's supported duration tiers (e.g. 4s, 6s, 8s, 10s, 12s).

## Capabilities

### Modified Capabilities
- `studio-asset-library`: Add interactive lightbox zoom, video playback preview, Finder reveal, and local file export to asset library cards.
- `storyboard-visual-composition`: Eliminate segment and shot task state crosstalk, refine prompt baseline and negative suppression against AI plastic artifacts, enrich video generation prompt context, and support configurable shot durations aligned with model capabilities.

## Impact

- `lib/tools/ai_video_studio/models/studio_models.dart`: Robust `StudioSegment.fromJson` parsing.
- `lib/tools/ai_video_studio/services/studio_task_queue.dart`: Strict task kind isolation for `tasksForShot`.
- `lib/tools/ai_video_studio/services/prompt_assembler.dart`: Modernized quality baselines, micro-texture style tokens, and anti-plastic negative prompts.
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: Supply `promptZh` and contextual metadata to `VideoGenTask`.
- `lib/tools/ai_video_studio/ui/asset_library_page.dart`: Interactive lightbox preview, video player, Finder reveal, and local file export.
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: Correct segment task matching, shot duration selector, and enriched prompt passing.
