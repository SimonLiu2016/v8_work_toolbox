## Purpose

Defines the OpenRouter model provider protocol integration, preset configuration, and the slot-driven universal ASR interface enabling seamless switching between StepFun and OpenRouter transcription.

## ADDED Requirements

### Requirement: OpenRouter Provider Protocol and Configuration Preset
The system SHALL support `openrouter` as a recognized `AiProtocolType`. The AI infrastructure configuration UI SHALL provide an OpenRouter preset action that pre-fills the provider name (`OpenRouter`), protocol (`openrouter`), base URL (`https://openrouter.ai/api/v1`), default chat models, and speech recognition model (`qwen/qwen3-asr-0.6b`). `AiService` SHALL route OpenRouter chat and model discovery requests through the OpenAI-compatible communication pipeline.

#### Scenario: User adds OpenRouter provider via preset
- **WHEN** the user clicks the "OpenRouter" preset chip in the Add Provider dialog
- **THEN** the provider name, protocol, base URL, and recommended models are automatically populated with OpenRouter defaults.

#### Scenario: OpenRouter discovery and chat completion
- **WHEN** an enabled provider has protocol `openrouter` and valid API key
- **THEN** model discovery and chat completion execute using standard OpenAI-compatible endpoints with OpenRouter authorization headers.

### Requirement: Slot-Driven Universal ASR Routing
The live translator coordinator SHALL dynamically resolve the speech-to-text engine from the `stt` capability slot binding. If the bound provider uses StepFun protocol, it SHALL route audio to `StepFunAsrClient`; if the bound provider uses OpenRouter or OpenAI protocol (or targets OpenRouter ASR models), it SHALL route audio to `OpenRouterAsrClient` without throwing provider type mismatch errors.

#### Scenario: Live translation starts with OpenRouter bound to stt slot
- **WHEN** the user starts live translation while the `stt` slot is bound to an OpenRouter provider with model `qwen/qwen3-asr-0.6b`
- **THEN** audio chunks are captured, packaged as WAV, and transcribed via OpenRouter STT without "StepFun ASR provider not configured" errors.

#### Scenario: Live translation starts with StepFun bound to stt slot
- **WHEN** the user starts live translation while the `stt` slot is bound to a StepFun provider
- **THEN** audio chunks are streamed to the StepFun SSE transcription endpoint as before.

### Requirement: OpenRouter Audio Transcription Execution
The system SHALL implement `OpenRouterAsrClient` adhering to the universal `LiveAsrClient` interface. The client SHALL convert raw 16kHz 16-bit PCM chunks into compliant WAV byte streams, encode them to Base64, and send a JSON POST request to OpenRouter's `/audio/transcriptions` endpoint with the specified model (e.g. `qwen/qwen3-asr-0.6b`). On receiving a successful transcript, it SHALL yield an `AsrEvent.done(text)` event.

#### Scenario: Audio chunk transcribed via OpenRouter
- **WHEN** a valid PCM chunk is submitted to `OpenRouterAsrClient.transcribe`
- **THEN** the client sends a WAV-formatted JSON payload to `https://openrouter.ai/api/v1/audio/transcriptions` and yields the recognized text as a done event.

#### Scenario: OpenRouter API returns authentication or quota error
- **WHEN** OpenRouter returns HTTP status 401 (auth) or 402 (insufficient credits)
- **THEN** the client classifies the failure into an `AsrException` with appropriate `AsrErrorKind` and detail message.
