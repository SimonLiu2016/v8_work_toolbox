## MODIFIED Requirements

### Requirement: Tri-mode Text-to-Speech synthesis engine
The system SHALL provide a tri-mode TTS engine supporting Edge-TTS, OpenAI-compatible commercial TTS APIs, and macOS native speech synthesis, with automatic protocol adaptation for legacy speech, chat audio models, and vendor-specific voice conventions.

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

#### Scenario: Voice adaptation for Qwen and CosyVoice TTS models
- **WHEN** user synthesizes audio using a Qwen or CosyVoice model (such as `cosyvoice-v3-flash` or `qwen-audio-tts`) or a provider whose endpoint is on `qianwenaiapi.com` or `dashscope.aliyuncs.com`
- **THEN** the system SHALL NOT send OpenAI-specific default voice identifiers (such as `alloy`)
- **AND** the system SHALL automatically substitute an applicable Qwen/CosyVoice voice (defaulting to `longxiaochun` or `Cherry`) when the configured voice is empty or an OpenAI default voice
