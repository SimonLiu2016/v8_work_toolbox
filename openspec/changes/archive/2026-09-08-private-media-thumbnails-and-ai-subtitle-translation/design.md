## Context

See proposal.md for motivation. Media items currently lack local thumbnail caching, displaying remote URLs or fallback icons in history and favorites. Local downloaded videos also need a complete offline pipeline to extract audio, perform ASR transcription, and invoke the text model slot to generate translated Chinese subtitles.

## Goals / Non-Goals

**Goals:**
- Provide a dedicated `ThumbnailManager` that saves online posters and extracts local video frame screenshots into private storage.
- Update Download Queue, Playback History, and Video Favorites lists with 64x44 rounded thumbnail previews.
- Implement an offline ASR + LLM translation pipeline translating full subtitle files into natural Chinese using `AiService.instance.chat(slot: 'text', ...)`.
- Support both bilingual and Chinese-only subtitle generation with automatic `.srt` persistence and player mounting.

**Non-Goals:**
- Real-time live audio translation during live-streaming playback (offline processing is preferred for quality and reliability).
- Custom image editing or poster replacement tools.

## Decisions

### Decision 1: ThumbnailManager for Dual-Source Thumbnail Ingestion
- **Online Videos**: When video metadata is resolved or queued, download the poster image via HTTP into `thumbnailsDir/{md5(url)}.jpg`.
- **Local Media**: Use `ffmpeg -ss 00:00:02 -i <path> -vframes 1 -q:v 2 <thumbnailsDir/{md5(path)}.jpg>`. Takes <50ms and produces high-quality video frames.
- **Data Association**: `MediaPlayRecord` and `DownloadTask` store the local file path in `thumbnailUrl`.

### Decision 2: Reusable MediaThumbnailWidget
- Encapsulate thumbnail display with rounded corners, aspect ratio preservation, loading state, and fallback placeholder icon.
- In Favorites, overlay a subtle amber star badge on the thumbnail.

### Decision 3: Batch Subtitle Translation via Global Text Slot
- Chunk subtitle segments into batches of 25 lines.
- Prompt `AiService.instance.chat(slot: 'text', ...)` with strict JSON format (`[{"id": 1, "text": "..."}]`) for precise line-to-line alignment.
- Provide options for bilingual (`$original\n$translated`) and Chinese-only subtitles.

### Decision 4: Action Integration in UI
- In Download Tasks: add a direct `[生成中文字幕]` button on completed items.
- In `AiSubtitlesDialog`: add a toggle for automatic Chinese subtitle translation.

## Risks / Trade-offs

- **[Risk] LLM translation line mismatch** → Mitigation: Strict JSON schema with ID mapping; fallback to original segment text if any line fails to parse.
- **[Risk] Large thumbnail disk usage** → Mitigation: Thumbnails are saved as compressed JPEGs (typically 10~30KB each).
