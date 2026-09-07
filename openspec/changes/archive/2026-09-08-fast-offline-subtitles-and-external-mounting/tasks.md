## 1. Subtitle Default State & External File Mounting

- [x] 1.1 Set `showSubtitles = false` by default in `PrivatePlayerController`
- [x] 1.2 Implement `AiSubtitleService.parseSrtOrVtt` parser for SRT and WebVTT files
- [x] 1.3 Implement `PrivatePlayerController.mountSubtitleFile` and auto-load saved subtitles in `open()`

## 2. Multi-Tier Fast Generation Engine

- [x] 2.1 Implement Tier 1 `yt-dlp` online auto/official subtitle extraction
- [x] 2.2 Implement Tier 2 `ffmpeg` container-embedded soft subtitle extraction
- [x] 2.3 Implement Tier 3 optimized single-pass 32kbps mono audio transcription
- [x] 2.4 Combine into `AiSubtitleService.fastGenerateSubtitles` with status callbacks

## 3. UI Controls & Verification

- [x] 3.1 Add Mount Subtitles button (`[挂载字幕]`) in `PrivatePlayerView`
- [x] 3.2 Add Fast Subtitles button (`[离线生成字幕]`) in `PrivatePlayerView`
- [x] 3.3 Add unit tests for SRT/VTT parsing, subtitle mounting, and multi-tier pipeline in `test/private_player_test.dart`
- [x] 3.4 Run `flutter test` and compile release build to verify
