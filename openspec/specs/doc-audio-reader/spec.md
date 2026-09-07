# doc-audio-reader Specification

## Purpose
Provides a multi-format document and web article audio reading assistant with intelligent chunking, tri-mode TTS synthesis, synchronized dual-way audio-text playback, and offline MP3 export.
## Requirements
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

### Requirement: Web article URL ingestion
The system SHALL support extracting readable body content from public web article URLs.

#### Scenario: User pastes web article URL
- **WHEN** user enters an HTTP/HTTPS article URL and confirms
- **THEN** system fetches HTML, strips navigation, headers, footers and advertisements, and extracts main article text into paragraphs

#### Scenario: Web article fetch fails or times out
- **WHEN** network request fails or returns non-200 status code
- **THEN** system displays error message with retry option

### Requirement: Tri-mode Text-to-Speech synthesis engine
The system SHALL provide a tri-mode TTS engine supporting Edge-TTS, OpenAI-compatible commercial TTS APIs, and macOS native speech synthesis, with automatic protocol adaptation for legacy speech and chat audio models.

#### Scenario: Default Edge-TTS free neural voice synthesis
- **WHEN** Edge-TTS mode is selected and playback starts
- **THEN** system synthesizes paragraph chunks using Microsoft neural voices (e.g., Xiaoxiao, Yunxi) without requiring an API key

#### Scenario: OpenAI-compatible custom TTS synthesis
- **WHEN** Custom AI TTS mode is selected and user configures endpoint and model
- **THEN** system adapts between /v1/audio/speech (for standard audio speech models) and /v1/chat/completions (for chat audio models), streaming or decoding audio chunks into memory/cache

#### Scenario: macOS offline native speech fallback
- **WHEN** macOS native mode is selected or network is unavailable
- **THEN** system synthesizes speech locally via native macOS speech synthesizer

#### Scenario: Default resolution via system global AI configuration
- **WHEN** Commercial AI TTS mode is selected and user chooses to use system AI configuration
- **THEN** system automatically resolves the TTS capability slot, provider endpoint, model name, and secure Keychain credentials from the global AI configuration store without requiring manual entry

#### Scenario: Custom voice ID specification for third-party providers
- **WHEN** user inputs or selects a custom voice ID for an OpenAI-compatible speech provider
- **THEN** system passes the voice identifier in the synthesis request body to the target provider, safely falling back to provider defaults if incompatible

### Requirement: Low-latency streaming chunk queue and cache
The system SHALL segment document text into sentence/paragraph chunks and schedule pre-synthesis of subsequent chunks in a strictly serialized, non-colliding order to avoid concurrent request spikes against external providers, cleaning repetitive filler dots from table-of-contents entries.

#### Scenario: Soft-break de-wrapping and sentence boundary preservation
- **WHEN** a document with visual hard wraps is loaded
- **THEN** system seamlessly merges intra-sentence line wraps without inserting spaces between CJK characters, cleans long repetitive dot filler lines (`...`), aggregates short sentences into coherent 300~600 character speech units, and strictly constrains chunk boundaries to terminal punctuation (`。！？；` or `. ! ? ;`)

#### Scenario: Playback initiates on first paragraph
- **WHEN** user clicks play on a new document
- **THEN** system immediately synthesizes the first chunk with highest priority, begins audio playback as soon as the first chunk is ready, and schedules subsequent preloading strictly after playback commences without issuing eager prefetch during initial document loading

#### Scenario: Preloading subsequent chunk
- **WHEN** audio playback of chunk `i` begins
- **THEN** system serializes a background prefetch task specifically for chunk `i + 1` without colliding with the actively playing chunk or flooding provider rate limits

#### Scenario: Cache hit on replay
- **WHEN** user replays or jumps back to a previously played paragraph
- **THEN** system plays from local audio cache instantly without re-synthesizing

### Requirement: Synchronized dual-way interactive audio player
The system SHALL provide a built-in player that synchronizes audio playback with text highlighting and scrolling without preventing user manual scrolling.

#### Scenario: Paragraph karaoke spotlight highlighting
- **WHEN** an audio chunk index transitions to a new paragraph
- **THEN** the corresponding paragraph in the text view is highlighted with spotlight styling and smoothly auto-scrolled into center view, while position ticks within the active chunk do not re-trigger auto-scroll animations so that user manual scrolling is preserved

#### Scenario: Click paragraph to jump and read
- **WHEN** user clicks any paragraph in the text viewer
- **THEN** player immediately stops current chunk, jumps to the clicked paragraph, and begins playback from that point

#### Scenario: Playback controls operation
- **WHEN** user interacts with play/pause, seek slider, or speed dropdown (0.5x to 2.5x)
- **THEN** player adjusts playback state, position, and rate in real-time

### Requirement: Offline MP3 audio file export
The system SHALL allow users to export the complete speech synthesis of a document as an MP3 audio file.

#### Scenario: User exports full document audio
- **WHEN** user clicks "Export as MP3" and specifies destination folder
- **THEN** system batches and merges all chunk audio files into a single MP3 file and displays completion notification

### Requirement: OpenAI Chat Audio Completions and Xiaomi MiMo adaptation
The system SHALL dynamically detect Chat Audio Completions models (such as Xiaomi MiMo `mimo-v2.5-tts` or OpenAI chat audio models), routing synthesis requests to `/v1/chat/completions` with assistant messages and audio configurations, and decoding Base64 audio payloads.

