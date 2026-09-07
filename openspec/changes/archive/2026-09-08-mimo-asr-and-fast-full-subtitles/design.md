## Context

See proposal.md for motivation. Currently, `AiSubtitleService` communicates exclusively using the OpenAI Whisper multipart format (`POST /v1/audio/transcriptions`). Users configuring Xiaomi MiMo (`mimo-v2.5-asr`) encounter 400/404 errors because MiMo requires the OpenAI Chat Completions schema (`POST /v1/chat/completions`) with Base64 audio in `input_audio` and `asr_options`. Furthermore, seeking along the timeline interrupts or shows no subtitles because generation was either aborted or limited to a local 10-minute slice.

## Goals / Non-Goals

**Goals:**
- Provide native support for Xiaomi MiMo ASR (`mimo-v2.5-asr`) via Chat Completions JSON protocol alongside OpenAI Whisper.
- Accurately construct timeline timestamps for MiMo ASR by chunking audio into short slices (e.g. 10~15s) and executing parallel transcriptions via a concurrent pool.
- Enable fastest full-audio extraction for both local files (ffmpeg mono 32k) and online web URLs (`yt-dlp` audio-only stream extraction).
- Generate, persist, and mount full `.srt` subtitle tracks so user mouse seeking anywhere on the timeline retains instantaneous subtitle synchronization.

**Non-Goals:**
- Supporting non-standard proprietary local speech-recognition SDKs requiring C++ bindings or dynamic libraries.
- Replacing the existing video player engine (MediaKit/MPV).

## Decisions

### Decision 1: Protocol Dispatch in AiSubtitleService
- **Decision**: In `_transcribeAudioFile()`, inspect the resolved STT provider and model:
  - If `model == 'mimo-v2.5-asr'` or `provider.baseUrl.contains('xiaomimimo.com')`: route to `_transcribeWithMimo()`.
  - Otherwise: route to `_transcribeWithOpenAiWhisper()`.
- **Rationale**: Keeps provider configuration completely transparent to the user without requiring manual protocol switching in the UI.

### Decision 2: Chunk-Based Parallel ASR for MiMo
- **Decision**: Because `mimo-v2.5-asr` transcribes an audio chunk into a direct string in `choices[0].message.content` rather than returning an array of fine-grained timestamps, we segment full audio into 10~15 second slices with known offsets `[start, end]`. A worker pool (concurrency: 5) executes the requests in parallel and collects ordered `SubtitleSegment` items.
- **Alternatives Considered**:
  - Sending the entire 1-hour audio in one single prompt: payload would exceed 20MB Base64, context window limits would be exceeded, and timecode information would be completely lost.
  - Sequential single-threaded chunking: too slow (60 chunks would take 60+ seconds). Parallel execution with 5 workers completes in ~6-10 seconds.

### Decision 3: Source-Aware Fastest Full Audio Extraction
- **Decision**:
  - Local video: `ffmpeg -y -i <path> -vn -ar 16000 -ac 1 -b:a 32k <out.mp3>` (1~2 seconds).
  - Online web URL (Bilibili, YouTube): `yt-dlp -f "ba/b" -x --audio-format mp3 --audio-quality 32k -o <out.mp3> <url>` (extracts only audio track, avoiding video download).
  - Direct CDN media URL: `ffmpeg` with User-Agent/Referer headers.

### Decision 4: Timeline Continuity via Full SRT Mount
- **Decision**: When full subtitles are generated, write out a standard `.srt` file, save to `PrivateStorageManager.subtitlesDir`, update `MediaHistoryStore`, and call `ctrl.mountSubtitleFile(path)`.
- **Rationale**: Mounting a complete subtitle track guarantees that `ctrl.position` lookups always find the corresponding text anywhere on the timeline during playback and seeking.

## Risks / Trade-offs

- **[Risk] Xiaomi MiMo Rate Limits with Parallel Chunks** → Mitigation: Limit concurrency to 5 parallel requests and implement backoff/retry.
- **[Risk] Silence / Background Noise in Chunks** → Mitigation: Filter out empty or punctuation-only responses ("嗯。", "...") so subtitles remain clean and unobtrusive.
