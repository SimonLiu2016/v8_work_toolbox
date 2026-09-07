## Why

Currently, video download tasks, playback history, and favorites rely on remote HTTP poster links or fallback icons, leaving items without offline visual previews when disconnected or when remote images expire. Furthermore, foreign-language or local downloaded videos require an automated pipeline to extract audio, perform AI speech recognition, and invoke an AI text model to translate the full subtitle file into Chinese.

## What Changes

- **Private Thumbnail Storage & Frame Capture**:
  - Add a dedicated `thumbnails/` directory under private storage.
  - Automatically download remote poster images to private storage for online media.
  - Extract high-quality frame screenshots (`ffmpeg -ss 00:00:02 -vframes 1`) for local downloaded media.
- **Visual Thumbnail Display in Lists**:
  - Update Download Tasks, Playback History, and Video Favorites lists to display 64x44 rounded cover thumbnails with graceful fallback.
- **Offline Subtitle Generation & AI Chinese Translation Pipeline**:
  - For local downloaded videos, extract temporary audio (16kHz mono MP3).
  - Transcribe audio into timestamped subtitle segments via the configured STT provider (MiMo ASR or Whisper).
  - Call the global `text` LLM slot (`AiService.instance.chat(slot: 'text', ...)`) in structured batches to translate subtitles into Chinese (supporting pure Chinese and bilingual formats).
  - Automatically persist the translated `.srt` file to private storage and mount it to the player.

## Capabilities

### Modified Capabilities
- `private-media-player`: Add local thumbnail caching, video frame capture, and visual thumbnail rendering across playback history, favorites, and download tasks.
- `ai-subtitles`: Add offline local video audio extraction, ASR transcription, and LLM text model translation into Chinese subtitles.

## Impact

- `lib/tools/private_player/services/private_storage_manager.dart`: Add `thumbnailsDir`.
- `lib/tools/private_player/services/thumbnail_manager.dart` (new): Dedicated service for thumbnail download and local ffmpeg frame capture.
- `lib/tools/private_player/services/ai_subtitle_service.dart`: Subtitle translation pipeline using `slot: 'text'`.
- `lib/tools/private_player/ui/private_media_player_page.dart`: Display thumbnails in History and Favorites lists.
- `lib/tools/private_player/ui/online_download_panel.dart`: Display thumbnails in Task Queue list and add `[生成中文字幕]` action for completed tasks.
- `lib/tools/private_player/ui/ai_subtitles_dialog.dart`: Add option to translate subtitles to Chinese.
- `test/private_player_test.dart`: Unit tests for thumbnail caching and subtitle translation prompt formatting.
