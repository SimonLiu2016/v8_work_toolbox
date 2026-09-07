## Why

When users configure the Document Audio Reader to follow system AI settings ("跟随系统AI配置") with Xiaomi MiMo (`mimo-v2.5-tts`) or other modern Chat Audio Completions models, speech synthesis fails silently (the play button spins twice and stops without sound).

This happens because modern audio models like Xiaomi MiMo adopt the OpenAI Chat Audio Completions protocol (`POST /v1/chat/completions` with `role: assistant` and `audio` parameters returning Base64-encoded audio) rather than the legacy speech endpoint (`POST /v1/audio/speech` returning binary stream). In addition, MiMo requires specific supported voice identifiers (`mimo_default`, `冰糖`, `茉莉`, etc.) and rejects unmapped voices with HTTP 400 errors. Audio format mismatches (WAV vs MP3) and lack of UI error toasts also cause silent failures.

## What Changes

- **Chat Audio Protocol Adaptation**: Extend `OpenAiTtsEngine` to auto-detect whether the configured model or provider uses Chat Audio (`mimo-*`, `gpt-4o-audio-*`, or baseUrl pointing to `xiaomimimo.com`), automatically routing to `POST /v1/chat/completions` with the correct JSON payload structure (`messages: [{role: "assistant", content: text}]`, `audio: {format: "wav", voice: ...}`) and decoding Base64 audio from `choices[0].message.audio.data`.
- **Xiaomi MiMo Voice Presets & Fallback Protection**:
  - Expose official Xiaomi MiMo voices in the UI when MiMo is selected (`mimo_default`, `冰糖`, `茉莉`, `苏打`, `白桦`, `Mia`, `Chloe`, `Milo`, `Dean`).
  - Automatically fall back unmapped or incompatible voice IDs (such as legacy Edge or OpenAI IDs) to `mimo_default` when invoking MiMo to prevent HTTP 400 errors.
- **Audio Cache Format Sniffing**: Update `AudioCacheManager` to inspect magic bytes (RIFF/WAVE header vs ID3/MPEG header) so WAV chunks are saved with `.wav` extensions and MP3 chunks with `.mp3` extensions, preventing macOS AVPlayer playback failures.
- **Visible Synthesis Failure Notifications**: Provide user-visible error alerts/toasts in `AudioReaderController` and the reader UI when chunk synthesis fails, instead of halting silently.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Adds support for OpenAI-compatible Chat Audio Completions APIs (including Xiaomi MiMo), automatic protocol routing, MiMo voice presets, voice safety fallback, audio format detection, and visible error notifications.

## Impact

- `lib/tools/reader/services/tts_engine.dart`: Protocol routing and Chat Audio response decoding.
- `lib/tools/reader/models/reader_models.dart`: MiMo voice options and preset mappings.
- `lib/tools/reader/services/audio_cache_manager.dart`: Multi-format audio extension detection and caching.
- `lib/tools/reader/services/audio_reader_controller.dart`: Synthesis error signaling and UI notifications.
- `lib/tools/reader/ui/doc_audio_reader_page.dart`: Voice selector dropdown dynamically updating for MiMo voices, error banner/toast display.
- Test suites: Unit tests for Chat Audio completions parsing and MiMo voice fallback.
