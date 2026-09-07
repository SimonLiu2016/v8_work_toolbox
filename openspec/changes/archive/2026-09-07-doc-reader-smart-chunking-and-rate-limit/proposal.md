## Why

In the Document Audio Reader tool, the current text chunker splits on every visual line wrap (`|\r?\n`). In PDF and wrapped text documents, this fragments complete sentences across line boundaries (e.g. cutting words in half like "经验总" / "结"), destroys speech cadence and prosody, and creates hundreds of tiny chunks. When combined with unthrottled lookahead prefetching, this causes a burst of simultaneous API requests that triggers commercial AI TTS rate limits (HTTP 429 Too Many Requests). Furthermore, macOS PDF text extraction via `swift -e` fails due to dynamic symbol resolution issues, and users lack an in-tool AI log viewer to inspect synthesis errors.

## What Changes

- **Smart Soft-Break De-wrapping & Semantic Chunking**: Replace line-by-line regex splitting with an intelligent two-phase text normalization and chunking pipeline that seamlessly welds intra-sentence wraps (especially CJK text), groups short thoughts into 300~600 character speech units, and strictly constrains chunk boundaries to sentence-ending punctuation (`。！？；` and `. ! ? ;`).
- **Commercial AI Rate Limiting & 429 Exponential Backoff**: Implement sequential mutex-protected prefetching (`lookahead: 1`) for commercial TTS providers, and add automatic 429 backoff retry in `OpenAiTtsEngine` (1.5s ~ 2.0s delay, up to 3 retries).
- **macOS PDF Extraction Hardening**: Replace brittle `swift -e` JIT script execution with robust native macOS Quartz text extraction, ensuring 100% reliable text layer extraction for multi-page PDF documents.
- **In-App AI Log Viewer in Reader**: Add an AI real-time call log viewer action button in `DocAudioReaderPage`'s AppBar, allowing one-click diagnosis of request payloads, response codes, and error messages.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `doc-audio-reader`: Enhanced with intelligent sentence-preserving de-wrapping, 300~600 char thought-group chunking, sequential commercial TTS prefetch with 429 exponential backoff, robust PDFKit/Quartz text extraction, and in-app AI log viewer integration.

## Impact

- `lib/tools/reader/services/document_parser.dart`: Rewrite `ParagraphChunker` and update `_parsePdf`.
- `lib/tools/reader/services/tts_engine.dart`: Add 429 retry backoff in `OpenAiTtsEngine`.
- `lib/tools/reader/services/tts_coordinator.dart`: Add sequential concurrency guard for commercial TTS mode.
- `lib/tools/reader/ui/doc_audio_reader_page.dart`: Add AI Log viewer action button in AppBar.
- `test/doc_audio_reader_test.dart`: Add unit tests for CJK de-wrapping, sentence boundary preservation, and rate limiting.
