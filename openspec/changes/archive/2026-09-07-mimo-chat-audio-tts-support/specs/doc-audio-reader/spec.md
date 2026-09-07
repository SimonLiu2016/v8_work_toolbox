## MODIFIED Requirements

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

## ADDED Requirements

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
