## Context

See `proposal.md`. Users need to:
1. Preserve worldview and style tokens edited in `_WorldviewTab` regardless of fast tab switching.
2. Select whether a novel file is a full novel or a single chapter in `IdeaIncubatorPanel`.
3. Support incremental IP asset upserting in `StudioProjectManager`.

## Goals / Non-Goals

**Goals:**
- Fix `_WorldviewTabState` save lifecycle so `dispose()` flushes pending saves.
- Add `_showNovelImportScopeDialog` in `IdeaIncubatorPanel` with options:
  - 全本/全剧解构（规划 8~20 集并初始入库）
  - 单章/单集扩写（指定集数：如第 1 集，或追加为新一集）
- Implement non-destructive `upsertCharacters` / `upsertScenes` and `importChapterToEpisode` in `StudioProjectManager`.

**Non-Goals:**
- Automated multi-file batch importing.

## Decisions

### Decision 1: Worldview tab save synchronization
- In `_WorldviewTabState`:
  - Keep `_hasPendingSave` bool or check `_debounce?.isActive == true`.
  - In `dispose()`, if debounce was active, call `_saveSync()` or fire `_save()` immediately before letting super.dispose happen. Also add `FocusNode` with blur trigger.

### Decision 2: Import Scope Dialog
- Present a modal dialog right after file picking:
  - Radio 1: 全本原著全案解构 (适合新剧初始化，规划全季 8-20 集大纲)
  - Radio 2: 单章/局部续写扩写 (适合连载更新，针对指定某一集或追加新一集)
    - Dropdown: 目标集数 (第 1 集 ~ 第 N 集，或「追加为第 N+1 集」)
- When Radio 2 is selected:
  - Extract master assets from chapter (Pass 1) -> incrementally upsert characters, scenes, worldview.
  - Skip whole-season episode wipeout! Instead, update/create ONLY the targeted episode's synopsis, summary, and hook.

### Decision 3: Incremental IP Asset Upsert in Project Manager
- Add `mergeMasterAssets(seriesId, masterExtraction)`:
  - For characters: query existing list. If match found by name, keep existing `id`, `variations`, `basePromptPositive` if customized, and enrich description if needed. If new, save new card.
  - For scenes: query existing scenes. If match found by name, skip or enrich. If new, save new card.
  - For worldview: if new worldview has content, append under a new delimiter if not already present.
