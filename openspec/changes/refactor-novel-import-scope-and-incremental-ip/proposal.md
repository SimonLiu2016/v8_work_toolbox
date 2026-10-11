## Why

Users importing novel text face three usability barriers:
1. When in "Episode Continuation" (单集续写扩写) mode, importing text forces a whole-series split (into 8-20 episodes) and destroys existing episodes, rather than letting users target a single chapter/episode.
2. IP assets (characters, scenes, worldview) do not incrementally enrich as new novel chapters are added across a series' lifecycle; existing data gets overwritten instead of upserted.
3. In the "IP Master Library" -> "Worldview" tab, pasting or typing content followed immediately by switching tabs causes edits to be discarded because the debounce timer is canceled upon dispose without flushing changes to disk.

## What Changes

- **Worldview Tab Instant Flush on Dispose & Blur**: In `_WorldviewTabState`, flush unsaved edits immediately upon widget disposal and focus lost, ensuring typed or pasted worldview/style text is 100% persisted.
- **Novel Import Scope Dialog**: Introduce an import scope modal before executing AI deconstruction:
  - **Full Series / Multi-chapter (全案解构)**: Deconstructs novel into full-season multi-episode plan and seeds initial master IP assets.
  - **Single Chapter / Episode Continuation (单集/章节扩写)**: Targets a specified episode (or appends as episode N+1), extracting chapter events into the target episode synopsis/hook while preserving the rest of the series.
- **Incremental IP Asset Upsert**: In `StudioProjectManager`, implement non-destructive upserting for characters (deduplicate by name, preserve customized prompts), scenes (deduplicate by name), and append/enrich worldview notes as new chapters are imported.

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: Add novel import scope selection, incremental IP asset merging, and loss-free worldview tab persistence.

## Impact

- `lib/tools/ai_video_studio/ui/series_page.dart`: `_WorldviewTabState` save-on-dispose lifecycle fix.
- `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`: Scope selection dialog and single-episode deconstruction dispatch.
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: `importNovelProject` and `importChapterToEpisode` with incremental character/scene/worldview upsert.
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: Chapter-level episode expansion task support if needed.
