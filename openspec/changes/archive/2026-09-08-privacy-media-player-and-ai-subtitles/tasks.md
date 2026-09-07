## 1. Dependencies & Privacy Space Framework

- [x] 1.1 Add `media_kit`, `media_kit_video`, and `media_kit_libs_macos_video` to `pubspec.yaml`
- [x] 1.2 Implement `PrivacySecurityService` for 6-digit PIN hashing, Keychain storage, session unlock, and auto-lock
- [x] 1.3 Implement `PrivacyLockView` (PIN setup and unlock interface with digit keypad and validation)
- [x] 1.4 Update `ActivityBar`, `ToolCategory.privacy`, and `AppShell` to isolate privacy tools and lock screen

## 2. Media Player Engine & Core UI

- [x] 2.1 Implement `PrivatePlayerController` wrapping `media_kit` for cross-format local/online playback, rate, and volume
- [x] 2.2 Implement `PrivatePlayerView` with control overlays, scrub bar, time display, speed selector, and fullscreen
- [x] 2.3 Implement `PrivateStorageManager` managing `~/Library/Application Support/V8WorkToolbox/PrivateMedia/` and Finder reveal
- [x] 2.4 Implement Playback History and Favorites persistence with resume playback support

## 3. Online Video Parser & Downloader

- [x] 3.1 Implement `YtdlpVideoParser` with dedicated flags for Bilibili, YouTube, Pornhub, pornlulu.com, MissAV, and generic URLs
- [x] 3.2 Implement `DownloadQueueManager` for concurrent single/batch downloads with stdout progress parsing
- [x] 3.3 Implement Download & Batch Download UI with queue management and one-click "Play in Player" action

## 4. AI Subtitles Transcription & Display

- [x] 4.1 Implement `AiSubtitleService` integrating `AiConfigStore` STT slot (`/v1/audio/transcriptions` with `verbose_json`)
- [x] 4.2 Implement `ffmpeg` lightweight 16kHz mono audio extraction and chunking
- [x] 4.3 Implement dual-mode generation: on-demand playback interval (±10 min) and full-video background batch
- [x] 4.4 Implement in-player synchronized subtitle overlay with `[CC]` switch and `.srt` file export

## 5. Verification & Testing

- [x] 5.1 Add unit tests for PIN validation, subtitle SRT parsing/formatting, and queue management
- [x] 5.2 Verify end-to-end playback, parsing, downloading, and AI subtitle generation on macOS
