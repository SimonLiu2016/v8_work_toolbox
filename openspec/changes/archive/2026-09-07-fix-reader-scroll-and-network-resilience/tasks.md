## 1. Document Reader Scroll Decoupling

- [x] 1.1 Guard `_scrollToActiveChunk` with `_lastScrolledChunkIndex` in `DocAudioReaderPage`
- [x] 1.2 Verify user can scroll freely during audio playback

## 2. Network Exception Handling & Handshake Recovery

- [x] 2.1 Wrap HTTP post in `OpenAiTtsEngine` to catch `HandshakeException`, `SocketException`, and network errors
- [x] 2.2 Recreate `http.Client` on connection termination and retry up to 3 times with 1.5s backoff
- [x] 2.3 Apply network retry across both `chat/completions` and `audio/speech` branches

## 3. Table of Contents Dotted Lines Sanitization

- [x] 3.1 In `ParagraphChunker.dewrapText`, sanitize repeated dots (`\.{3,}`) and underscores
- [x] 3.2 Verify sanitization preserves valid punctuation
## 4. Verification & Testing

- [x] 4.1 Run unit and widget tests for reader scroll guard, network retry, and chunker cleaning
- [x] 4.2 Rebuild macOS release app and verify end-to-end
