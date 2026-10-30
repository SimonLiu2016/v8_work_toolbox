## Context

See `proposal.md` for background and problem motivation.
Currently, `StudioSegment` deserialization in `ai_constraint_engine.dart` and `studio_models.dart` suffers from key naming divergence (`segment_id` vs `id`). Concurrently, `StudioTaskQueue.tasksForShot` does not verify `StudioTaskKind`, leading to task state collision where segment video tasks are attributed to shot #1.
In `AssetLibraryPage`, `_AssetCard` lacks interactive tap handlers and file system integration.
In `PromptAssembler`, `_qualityBaseline` relies on legacy 2022-era tokens (`masterpiece, best quality`) that induce smooth plastic AI faces on modern models.
In `VideoGenTask`, `promptZh` is omitted when dispatching to video adapters, generating silent blind motion.

## Goals / Non-Goals

**Goals:**
- Completely isolate segment tasks and shot tasks in `StudioTaskQueue` and UI progress indicators.
- Provide dual-key compatibility (`id` and `segment_id`) for `StudioSegment` to guarantee non-empty unique IDs.
- Equip `AssetLibraryPage` with image lightbox zoom, video playback preview, Finder reveal (`open -R`), and local file export.
- Upgrade `PromptAssembler` baseline and negative prompts to anchor physical textures and suppress plastic AI doll artifacts.
- Pass `promptZh` context in `VideoGenTask` and provide shot duration customization in storyboard cards.

**Non-Goals:**
- Native audio lip-sync inside raw video diffusion generation (as explained in explore phase, native audio is unsupported by video generation models; TTS and audio mixing belong to Sound Design & Delivery panels).
- Changing local Ken Burns FFmpeg animation pipeline.

## Decisions

### Decision 1: Dual Key Deserialization and Fallback in `StudioSegment`
In `StudioSegment.fromJson`:
- Check `json['id'] as String?`, `json['segment_id']?.toString()`, or synthesize `'seg-${json['segment_id']}'`.
- If both are absent or blank, derive a deterministic ID `'seg-${shotNumbers.firstOrNull ?? 1}'`.
- In `ai_constraint_engine.dart`, ensure breakdown serialization exports both `'id': 'seg-$id'` and `'segment_id': id`.

### Decision 2: Task Kind Isolation in `StudioTaskQueue`
In `StudioTaskQueue.tasksForShot(int shotNumber)`:
- Add filter: `t.kind == StudioTaskKind.frame || t.kind == StudioTaskKind.video`.
- Segment tasks (`StudioTaskKind.segment`) are only returned by `tasksForSegment(String segmentId)`.
- This strictly eliminates task state collision between segment cards and shot cards.

### Decision 3: Anti-AI-Glaze Texture Baseline and Negative Prompt Overhaul
In `PromptAssembler`:
- Replace `_qualityBaseline`:
  ```dart
  static const String _qualityBaseline =
      'authentic film texture, natural skin tones, subtle micro details, cinematic soft lighting, raw photo, 8k resolution';
  ```
- Enhance `defaultNegativePrompt`:
  ```dart
  static const String defaultNegativePrompt =
      'plastic skin, smooth doll, airbrushed, wax figure, mannequin, '
      '3d render doll, fake glossy skin, uncanny valley, over-saturated, '
      'cartoonish, blurry, low quality, worst quality, deformed, duplicate, '
      'extra limbs, bad anatomy, disfigured, watermark, signature, text, '
      'subtitles, on-screen text, speech bubble, gibberish characters, '
      'deformed mouth, mouth open speaking, username, logo, cropped, out of frame';
  ```
- For Chinese genre presets (e.g. `drama`, `guofeng`), append traditional Chinese Xuanhuan texture tokens to enhance cloth weaves and ancient aesthetic consistency.

### Decision 4: Asset Library UX Parity with Agnes Playground
In `AssetLibraryPage`:
- Wrap thumbnail in `InkWell`:
  - When `asset.kind == AssetKind.image`: open `_openImageLightbox` with `InteractiveViewer`.
  - When `asset.kind == AssetKind.clip`: open `_openVideoPlayer` with video preview dialog.
- Add bottom card actions:
  - Finder icon (`Icons.folder_open`): executes `Process.run('open', ['-R', asset.file.path])` on macOS.
  - Export icon (`Icons.download`): uses system save picker (`file_selector` or fallback directory copy) to save to user's desired folder.

### Decision 5: Shot Duration Selector and Video Task Context Enrichment
In `storyboard_board.dart`:
- Replace static duration text with an interactive duration selector (chips or dropdown: 3s, 4s, 5s, 6s, 8s, 10s, 12s) allowing direct updates to `shot.durationSec`.
- In `VideoGenTask.run`: pass `promptZh: shot.assembledPrompt ?? shot.actionZh` into `VideoGenRequest` so the video model receives cinematic motion context.

## Risks / Trade-offs

- **[Risk]** Existing episodes created in local cache might contain `segment.id == ""` from previous breakdown runs.
  → **Mitigation**: In `StudioEpisode.migrateSegmentsIfNeeded` and `StudioSegment.fromJson`, automatically normalize any empty `id` into `seg-<index>`.
- **[Risk]** Model rejecting prompt length if Chinese action text is excessively long.
  → **Mitigation**: `PromptAssembler` already maintains `_joinWithinLimit` with `kMaxPromptWords = 750`.
