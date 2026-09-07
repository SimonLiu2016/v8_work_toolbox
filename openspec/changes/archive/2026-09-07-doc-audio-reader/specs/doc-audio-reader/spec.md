## Purpose

Provides a multi-format document and web article audio reading assistant with intelligent chunking, tri-mode TTS synthesis, synchronized dual-way audio-text playback, and offline MP3 export.

## ADDED Requirements

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
The system SHALL provide a tri-mode TTS engine supporting Edge-TTS, OpenAI-compatible commercial TTS APIs, and macOS native speech synthesis.

#### Scenario: Default Edge-TTS free neural voice synthesis
- **WHEN** Edge-TTS mode is selected and playback starts
- **THEN** system synthesizes paragraph chunks using Microsoft neural voices (e.g., Xiaoxiao, Yunxi) without requiring an API key

#### Scenario: OpenAI-compatible custom TTS synthesis
- **WHEN** Custom AI TTS mode is selected and user configures endpoint and model
- **THEN** system posts requests to /v1/audio/speech with chosen voice and speed, streaming audio chunks into memory/cache

#### Scenario: macOS offline native speech fallback
- **WHEN** macOS native mode is selected or network is unavailable
- **THEN** system synthesizes speech locally via native macOS speech synthesizer

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
