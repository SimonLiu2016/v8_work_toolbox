## 1. Smart Text De-wrapping and Semantic Chunking

- [x] 1.1 Implement CJK-aware soft-break de-wrapping and paragraph normalization in `ParagraphChunker`
- [x] 1.2 Implement thought-group chunk aggregation (target 300~600 chars) with strict sentence boundary constraints (`。！？；` / `. ! ? ;`)
- [x] 1.3 Implement robust macOS PDF text extraction in `DocumentParser._parsePdf` using native Quartz/PDFKit

## 2. Commercial AI Rate Limiting & Auto-Retry

- [x] 2.1 Add HTTP 429 exponential backoff retry in `OpenAiTtsEngine`
- [x] 2.2 Add sequential mutex prefetch scheduling (`lookahead: 1`) for commercial TTS in `TtsSynthesisCoordinator`

## 3. UI Observability & Validation

- [x] 3.1 Add AI Log Viewer action button in `DocAudioReaderPage` AppBar
- [x] 3.2 Add comprehensive unit tests for de-wrapping, chunk sizing, and 429 retry in `test/doc_audio_reader_test.dart`
- [x] 3.3 Rebuild macOS release app and deploy to `/Applications/V8WorkToolbox.app`
