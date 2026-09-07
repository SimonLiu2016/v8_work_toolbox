## Context

Currently, `ParagraphChunker.chunkText` splits raw document text on any newline (`\r?\n`), treating visual soft wraps in PDFs and documents as separate paragraphs. For a standard 42-page PDF, this generates 1,370 micro-chunks (20~40 characters each), cutting sentences in half and causing `ensureAhead` to fire bursts of simultaneous API requests that immediately trigger HTTP 429 rate limits on Xiaomi MiMo and other commercial providers.

## Goals / Non-Goals

**Goals:**
- Eliminate sentence fragmentation by welding soft line wraps (connecting CJK characters seamlessly and Latin words with single spaces).
- Aggregate short sentences into coherent 300~600 character speech thought-groups, strictly breaking on terminal punctuation (`。！？；` or `. ! ? ;`).
- Reduce total chunk count for long documents by 90%+ (e.g. from 1,370 down to ~70 chunks for the Alibaba manual).
- Guard commercial TTS with sequential prefetching (`lookahead: 1`, mutex lock) and automatic 429 exponential backoff retry (up to 3 retries).
- Replace failing `swift -e` PDF extraction with native macOS Quartz text extraction.
- Provide a direct "View AI Logs" action button in `DocAudioReaderPage`'s AppBar.

**Non-Goals:**
- Changing audio cache storage format or path structure (`~/.v8worktoolbox/audio_cache`).
- Restricting or modifying Edge-TTS concurrent synthesis behavior (Edge-TTS handles concurrent prefetching fine without rate limits).

## Decisions

### Decision 1: Two-Phase Normalization and Semantic Chunking
Instead of splitting text directly on raw newlines:
1. **Phase 1 (De-wrapping & Block Normalization)**:
   - Split blocks only on double newlines (`\n\s*\n+`) or markdown headers/list markers (`1. `, `• `, `【`).
   - Intra-block newlines: merge CJK-to-CJK characters without spaces (`'经验总\n结'` -> `'经验总结'`), and Latin words with a space (`'Java\nGuide'` -> `'Java Guide'`).
2. **Phase 2 (Thought-Group Aggregation)**:
   - Target chunk length: `targetMin = 250`, `targetMax = 600`.
   - Accumulate sentences up to `targetMax`.
   - If a single sentence exceeds `targetMax`, split only on secondary punctuation marks (`，, ` or `、`) as a last resort.

*Alternatives Considered*:
- *Splitting purely by character count (e.g. every 500 chars)*: Rejected because cutting through sentences produces jarring, unnatural speech.
- *Keeping raw paragraph breaks*: Rejected because extracted PDFs insert hard line breaks every 35-40 characters.

### Decision 2: Sequential Prefetching & 429 Retry in Commercial TTS
- In `TtsSynthesisCoordinator.ensureAhead`:
  - If `mode == TtsMode.customAi`, set `lookahead = 1` and wrap in an asynchronous execution lock (`Completer` / mutex) to ensure the engine only processes one remote TTS synthesis task at a time.
- In `OpenAiTtsEngine.synthesize`:
  - When a response returns HTTP 429:
    - Log an `AiLogger.logWarning` entry.
    - Sleep with exponential backoff: `1500ms * (retryIndex + 1)`.
    - Retry up to 3 times before rethrowing the exception.

*Alternatives Considered*:
- *Increasing MiMo API tier*: Rejected because app architecture must be resilient to any tier or concurrency quota.

### Decision 3: Quartz PDF Layer Extraction
- In `DocumentParser._parsePdf`:
  - Invoke native macOS Quartz PDF via system Python (`from Quartz import PDFDocument`) or compiled Swift helper.
  - Fallback cleanly if unreadable, reporting meaningful errors.

### Decision 4: Real-time AI Log Action in Reader AppBar
- Add an `IconButton` with `Icons.receipt_long_rounded` and tooltip "AI 调用日志" in `DocAudioReaderPage` AppBar.
- Triggers `AiLogDialog.show(context)` directly, giving instant visibility into every request, response, latency, and error trace.

## Risks / Trade-offs

- [Risk] Aggregated chunks (300~600 chars) take slightly longer to synthesize on the first chunk (~1.5s vs 0.3s) → Mitigation: 1.5s is well within comfortable interactive delay, and subsequent chunks are completely seamless because 500 characters provide over 60 seconds of playback time per chunk.
- [Risk] Complex PDF multi-column layouts might merge across columns → Mitigation: Standard PDFKit/Quartz `doc.string` handles standard reading order; structural headings and bullet points retain line boundaries.

## Migration Plan

1. Update `ParagraphChunker` logic and verify with existing unit tests.
2. Update `DocumentParser._parsePdf` to use Quartz.
3. Update `TtsSynthesisCoordinator` prefetch concurrency and `OpenAiTtsEngine` 429 retry.
4. Add AI log icon to `DocAudioReaderPage`.
5. Verify via unit tests, build, and deploy.
