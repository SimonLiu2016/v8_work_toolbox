## ADDED Requirements

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
The system SHALL protect commercial AI TTS synthesis against transient HTTP 429 rate limits through stepped backoff delays with observable progress updates, and support synthesis durations up to 90 seconds for long paragraphs.

#### Scenario: HTTP 429 rate limit backoff recovery
- **WHEN** a commercial AI TTS provider responds with HTTP 429 (Too Many Requests)
- **THEN** system waits for stepped backoff intervals (4s, 10s, 20s), notifies the user interface of the waiting state, and retries the request before declaring synthesis failure

#### Scenario: Extended synthesis timeout for dense paragraphs
- **WHEN** a chunk containing up to 600 characters is sent to a commercial AI TTS provider
- **THEN** system permits up to 90 seconds for synthesis completion before raising a timeout exception

## MODIFIED Requirements

### Requirement: Low-latency streaming chunk queue and cache
The system SHALL segment document text into sentence/paragraph chunks and schedule pre-synthesis of subsequent chunks in a strictly serialized, non-colliding order to avoid concurrent request spikes against external providers.

#### Scenario: Soft-break de-wrapping and sentence boundary preservation
- **WHEN** a document with visual hard wraps is loaded
- **THEN** system seamlessly merges intra-sentence line wraps without inserting spaces between CJK characters, aggregates short sentences into coherent 300~600 character speech units, and strictly constrains chunk boundaries to terminal punctuation (`。！？；` or `. ! ? ;`)

#### Scenario: Playback initiates on first paragraph
- **WHEN** user clicks play on a new document
- **THEN** system immediately synthesizes the first chunk with highest priority, begins audio playback as soon as the first chunk is ready, and schedules subsequent preloading strictly after playback commences without issuing eager prefetch during initial document loading

#### Scenario: Preloading subsequent chunk
- **WHEN** audio playback of chunk `i` begins
- **THEN** system serializes a background prefetch task specifically for chunk `i + 1` without colliding with the actively playing chunk or flooding provider rate limits

#### Scenario: Cache hit on replay
- **WHEN** user replays or jumps back to a previously played paragraph
- **THEN** system plays from local audio cache instantly without re-synthesizing

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
