## Context

During audio playback in `DocAudioReaderPage`:
1. `_onControllerUpdate` was triggered by `AudioReaderController`'s `onPositionChanged` every 200ms. In every update, it invoked `_scrollToActiveChunk()` which called `_scrollController.animateTo(..., duration: 300ms)`. Since 300ms > 200ms, the viewport was permanently locked in animation, preventing manual scrolling.
2. In `OpenAiTtsEngine`, when requests to international endpoints (e.g. Singapore gateway `token-plan-sgp.xiaomimimo.com`) suffer connection reset (`HandshakeException: Connection terminated during handshake`), the engine immediately rethrew without retrying. Background prefetch failed silently, and playback transition threw an error until user clicked Play again.
3. Documents containing table-of-contents dotted lines (`......... 1`) produce unnatural speech.

## Goals / Non-Goals

**Goals:**
- Decouple scroll auto-centering from 200ms audio player position ticks so users can freely scroll.
- Add network-level exception recovery (`HandshakeException`, `SocketException`, `ClientException`) to `OpenAiTtsEngine` with socket recreation and automatic retry.
- Sanitize long dotted sequences in `ParagraphChunker` to improve speech synthesis quality.

**Non-Goals:**
- Completely rewriting table-of-contents detection or PDF structure extraction.

## Decisions

### Decision 1: Chunk-Index Transition Guard on Auto-Scroll
- **Choice**: Track `int? _lastScrolledChunkIndex` in `_DocAudioReaderPageState`. Only invoke `_scrollToActiveChunk()` when `_controller.currentChunkIndex != _lastScrolledChunkIndex`.
- **Rationale**: Audio position ticks (which occur 5 times per second) should only update the slider and timer, never the scroll position.

### Decision 2: Network Exception Retry & Socket Recreation in OpenAiTtsEngine
- **Choice**: In `OpenAiTtsEngine`, wrap HTTP calls in a catch block that intercepts `HandshakeException`, `SocketException`, `http.ClientException`, and `TimeoutException`. Upon error, if `retryCount < maxRetries`:
  1. Close the current `http.Client` instance to discard corrupted socket pools.
  2. Instantiate a fresh `http.Client`.
  3. Wait 1.5 seconds.
  4. Continue retry loop.
- **Rationale**: Overseas TLS handshakes periodically reset. Creating a new connection pool allows the next attempt to succeed seamlessly without user intervention.

### Decision 3: Sanitize Dotted Sequences in ParagraphChunker
- **Choice**: In `ParagraphChunker.dewrapText`, replace `\.{3,}` and `…{2,}` and `_{3,}` with a space or single punctuation mark.
- **Rationale**: Prevents TTS engines from speaking out dozens of "dian" / "dot" words in table-of-contents pages.
