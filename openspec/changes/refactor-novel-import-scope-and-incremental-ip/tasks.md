## 1. Worldview Tab Persistence Fix

- [x] 1.1 In `_WorldviewTabState` of `series_page.dart`, flush unsaved edits synchronously on `dispose` and blur
- [x] 1.2 Verify that pasting into worldview and immediately switching tabs retains all content

## 2. Incremental IP Asset Merging in StudioProjectManager

- [x] 2.1 Implement `mergeMasterAssets` in `StudioProjectManager` to deduplicate and upsert characters and scenes by name
- [x] 2.2 Implement `importChapterToEpisode` in `StudioProjectManager` to update/create a single episode without wiping out other episodes
- [x] 2.3 Refactor `importNovelProject` to leverage `mergeMasterAssets`

## 3. Novel Import Scope Dialog in IdeaIncubatorPanel

- [x] 3.1 Build `_showImportScopeDialog` presenting "全案解构 (全本)" vs "单章扩写 (指定集数)"
- [x] 3.2 Wire single-chapter mode to call `mergeMasterAssets` and update the target episode
- [x] 3.3 Ensure progress status accurately shows whether it's full-season or single-episode processing

## 4. Verification and Deployment

- [x] 4.1 Run existing tests (`flutter test`)
- [x] 4.2 Run `./scripts/deploy_local.sh` to compile, re-sign, and deploy
