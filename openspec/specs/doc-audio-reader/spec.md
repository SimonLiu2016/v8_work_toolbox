# doc-audio-reader Specification

## Purpose
Provides a multi-format document and web article audio reading assistant with intelligent chunking, tri-mode TTS synthesis, synchronized dual-way audio-text playback, and offline MP3 export.
## Requirements
### Requirement: Multi-format document text extraction
The system SHALL extract clean readable plain text and structural paragraphs from local files (.pdf, .docx, .txt, .md, .epub).

#### Scenario: User imports local PDF file
- **WHEN** user selects or drags a valid .pdf file into the audio reader
- **THEN** system extracts text content, preserves paragraph boundaries, displays estimated word count and reading duration, and populates the reading viewer

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
The system SHALL segment document text into sentence/paragraph chunks and pre-synthesize upcoming chunks concurrently.

#### Scenario: Playback initiates on first paragraph
- **WHEN** user clicks play on a new document
- **THEN** system immediately synthesizes the first chunk to begin playback within 1 second, while preloading subsequent chunks in background

#### Scenario: Cache hit on replay
- **WHEN** user replays or jumps back to a previously played paragraph
- **THEN** system plays from local audio cache instantly without re-synthesizing

### Requirement: Synchronized dual-way interactive audio player
The system SHALL provide a built-in player that synchronizes audio playback with text highlighting and scrolling.

#### Scenario: Paragraph karaoke spotlight highlighting
- **WHEN** an audio chunk is actively playing
- **THEN** the corresponding paragraph in the text view is highlighted with spotlight styling and smoothly auto-scrolled into center view

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
The system SHALL record structured telemetry entries into AiLogger for every TTS synthesis request, successful response, and synthesis error, enabling real-time inspection in the in-app AI Log Viewer.

#### Scenario: Commercial AI TTS request logging
- **WHEN** user initiates playback using a commercial or system AI TTS provider
- **THEN** system logs a structured request entry in AiLogger with provider name, protocol, model, endpoint, voice, and text summary

#### Scenario: Synthesis response and duration logging
- **WHEN** a TTS synthesis request completes successfully
- **THEN** system logs an AiLogger response entry with status code, elapsed milliseconds, and byte size

#### Scenario: Synthesis error logging
- **WHEN** a TTS synthesis request encounters an HTTP or network failure
- **THEN** system logs an AiLogger error entry containing the exact failure reason and status code

### Requirement: System TTS slot model priority resolution
The system SHALL resolve the synthesis model name from the active TTS slot bindings for the matched provider with highest priority when system AI configuration is selected, falling back to provider model inspection and provider-specific model defaults.

#### Scenario: Slot candidate model extraction with explicit systemProviderId
- **WHEN** user selects a specific systemProviderId and useSystemAiConfig is true
- **THEN** system queries the TTS slot bindings for that provider and resolves its configured model (e.g., mimo-v2.5-tts) instead of falling back to default tts-1

#### Scenario: MiMo model fallback protection
- **WHEN** the resolved provider is Xiaomi MiMo and the resolved model is empty or default tts-1
- **THEN** system automatically substitutes mimo-v2.5-tts as the model name

