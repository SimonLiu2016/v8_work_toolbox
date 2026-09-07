# Design Document: Document & Web AI Audio Reader

## Context

See `proposal.md` for motivation and high-level requirements.
V8WorkToolbox is a Flutter macOS desktop application with an established AI Configuration subsystem (`lib/services/ai_service.dart`, `lib/services/ai_config_store.dart`) and tool registry (`lib/tools/registry.dart`).
The project already includes dependencies for `archive` (zip operations), `xml` (XML traversal), and `http` (HTTP requests).
This design adds a dedicated tool page (`lib/tools/reader/`) that ingests diverse document types, manages TTS synthesis with sliding window caching, and renders an interactive reader with audio playback controls.

## Goals / Non-Goals

**Goals:**
- Provide universal text extraction across TXT, MD, PDF, Word (.docx), EPUB (.epub), and Web URLs.
- Provide a tri-mode TTS engine (Edge-TTS neural voices, OpenAI-compatible custom TTS endpoint, and macOS native speech synthesizer).
- Achieve sub-second time-to-first-sound (TTFB) using proactive chunking and sliding-window synthesis queue.
- Deliver a responsive reader UI with synchronized paragraph spotlight highlighting, auto-scroll, and click-to-jump playback.
- Allow exporting synthesized full audio into an MP3 file.

**Non-Goals:**
- Optical Character Recognition (OCR) for scanned PDFs or images (out of scope for initial phase; user is notified if PDF has no extractable text).
- Audio transcription (speech-to-text / ASR) into text (this tool focuses solely on text-to-speech reading).

## Decisions

### 1. Document Extraction Strategy
- **PDF**: Leverage macOS built-in Cocoa `PDFKit` via Swift/CLI invocation (`swift -e "import PDFKit; ..."`) or fallback to pure Dart parser. This gives 100% fidelity on macOS without bundling heavy native binaries.
- **Word (.docx)**: Use macOS built-in `textutil -convert txt <path> -stdout` for rich paragraph/formatting conversion, with pure Dart `archive` + `xml` (`word/document.xml`) as an embedded fallback.
- **EPUB (.epub)**: Extract container XML and XHTML content using existing `archive` and `xml` packages, parsing reading spine and table of contents.
- **TXT / Markdown**: Read via UTF-8 Dart File streams, stripping Markdown formatting noise (URLs, badge images) while keeping headings and list structure.
- **Web URLs**: Fetch via `http.get`, clean HTML using DOM parsing / regex, extracting title and readability body.

*Alternatives considered*:
- Bundling large Poppler or Pandoc CLI binaries: Rejected due to 50MB+ bundle bloat and architecture incompatibility.

### 2. Tri-Mode TTS Architecture
- **Engine Interface**: Abstract `TtsEngine` base class with `synthesizeChunk(String text, TtsOptions options) -> Future<Uint8List>`.
- **Edge-TTS Adapter**: Direct HTTP/WebSocket streaming interface to Edge neural voice endpoint, fetching high-quality Chinese/English audio without requiring API keys.
- **OpenAI-compatible Adapter**: Calls configured endpoint (e.g. `/v1/audio/speech`) with `Authorization: Bearer <key>`, `model`, `voice`, and `input`.
- **macOS Native Adapter**: Invokes system `say -o output.aiff` / `AVSpeechSynthesizer` for zero-network environments.

*Alternatives considered*:
- Only supporting OpenAI API: Rejected because users without API keys should still enjoy high-quality reading out of the box (via Edge-TTS).

### 3. Audio Playback Subsystem
- Adopt `audioplayers: ^6.0.0` in `pubspec.yaml`. It provides first-class macOS desktop support, streaming byte sources, position change streams, playback rate changes (0.5x to 2.5x), and completion listeners.
- Cache synthesized chunk audio files in `~/.v8worktoolbox/audio_cache/<doc_hash>/` named `chunk_001.mp3`.

### 4. Dual-way Text-Audio Synchronization
- Text is tokenized into clean `ReadingChunk` objects (natural paragraphs or sentences of 80~250 characters).
- Each chunk has an index, text content, start/end byte offsets, and synthesis status (`pending`, `synthesizing`, `cached`, `error`).
- When a chunk completes, the controller auto-advances to the next chunk without audio stuttering (queue pre-synthesis keeps 2 chunks ahead).
- The text list view uses an `ItemScrollController` to smoothly scroll the active chunk into viewport center.

### 5. MP3 Export Pipeline
- Concatenates the cached MP3 binary chunks in order into a target file specified by user file picker.
- If audio chunks are raw MP3 frames, binary concatenation is valid and produce seamless MP3 streams.

## Risks / Trade-offs

- [Network flakiness during live TTS streaming] → Mitigation: Queue-ahead synthesis synthesizes 2-3 paragraphs in advance; if network fails, UI shows retry icon and allows falling back to macOS offline voice.
- [Complex web pages with heavy JavaScript] → Mitigation: Standard readability extraction strips noise; if body text is sparse, alert user that page requires manual copy-paste.
- [Large PDF files (e.g., 500+ pages)] → Mitigation: Paginated / chapter-based lazy parsing so UI remains fluid.

## Migration Plan

- Non-breaking addition: Creates new routes, models, and services under `lib/tools/reader/`.
- Adds `audioplayers` to `pubspec.yaml`.
- Registers new entry in `lib/tools/registry.dart`.
