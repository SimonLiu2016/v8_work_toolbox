## 1. Segment Deserialization & Task Queue Isolation

- [x] 1.1 Support `segment_id` and normalize empty `id` in `StudioSegment.fromJson` and `AiConstraintEngine._parseBreakdown`
- [x] 1.2 Restrict `StudioTaskQueue.tasksForShot` to only return `StudioTaskKind.frame` and `StudioTaskKind.video` tasks
- [x] 1.3 Add unit tests verifying `StudioSegment.fromJson` ID compatibility and task queue shot vs segment isolation

## 2. Prompt Assembler & Visual Consistency Enhancements

- [x] 2.1 Overhaul `_qualityBaseline` with micro-texture tokens and enhance `defaultNegativePrompt` with anti-plastic constraints in `PromptAssembler`
- [x] 2.2 Enrich `VideoGenTask` to pass `promptZh` context to `VideoGenRequest`
- [x] 2.3 Add unit tests verifying prompt assembly anti-plastic tokens and `VideoGenTask` prompt forwarding

## 3. Storyboard Board Duration Selector & Segment Regeneration UX

- [x] 3.1 Add duration selection control to `_ShotCard` in `storyboard_board.dart` allowing user to adjust shot duration
- [x] 3.2 Ensure segment card regenerate button and shot thumbnails properly react to isolated task queues without cross-talk

## 4. Asset Library Interactive Inspection & Local Export

- [x] 4.1 Implement image zoom/lightbox dialog (`_openImageLightbox`) and video preview player (`_openVideoPlayer`) in `AssetLibraryPage`
- [x] 4.2 Implement "Reveal in Finder" (`open -R`) and "Export to local file" in `_AssetCard`
- [x] 4.3 Add unit tests for asset library card action handlers and export logic

## 5. Verification & Local App Deployment

- [x] 5.1 Run all tests (`flutter test`) and verify 100% pass rate
- [x] 5.2 Execute `./scripts/deploy_local.sh` to compile release and deploy locally
