## Context

See `proposal.md` for background. Subtitles previously defaulted to ON and relied on sequential chunking that created long waits. Furthermore, existing local `.srt`/`.vtt` files could not be mounted.

## Goals / Non-Goals

**Goals:**
- Subtitle display defaults to off; users toggle or mount on demand.
- Fast multi-tier subtitle generation: 1-2s for online videos and embedded MKV streams, 10-20s for pure audio speech-to-text.
- Support selecting and mounting external `.srt` and `.vtt` files directly in the player.
- Persist mounted subtitle association in `MediaHistoryStore`.

**Non-Goals:**
- Real-time live microphone transcription.
- Complex ASS/SSA karaoke visual style rendering (text-only subtitle synchronization is targeted).

## Decisions

### Decision 1: Multi-Tier Fast Generation Strategy
Implement `AiSubtitleService.fastGenerateSubtitles`:
```
                     Input Media (URL or Local Path)
                                    │
           ┌────────────────────────┴────────────────────────┐
           ▼                                                 ▼
      [Online URL]                                     [Local File]
           │                                                 │
  yt-dlp --write-subs                               ffmpeg -map 0:s:0
  --write-auto-subs                                 extract embedded subs
           │                                                 │
     Success? ───Yes──┐                                Success? ───Yes──┐
           │No        │                                      │No        │
           ▼          ▼                                      ▼          ▼
     Fallback to Tier 3                                Fallback to Tier 3
                      │                                      │
                      └───────────────┬──────────────────────┘
                                      ▼
                        [Tier 3: Single-Pass STT]
                        ffmpeg 32kbps mono MP3 (1/2 size)
                        Single HTTP request with verbose_json
                                      │
                                      ▼
                             Mount & Save .srt
```
*Rationale*: 90% of videos on YouTube/Bilibili already have machine or creator subtitles available. Fetching them directly via `yt-dlp` takes 1-2 seconds instead of minutes of AI audio re-encoding.

### Decision 2: Universal SRT & WebVTT Robust Parser
Implement a zero-dependency Dart regex parser in `AiSubtitleService`:
- Normalizes CRLF and LF line endings.
- Matches timestamp patterns `HH:MM:SS[,.]mmm --> HH:MM:SS[,.]mmm`.
- Strips VTT header/cue tags (e.g. `WEBVTT`, `<c>`, `<v>`).
- Converts into `List<SubtitleSegment>`.

### Decision 3: Subtitle Mounting & History Association
In `PrivatePlayerController`:
- `mountSubtitleFile(String path)` reads file, invokes `parseSrtOrVtt`, updates `_subtitles`, and sets `showSubtitles = true`.
- Emits playback record with `subtitlePath: path` to `MediaHistoryStore` so reopening the video in the future automatically restores the subtitle track.

## Risks / Trade-offs

- **[Risk] Online site blocking auto-subs or requiring cookies**
  → *Mitigation*: If `yt-dlp` fails to extract subtitles, gracefully fall back to Tier 3 audio transcription without halting.