#### Scenario: Xiaomi MiMo TTS model synthesis
- **WHEN** user selects a Xiaomi MiMo TTS model or provider via system AI config or manual settings
- **THEN** system routes the request to POST /v1/chat/completions with role assistant content and audio format configuration, and decodes the Base64 audio data from the response

#### Scenario: Incompatible voice fallback protection
- **WHEN** a synthesis request targets Xiaomi MiMo but the active voice is not in MiMo's supported voice list
- **THEN** system automatically substitutes `mimo_default` as the synthesis voice to prevent HTTP 400 parameter errors

### Requirement: Audio format sniffing and cache persistence
The system SHALL inspect audio byte headers to persist chunk audio files with correct format extensions (.wav or .mp3) to ensure macOS audio player compatibility.

#### Scenario: WAV audio persistence
- **WHEN** synthesized audio bytes contain RIFF/WAVE header
- **THEN** system caches the chunk audio file with .wav extension and plays it correctly in the audio player

### Requirement: Synthesis failure notifications
The system SHALL present observable user notifications when TTS chunk synthesis fails.

#### Scenario: Synthesis error toast
- **WHEN** a chunk fails to synthesize due to network or provider error
- **THEN** system halts buffering and displays a visible error notification containing the failure cause

### Requirement: Observable TTS synthesis telemetry and diagnostic logging
The system SHALL record structured telemetry entries into AiLogger for every TTS synthesis request, successful response, rate-limit retry, and synthesis error, mirrored asynchronously to a persistent local log file in addition to the in-app AI Log Viewer.

#### Scenario: Commercial AI TTS request logging
- **WHEN** user initiates playback using a commercial or system AI TTS provider
- **THEN** system logs a structured request entry in AiLogger with provider name, protocol, model, endpoint, voice, and text summary

#### Scenario: Synthesis response and duration logging
- **WHEN** a TTS synthesis request completes successfully
- **THEN** system logs an AiLogger response entry with status code, elapsed milliseconds, and byte size

#### Scenario: Synthesis error logging
- **WHEN** a TTS synthesis request encounters an HTTP or network failure
- **THEN** system logs an AiLogger error entry containing the exact failure reason and status code

#### Scenario: File system log mirroring
- **WHEN** an entry is logged to AiLogger
- **THEN** system asynchronously appends the formatted log entry to the application's local log file on disk so logs are retrievable across application restarts

### Requirement: System TTS slot model priority resolution
The system SHALL resolve the synthesis model name from the active TTS slot bindings for the matched provider with highest priority when system AI configuration is selected, falling back to provider model inspection and provider-specific model defaults.

#### Scenario: Slot candidate model extraction with explicit systemProviderId
- **WHEN** user selects a specific systemProviderId and useSystemAiConfig is true
- **THEN** system queries the TTS slot bindings for that provider and resolves its configured model (e.g., mimo-v2.5-tts) instead of falling back to default tts-1

#### Scenario: MiMo model fallback protection
- **WHEN** the resolved provider is Xiaomi MiMo and the resolved model is empty or default tts-1
- **THEN** system automatically substitutes mimo-v2.5-tts as the model name

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

### Requirement: TTS configuration persistence and smart mode defaulting
The system SHALL persist the user's TTS configuration (synthesis mode, selected provider, model, voice ID, and speech rate) to local application storage, and automatically resolve a functional default mode on startup.

#### Scenario: Persisting user TTS configuration changes
- **WHEN** user changes the TTS synthesis mode, voice, speed, or provider settings
- **THEN** system immediately saves the configuration to local application storage

#### Scenario: Restoring configuration across application restarts
- **WHEN** user opens the audio reader after an application restart
- **THEN** system loads and applies the previously saved TTS configuration instead of reverting to default Edge-TTS

#### Scenario: Smart initial default when AI provider configured
- **WHEN** the audio reader opens without prior saved configuration and the system AI configuration contains an active TTS model provider
- **THEN** system automatically defaults the synthesis mode to Custom AI TTS using the configured provider and model rather than defaulting to Edge-TTS

### Requirement: Resilient commercial AI rate limit backoff and extended synthesis timeout
The system SHALL protect commercial AI TTS synthesis against transient HTTP 429 rate limits, network connection terminations, and TLS handshake failures through automatic retry and stepped backoff delays with observable progress updates, supporting synthesis durations up to 90 seconds for long paragraphs.

#### Scenario: HTTP 429 rate limit backoff recovery
- **WHEN** a commercial AI TTS provider responds with HTTP 429 (Too Many Requests)
- **THEN** system waits for stepped backoff intervals (4s, 10s, 20s), notifies the user interface of the waiting state, and retries the request before declaring synthesis failure

#### Scenario: Network exception and TLS handshake failure recovery
- **WHEN** a commercial AI TTS request fails due to transient network interruption, socket disconnect, or TLS handshake termination (`HandshakeException`, `SocketException`, `ClientException`)
- **THEN** system automatically refreshes the underlying network connection, logs a warning, waits 1.5 to 2 seconds, and retries the synthesis request up to 3 times before reporting an error

#### Scenario: Extended synthesis timeout for dense paragraphs
- **WHEN** a chunk containing up to 600 characters is sent to a commercial AI TTS provider
- **THEN** system permits up to 90 seconds for synthesis completion before raising a timeout exception

