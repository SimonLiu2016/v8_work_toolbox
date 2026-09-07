# Proposal: Fix Document Reader Scroll Locking and Network Handshake Resilience

## Why

During playback testing of the Document Audio Reader (`doc-audio-reader`), two critical functional defects were identified:
1. The document text view in the main window is completely unscrollable during playback. Every 200ms audio position tick triggers `_scrollToActiveChunk()`, continuously firing a 300ms `animateTo` animation that forcefully overrides and cancels manual user scrolling.
2. Background prefetch and playback of subsequent paragraphs frequently encounter `HandshakeException: Connection terminated during handshake` against remote international endpoints (such as Xiaomi MiMo on Singapore gateway `token-plan-sgp.xiaomimimo.com`). Because `OpenAiTtsEngine` only retries HTTP 429 status codes and immediately rethrows network exceptions, background prefetch silently aborts, leaving the next chunk uncached and causing synthesis to fail upon transition unless manually restarted by the user.

## What Changes

- **Decoupled Spotlight Scroll Synchronization**: Track the active chunk index and trigger `_scrollToActiveChunk()` only when `currentChunkIndex` actually changes (not on 200ms playback progress ticks). Allow smooth manual scrolling by user during playback.
- **Network Layer Exception Retry & TLS Recovery**: Expand `OpenAiTtsEngine` retry loop to intercept network exceptions (`HandshakeException`, `SocketException`, `ClientException`, `TimeoutException`), cleanly close dead TCP/TLS sockets, wait 1.5s to 2s, and automatically retry up to 3 times.
- **Dotted Line TOC Cleanup in Chunker**: Clean continuous dot patterns (`\.{3,}`) and page trailing lines in `ParagraphChunker` so table of contents entries are not spoken aloud as repetitive dot sounds.

## Capabilities

### Modified Capabilities
- `doc-audio-reader`: Update scroll synchronization requirements to only trigger on chunk index transitions, add network-level transient fault tolerance for commercial TTS endpoints, and sanitize long dotted filler lines during text normalization.

## Impact

- `lib/tools/reader/ui/doc_audio_reader_page.dart`: Refactor `_onControllerUpdate` and auto-scroll logic.
- `lib/tools/reader/services/tts_engine.dart`: Add network exception handling and socket retry to `OpenAiTtsEngine`.
- `lib/tools/reader/services/document_parser.dart`: Add dot line sanitization to `ParagraphChunker`.
- `test/doc_audio_reader_test.dart`: Add verification tests.
