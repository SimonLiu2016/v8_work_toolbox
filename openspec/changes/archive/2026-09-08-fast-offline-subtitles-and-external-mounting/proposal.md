## Why

Currently, subtitle transcription relies on sequential chunking that results in slow generation times. Additionally, subtitles are on by default (which may clutter video playback before subtitles are desired), and users cannot mount existing external subtitle files (`.srt`, `.vtt`) that they already possess.

## What Changes

1. **Default Subtitle State to OFF**: Set subtitle toggle `showSubtitles` default to `false` in `PrivatePlayerController`. Subtitles only render when explicitly toggled on by the user or when a subtitle file is mounted/generated.
2. **Fast Offline Subtitle Generation**: Add a dedicated "离线生成字幕" (Generate Subtitles Fast) button on the player controls. It uses a tiered multi-strategy engine:
   - Tier 1: Instant native subtitle extraction for online streams (B站, YouTube, etc.) via `yt-dlp --write-subs --write-auto-subs --skip-download` (1~2 seconds).
   - Tier 2: Instant embedded subtitle extraction for local MKV/MP4 files containing soft subtitle streams via `ffmpeg` (< 1 second).
   - Tier 3: Direct high-efficiency single-pass full-audio transcription (16kHz mono 32kbps lightweight audio, <15MB/hour) avoiding multi-slice serial delays.
3. **Mount External Subtitle Files**: Add a "挂载字幕" (Mount Subtitles) button to pick `.srt` or `.vtt` files from disk, parse their timestamps, activate playback overlay, and persist the subtitle path in playback history for auto-resumption.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `private-media-player`: Default subtitle visibility to off, support picking and mounting external subtitle files (.srt/.vtt), and add quick generation button.
- `ai-subtitles`: Multi-tier fast offline subtitle generation (yt-dlp online subs direct extraction, ffmpeg embedded stream extraction, single-pass full audio transcription).

## Impact

- `lib/tools/private_player/services/private_player_controller.dart`: Default `showSubtitles = false`, add `mountSubtitleFile(String path)`.
- `lib/tools/private_player/services/ai_subtitle_service.dart`: Add `fastGenerateSubtitles(String urlOrPath)` implementing the 3 tiers. Add SRT/VTT parser.
- `lib/tools/private_player/ui/private_player_view.dart`: Add "挂载字幕" and "离线生成字幕" buttons on control overlay.
- `lib/tools/private_player/services/media_history_store.dart`: Persist mounted subtitle path with the record.
