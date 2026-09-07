## MODIFIED Requirements

### Requirement: Multi-format document text extraction
The system SHALL extract clean readable plain text and structural paragraphs from local files (.pdf, .docx, .txt, .md, .epub), utilizing native macOS Quartz/PDFKit text layer extraction for PDF documents.

#### Scenario: User imports local PDF file
- **WHEN** user selects or drags a valid .pdf file into the audio reader
- **THEN** system extracts all text layers using native Quartz/PDFKit runtime, preserves logical paragraphs, displays estimated word count and reading duration, and populates the reading viewer without process execution failures

#### Scenario: User imports local Word document (.docx)
- **WHEN** user selects a valid .docx file
- **THEN** system parses text from document XML or textutil and populates the reading viewer with structured paragraphs

#### Scenario: User imports local EPUB e-book (.epub)
- **WHEN** user selects a valid .epub file
- **THEN** system parses chapter manifests and XHTML text streams, presenting chapter navigation and body text

#### Scenario: Unsupported or corrupted file imported
- **WHEN** user drops an unsupported format or corrupted file
- **THEN** system displays a user-friendly error notification without crashing

### Requirement: Low-latency streaming chunk queue and cache
The system SHALL normalize soft line wraps, segment document text into semantic thought-group chunks (targeting 300 ~ 600 characters) strictly aligned to natural sentence terminators, and pre-synthesize upcoming chunks sequentially or concurrently according to the engine type.

#### Scenario: Soft-break de-wrapping and sentence boundary preservation
- **WHEN** a document with visual hard wraps is loaded
- **THEN** system seamlessly merges intra-sentence line wraps without inserting spaces between CJK characters, aggregates short sentences into coherent 300~600 character speech units, and strictly constrains chunk boundaries to terminal punctuation (`。！？；` or `. ! ? ;`)

#### Scenario: Playback initiates on first paragraph
- **WHEN** user clicks play on a new document
- **THEN** system immediately synthesizes the first chunk to begin playback within 1 second, while preloading the next chunk in background

#### Scenario: Cache hit on replay
- **WHEN** user replays or jumps back to a previously played paragraph
- **THEN** system plays from local audio cache instantly without re-synthesizing

## ADDED Requirements

### Requirement: Commercial AI TTS rate limiting and automatic backoff retry
The system SHALL guard commercial AI TTS synthesis against concurrency overflow and HTTP 429 rate limits, enforcing sequential prefetch scheduling (`lookahead: 1`) and automatic exponential backoff retry.

#### Scenario: HTTP 429 rate limit automatic backoff retry
- **WHEN** a commercial AI TTS provider returns HTTP 429 Too Many Requests
- **THEN** system logs a warning in AiLogger, waits with exponential backoff (1.5s ~ 2.0s), and automatically retries the request up to 3 times before reporting an error to the user

#### Scenario: Sequential prefetching for commercial TTS
- **WHEN** a document is playing in commercial AI TTS mode
- **THEN** system enforces a single-task mutex lock for background prefetching, ensuring subsequent chunks are requested strictly one at a time after the prior chunk completes

### Requirement: In-app AI real-time call log viewer in reader
The system SHALL provide an accessible action in the reader navigation bar to directly open the AI Log Viewer dialog for inspecting real-time TTS request payloads, responses, and error traces.

#### Scenario: User opens AI Log Viewer from reader
- **WHEN** user clicks the AI Log icon button in the reader AppBar
- **THEN** system opens the AiLogDialog modal displaying recent TTS synthesis requests, status codes, latency, and error details with one-click copy support
