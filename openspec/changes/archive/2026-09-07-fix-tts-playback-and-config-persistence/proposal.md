# Proposal: Fix TTS Playback Resilience, Config Persistence, and Log File Sync

## Why

In the Document Audio Reader (`doc-audio-reader`), users encountered playback failures immediately after clicking the "Play" button. Diagnostic probes identified three contributing failure modes:
1. `TtsSynthesisConfig` is never persisted to disk and hardcodes `mode = TtsMode.edge`. Every time the app restarts, the engine reverts to Edge-TTS, which currently fails globally with HTTP 403 Forbidden due to Microsoft client token invalidation.
2. In commercial AI mode (e.g. Xiaomi MiMo), `loadDocument` and `_playChunk` launch concurrent prefetch and playback tasks simultaneously (`lookahead: 2`), triggering MiMo's strict concurrency and QPS limit (`HTTP 429 Too many requests`), while the existing 429 retry backoff (~9s) is far shorter than MiMo's rate limit cooldown window (~15-30s).
3. `AiLogger` records telemetry only in volatile memory, preventing post-crash or headless inspection of synthesis errors from the filesystem.

Solving this now ensures that user TTS engine choices are remembered across app launches, commercial AI synthesis obeys strict concurrency and backoff requirements, and diagnostic logs are reliably preserved on disk.

## What Changes

- **TTS Configuration Persistence & Smart Defaulting**: Persist `TtsSynthesisConfig` (mode, providerId, model, voiceId, speed) to local storage. On startup, automatically default to `TtsMode.customAi` if an enabled TTS provider or slot candidate (e.g. Xiaomi MiMo) exists in `AiConfigStore`, avoiding dead Edge-TTS defaults.
- **Serialized Non-Colliding Prefetch Queue**: Remove eager `ensureAhead` calls during document loading. When playing chunk `i`, strictly serialize synthesis so playback takes priority, and prefetch chunk `i + 1` only after current chunk begins playback, preventing multi-request concurrency spikes.
- **Resilient 429 Rate Limit Backoff & Extended Timeout**: Increase OpenAI-compatible TTS HTTP timeout from 45s to 90s to accommodate long paragraph generation (e.g. ~36s for 580+ characters). Expand 429 retry backoff with stepped intervals (4s, 10s, 20s) and emit observable progress notifications.
- **AiLogger Persistent Disk Mirroring**: Mirror `AiLogger` entries to a rotating or appended local log file (`~/Library/Application Support/V8WorkToolbox/logs/ai.log`) so synthesis histories and errors can be reviewed directly from the file system.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Add requirements for TTS configuration persistence & smart defaulting, non-blocking serialized prefetch queue scheduling, extended 429 rate limit backoff with 90s synthesis timeout, and file-based AI diagnostic logging.

## Impact

- Affected Code:
  - `lib/tools/reader/ui/doc_audio_reader_page.dart`: Load/save TTS configuration; smart default mode resolution.
  - `lib/tools/reader/services/audio_reader_controller.dart`: Remove eager prefetch during document load; prevent duplicate prefetch collision with current playing chunk.
  - `lib/tools/reader/services/tts_coordinator.dart`: Serialize prefetch queue and ensure strict priority for active playing chunk.
  - `lib/tools/reader/services/tts_engine.dart`: Extend timeout to 90s, enhance 429 backoff retry timing.
  - `lib/services/ai_logger.dart`: Add asynchronous local disk file logging to `logs/ai.log`.
- APIs & Dependencies: None (uses existing Flutter/Dart standard library and file I/O).
