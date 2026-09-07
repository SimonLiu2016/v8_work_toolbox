## MODIFIED Requirements

### Requirement: Integrated AI STT slot transcription
The system SHALL transcribe audio extracted from local media or online streams into timestamped subtitle segments utilizing the global AI STT slot binding, adaptively selecting between standard OpenAI Whisper multipart transcription and Xiaomi MiMo chat completions speech recognition protocols based on provider and model metadata.

#### Scenario: Audio extraction and pre-processing
- **WHEN** user initiates AI subtitle generation for a video
- **THEN** system extracts lightweight 16kHz mono audio using ffmpeg or yt-dlp to meet STT payload constraints before dispatching API requests

#### Scenario: STT transcription with segment timestamps
- **WHEN** audio is submitted to the configured AI STT provider
- **THEN** system dispatches to the corresponding protocol (OpenAI Whisper multipart or MiMo Chat Completions with base64 audio and asr_options) and parses the response into structured subtitle segments with start and end timestamps

### Requirement: Multi-tier fast subtitle extraction and offline generation
The system SHALL provide a multi-tier fast generation pipeline prioritizing instant native/embedded subtitle extraction before falling back to fastest full-audio extraction and AI transcription.

#### Scenario: Extract online native or auto subtitles
- **WHEN** user requests fast subtitle generation for a supported online URL (e.g. Bilibili or YouTube)
- **THEN** system uses yt-dlp to extract available native or auto-generated subtitles within seconds, saving and mounting the resulting SRT file

#### Scenario: Extract embedded soft subtitles from local file
- **WHEN** user requests fast subtitle generation for a local video containing embedded subtitle tracks
- **THEN** system uses ffmpeg to extract the primary subtitle track to an SRT file in less than 2 seconds and mounts it immediately

#### Scenario: Fallback to single-pass full audio transcription
- **WHEN** no native or embedded subtitle tracks exist on the video
- **THEN** system extracts the complete audio using the fastest method (ffmpeg 16kHz 32kbps mono for local media, or yt-dlp audio-only download for web URLs), submits to the configured AI STT service, compiles a complete .srt file, and mounts it to the player

## ADDED Requirements

### Requirement: Xiaomi MiMo ASR protocol and chunk-based timestamp alignment
The system SHALL support Xiaomi MiMo's `mimo-v2.5-asr` model via the `/v1/chat/completions` API using Base64 encoded audio payloads and concurrent slice processing to establish accurate subtitle timestamps.

#### Scenario: Transcribe via Xiaomi MiMo ASR
- **WHEN** the configured STT model is `mimo-v2.5-asr` or provider baseUrl points to Xiaomi MiMo
- **THEN** system encodes the audio chunk into Base64 (`data:audio/mp3;base64,...`), sets `asr_options.language: "auto"`, includes `api-key` and `Authorization` headers, and extracts the transcribed text from `choices[0].message.content`

#### Scenario: Concurrent slice processing for full timeline alignment
- **WHEN** transcribing a full audio track with MiMo ASR
- **THEN** system segments the audio into short time intervals with known start and end offsets, executes transcriptions using a concurrent worker pool, and stitches the resulting text into consecutive subtitle segments covering the entire timeline
