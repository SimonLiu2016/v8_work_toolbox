## 1. Local Thumbnail Management & Capture Service

- [x] 1.1 Add `thumbnailsDir` to `PrivateStorageManager` and ensure directory initialization
- [x] 1.2 Implement `ThumbnailManager` supporting remote poster downloading and ffmpeg local video screenshot extraction
- [x] 1.3 Create reusable `MediaThumbnailWidget` with rounded styling, loading indicator, and fallback icon

## 2. Media Lists Thumbnail Visualization

- [x] 2.1 Update `OnlineDownloadPanel` task queue cards to display visual thumbnails
- [x] 2.2 Update `PrivateMediaPlayerPage` Playback History list to display visual thumbnails
- [x] 2.3 Update `PrivateMediaPlayerPage` Video Favorites list to display visual thumbnails with star badge overlay

## 3. Offline Subtitle Generation & AI Text Model Chinese Translation

- [x] 3.1 Implement `translateSubtitleSegments` in `AiSubtitleService` using `AiService.instance.chat(slot: 'text', ...)` with JSON-structured batching
- [x] 3.2 Add bilingual and pure Chinese subtitle assembly and persistence methods (`saveSubtitleFile` with `.zh.srt`)
- [x] 3.3 Add `[生成中文字幕]` action button to completed tasks in `OnlineDownloadPanel` and Chinese translation toggle in `AiSubtitlesDialog`

## 4. Verification & Testing

- [x] 4.1 Add unit tests in `test/private_player_test.dart` for thumbnail file resolution, frame capture args, and translation batch formatting
- [x] 4.2 Run `flutter analyze` and `flutter test` to ensure zero errors or regressions
