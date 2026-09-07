## 1. Xiaomi MiMo ASR Client & Adaptive Dispatcher

- [x] 1.1 Implement `_transcribeWithMimo` in `AiSubtitleService` using `/v1/chat/completions` JSON schema with Base64 MP3 and `asr_options`
- [x] 1.2 Implement protocol detection in `_transcribeAudioFile` to seamlessly route between MiMo ASR and OpenAI Whisper based on model and provider metadata
- [x] 1.3 Add silence and non-speech filler text filtering for MiMo ASR responses

## 2. Fast Full-Audio Extraction & Chunked Transcription Pipeline

- [x] 2.1 Enhance `extractAudioFast` to support online video URLs via `yt-dlp` audio-only stream extraction (`-f ba/b -x --audio-format mp3`)
- [x] 2.2 Implement audio slice chunking and concurrent worker pool (concurrency: 5) for MiMo full-audio transcription with exact timestamp tracking
- [x] 2.3 Assemble parsed chunks into full `.srt` subtitle format, auto-save to private storage, and mount via `ctrl.mountSubtitleFile()`

## 3. UI, Timeline Scrubbing & Verification

- [x] 3.1 Update `AiSubtitlesDialog` to prioritize and default to full fast subtitle generation over isolated interval slices
- [x] 3.2 Verify timeline scrubbing across the entire video duration with loaded subtitles
- [x] 3.3 Add unit tests in `test/private_player_test.dart` for MiMo request formatting, response parsing, and chunk assembly
- [x] 3.4 Run `flutter analyze` and `flutter test` to ensure zero errors or regressions
