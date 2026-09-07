## MODIFIED Requirements

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
