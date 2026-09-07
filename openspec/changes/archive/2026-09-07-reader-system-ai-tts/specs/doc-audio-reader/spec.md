## MODIFIED Requirements

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

#### Scenario: Default resolution via system global AI configuration
- **WHEN** Commercial AI TTS mode is selected and user chooses to use system AI configuration
- **THEN** system automatically resolves the TTS capability slot, provider endpoint, and secure Keychain credentials from the global AI configuration store without requiring manual entry

#### Scenario: Custom voice ID specification for third-party providers
- **WHEN** user inputs a custom voice ID for an OpenAI-compatible speech provider
- **THEN** system passes the custom voice identifier in the synthesis request body to the target provider
