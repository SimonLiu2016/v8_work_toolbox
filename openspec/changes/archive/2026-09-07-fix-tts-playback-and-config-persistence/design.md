## Context

See `proposal.md` for motivation.

Current implementation state:
1. `TtsSynthesisConfig` is an ephemeral in-memory model in `lib/tools/reader/models/reader_models.dart`. `DocAudioReaderPage` creates `TtsSynthesisCoordinator` with default `TtsSynthesisConfig()` (`TtsMode.edge`) upon `initState()`. Closing and reopening the page or app resets the user's settings.
2. `AudioReaderController.loadDocument()` calls `coordinator.ensureAhead(doc, 0, lookahead: 2)` immediately upon file import. When user clicks "Play", `_playChunk(0)` calls `coordinator.ensureAhead` and `ensureChunkSynthesized(0)` simultaneously, causing concurrent requests that trigger HTTP 429 on providers with strict concurrency/RPM limits like Xiaomi MiMo.
3. `OpenAiTtsEngine` has a 45s timeout and backoff delays of `1500 * (attempt + 1)` ms (~9s total), which is shorter than MiMo's 15~30s rate limit reset window.
4. `AiLogger` keeps logs only in an in-memory ring buffer (`maxEntries = 200`) and prints via `debugPrint`. Logs are lost when the app closes or crashes.

## Goals / Non-Goals

**Goals:**
- Persist reader TTS configuration across app restarts in a dedicated local JSON file.
- Automatically resolve the initial default synthesis mode to `TtsMode.customAi` if an active TTS model provider is available in `AiConfigStore`.
- Serialize prefetching so that playback has absolute priority and prefetching chunk `i + 1` only begins after chunk `i` has started playing.
- Extend commercial AI TTS timeout to 90 seconds and expand 429 retry backoff with stepped intervals (4s, 10s, 20s).
- Mirror all `AiLogger` entries asynchronously to a local disk log file (`logs/ai.log`).

**Non-Goals:**
- Circumventing Microsoft's Edge-TTS server token restrictions (we retain Edge-TTS as an option, but do not default to it when AI models are configured).
- Full redesign of the document reader or karaoke viewer UI.

## Decisions

### Decision 1: Dedicated ReaderConfigStore for persistence
- **Choice**: Store reader settings in `~/Library/Application Support/V8WorkToolbox/config/reader_config.json`.
- **Rationale**: Isolates reader preferences (mode, voiceId, speed, customProviderId, customModel) from window geometry and cleaner tool settings in `app.json`.
- **Alternatives considered**: Merging into `app.json`. Rejected to prevent monolithic config schema bloat.

### Decision 2: Smart Default Engine Resolution on Startup
- **Choice**: When no saved config exists, `ReaderConfigStore` queries `AiConfigStore.instance`:
  - If a configured TTS slot candidate exists or an enabled provider provides a recognized TTS model (e.g. `mimo-v2.5-tts`), initialize `TtsMode.customAi` with that provider and model.
  - If no commercial AI TTS is configured, default to `TtsMode.native` or `TtsMode.edge`.
- **Rationale**: Prevents new or existing users with configured AI models from defaulting to the currently broken Edge-TTS.

### Decision 3: Serialized Non-Colliding Prefetch Queue
- **Choice**:
  1. Remove `ensureAhead` from `AudioReaderController.loadDocument()`.
  2. In `_playChunk(index)`, directly call `await coordinator.ensureChunkSynthesized(_document!, index)`.
  3. Only when chunk `index` successfully begins playing, schedule a low-priority background task to prefetch chunk `index + 1` (`lookahead: 1`).
- **Rationale**: Commercial AI TTS engines frequently enforce concurrency = 1 and strict RPM limits. Strictly sequential operations guarantee zero concurrent collision between player and prefetcher.

### Decision 4: Resilient 429 Backoff Schedule and 90s Timeout
- **Choice**:
  - When encountering HTTP 429, retry up to 3 times with delays of 4s, 10s, and 20s (cumulative ~34s), logging a warning before each delay.
  - Set request timeout to 90 seconds.
- **Rationale**: Dense paragraphs (500-600 characters) require ~36 seconds of inference time on MiMo. 90s gives ample headroom, and 34s backoff covers MiMo's 30-second rate limit rollover window.

### Decision 5: Non-blocking Local Disk Mirroring in AiLogger
- **Choice**:
  - `AiLogger` asynchronously appends formatted entries to `~/Library/Application Support/V8WorkToolbox/logs/ai.log`.
  - Check file size periodically; if it exceeds 5MB, rotate to `ai.log.old`.
- **Rationale**: Enables zero-configuration debugging from terminal or support requests even after the app is closed.

## Risks / Trade-offs

- **[Risk] Long generation time for 500+ character paragraphs**:
  - *Mitigation*: The player displays a buffering / generating spinner with status text so users know generation is underway.
- **[Risk] File I/O overhead on main isolate**:
  - *Mitigation*: Appending to log file uses standard asynchronous I/O (`writeAsString(mode: FileMode.append, flush: false)`), ensuring zero perceptible UI frame drops.
