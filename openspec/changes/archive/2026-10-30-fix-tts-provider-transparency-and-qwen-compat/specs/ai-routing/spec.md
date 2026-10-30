## ADDED Requirements

### Requirement: Transparent TTS provider synthesis and voice adaptation
The AI routing engine and TTS synthesis pipeline SHALL provide complete provider transparency for business callers, automatically adapting model identifiers, voice options, and audio protocols according to the selected provider without requiring business callers to adjust vendor-specific configurations.

#### Scenario: Transparent Qwen model normalization
- **WHEN** a business tool requests audio synthesis using the global TTS slot configured with a Qwen/DashScope provider
- **THEN** the TTS engine SHALL route to DashScope's native `SpeechSynthesizer` endpoint (`/api/v1/services/audio/tts/SpeechSynthesizer`)
- **AND** normalize legacy or generic models (`qwen-audio-tts`, `cosyvoice-v1`, `tts-1`) to `qwen-audio-3.0-tts-plus`.

#### Scenario: Cross-vendor voice sanitization for Qwen
- **WHEN** a business tool requests audio synthesis with a voice ID originating from another vendor (e.g. StepFun's `zhixingjiejie`, `cixingnansheng`, or OpenAI's `alloy`) while Qwen is the active TTS provider
- **THEN** the TTS engine SHALL map the voice ID to an appropriate native DashScope voice (`longanlingxin` for female/default, `longanlufeng` for male).

#### Scenario: DashScope audio response retrieval
- **WHEN** the DashScope SpeechSynthesizer endpoint responds with HTTP 200
- **THEN** the engine SHALL extract the audio stream from base64 data or download the generated audio URL and return raw audio bytes to the caller.

#### Scenario: Isolation of candidate models across providers
- **WHEN** resolving the active model for a TTS capability slot
- **THEN** candidate models assigned to a different provider SHALL NOT be used as fallback for the current provider
- **AND** the engine SHALL fallback to the provider's own verified TTS models or provider default.

#### Scenario: Universal vendor voice fallback guard
- **WHEN** audio synthesis is dispatched to any provider (OpenAI, StepFun, Qwen, or MiMo) with an unsupported voice ID
- **THEN** the engine SHALL fallback to a known valid voice profile for that provider rather than failing the request.
