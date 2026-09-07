## Why

The current AI subtitle generation in the private player fails when using Xiaomi MiMo's `mimo-v2.5-asr` model because the service hardcodes the OpenAI Whisper `/v1/audio/transcriptions` multipart protocol instead of MiMo's official `/v1/chat/completions` (JSON + Base64 audio + `asr_options`) protocol. As a result, all STT requests fail, leaving the player with no subtitles so that moving the playback position via mouse scrubbing displays nothing. Furthermore, the fast subtitle generation pipeline requires robust full-audio extraction for both local files and online URLs, transcribing full audio into a complete `.srt` file that persists across playback seeking.

## What Changes

- **Xiaomi MiMo ASR Protocol Support**: Implement support for MiMo's `/v1/chat/completions` endpoint with Base64 audio encoding and `asr_options` (`language: "auto"`).
- **Adaptive STT Protocol Dispatcher**: Automatically dispatch STT requests to either Xiaomi MiMo Chat Completions or standard OpenAI Whisper `/audio/transcriptions` based on provider configuration and model name.
- **Concurrent Chunk Transcription for MiMo**: For MiMo ASR (which transcribes audio segments into text), split extracted audio into short timestamped chunks (e.g. 10~15s) and transcribe them via a concurrent worker pool, assembling an accurate full-video `.srt` file.
- **Fast Full-Audio Extraction Pipeline**: Support fastest full-audio extraction:
  - For local media: fast 16kHz mono 32kbps MP3 extraction (<2s).
  - For online media (Bilibili, YouTube, web URLs): `yt-dlp` audio-only stream extraction (`-f ba/b -x --audio-format mp3`) without downloading video streams.
- **Automatic Full Subtitle Mounting**: Once generated, full `.srt` files are saved to private storage and mounted to the player, ensuring mouse scrubbing anywhere along the timeline maintains synchronized subtitles.

## Capabilities

### Modified Capabilities
- `ai-subtitles`: Add Xiaomi MiMo ASR protocol alongside OpenAI Whisper, concurrent slice transcription for non-timestamped ASR models, and full audio extraction for online and local video sources.
- `private-media-player`: Guarantee that generated or mounted subtitles cover the entire timeline so seeking via mouse scrub retains active subtitle synchronization.

## Impact

- `lib/tools/private_player/services/ai_subtitle_service.dart`: Core STT protocol dispatching, MiMo JSON/Base64 client, audio chunking and `.srt` assembly.
- `lib/tools/private_player/services/private_player_controller.dart`: Timeline subtitle lookup consistency during seek.
- `lib/tools/private_player/ui/ai_subtitles_dialog.dart`: Default to full fast generation instead of misleading 10-minute intervals.
- Unit tests in `test/private_player_test.dart`: MiMo request payload builder, response parsing, and subtitle chunk assembly.
