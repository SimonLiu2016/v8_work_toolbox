## 1. Data Model Extension

- [x] 1.1 Implement `SceneDirection` enum with 7 directions (`front`, `back`, `left`, `right`, `top`, `bottom`, `topDown`), localized titles, and helper methods in `studio_models.dart`
- [x] 1.2 Implement `SceneDirectionalView` class with `direction`, `descriptionZh`, `promptEn`, `imagePath`, and full JSON serialization in `studio_models.dart`
- [x] 1.3 Extend `SceneCard` with `spatialViews` map, backward-compatible default fallback, and JSON serialization in `studio_models.dart`
- [x] 1.4 Add unit tests for `SceneDirection`, `SceneDirectionalView`, and `SceneCard` serialization and backward compatibility in `test/studio_scene_spatial_profile_test.dart`

## 2. AI Constraint Engine & Spatial Deconstruction

- [x] 2.1 Add `StudioAiTask.sceneSpatialDeconstruction` task definition, system prompt, and schema validator with strict spatial purity in `ai_constraint_engine.dart`
- [x] 2.2 Implement `AiConstraintEngine.deconstructSceneSpatialProfile(...)` to invoke LLM, parse 7-view JSON, and handle fallback
- [x] 2.3 Add unit tests for spatial deconstruction parser, JSON schema validation, and character filter purity in `test/studio_scene_spatial_profile_test.dart`

## 3. Novel Import & Scene Library Batch Deconstruction

- [x] 3.1 Update `NovelImportTaskService` to automatically trigger 7-direction spatial deconstruction during novel scene extraction
- [x] 3.2 Update `StudioProjectManager` to support batch scene spatial deconstruction (`deconstructAllScenesSpatialProfiles`) and single-scene spatial profile saving
- [x] 3.3 Add unit tests verifying novel import and project manager spatial profile batch processing

## 4. UI Implementation (Scene Library & Scene Editor)

- [x] 4.1 Add "一键全息解构全部场景" batch action button with progress indicator in the scene library toolbar in `series_page.dart`
- [x] 4.2 Rebuild `_SceneEditorSheet` in `series_page.dart` to support 7-directional view navigation and editable Chinese/English fields
- [x] 4.3 Add single-scene "AI 全息解构七方位" trigger button and state management in `_SceneEditorSheet`
- [x] 4.4 Add per-view image generation, image asset picking, and "一键生成全息组图 (7视角)" batch generation action in `_SceneEditorSheet`

## 5. Downstream Camera Angle Matching & Production Integration

- [x] 5.1 Implement camera angle to scene direction matching logic in `PromptAssembler`
- [x] 5.2 Integrate matched directional reference image and prompt into storyboard segment generation in `studio_generation_tasks.dart`
- [x] 5.3 Add unit tests for camera angle to spatial view resolution in `test/studio_scene_spatial_profile_test.dart`

## 6. Verification and Local Deployment

- [ ] 6.1 Run full Flutter test suite (`flutter test`) to verify zero regressions
- [ ] 6.2 Execute `./scripts/deploy_local.sh` to build, sign, and deploy updated app to `/Applications/V8WorkToolbox.app`
