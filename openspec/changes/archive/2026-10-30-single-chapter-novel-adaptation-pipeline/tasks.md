## 1. Engine Task Definition & Prompt Design

- [x] 1.1 In `ai_constraint_engine.dart`, add `StudioAiTask.novelChapterAdaptation` with 240s timeout mapping
- [x] 1.2 Design structured System Prompt `_promptNovelChapterAdaptation` enforcing the 4-phase narrative structure (Hook, Conflict, Climax, Cliffhanger) and 300-500 words synopsis
- [x] 1.3 Implement schema validator for `novelChapterAdaptation` requiring non-empty title, synopsis (>= 150 chars), summary, and hook
- [x] 1.4 Expose `AiConstraintEngine.adaptNovelChapter` helper method

## 2. Novel Import Pipeline Orchestration

- [x] 2.1 In `idea_incubator_panel.dart`, eliminate `novelContent.substring(0, 480)` truncation
- [x] 2.2 Wire single-chapter flow to invoke `AiConstraintEngine.adaptNovelChapter` after `extractNovelMaster`
- [x] 2.3 Update progress status ticker to show "正在深入分析本章全篇情节，提炼起承转合影视剧本大纲…" with elapsed time
- [x] 2.4 Pass the AI-adapted title, synopsis, summary, and hook into `StudioProjectManager.importChapterToEpisode`

## 3. Verification & Deployment

- [x] 3.1 Add unit test in `test/ai_constraint_engine_test.dart` verifying prompt template and schema validation for `novelChapterAdaptation`
- [x] 3.2 Update `test/studio_incremental_novel_import_test.dart` to assert full-chapter adapted synopsis preservation
- [x] 3.3 Execute `./scripts/deploy_local.sh` to compile, re-sign, and deploy the updated application to `/Applications/V8WorkToolbox.app`
