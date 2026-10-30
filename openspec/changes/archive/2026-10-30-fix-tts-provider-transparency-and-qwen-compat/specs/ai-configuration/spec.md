## MODIFIED Requirements

### Requirement: Multi-protocol AI provider management
The AI configuration module SHALL support configuring multiple providers adhering to OpenAI-compatible, Anthropic, Google Gemini, or Agnes protocols, executing authentic HTTP connection handshakes and chat/image/video/speech requests according to each protocol's API specification, with adaptive path normalization, fixed endpoint conventions, and credential compatibility for third-party reverse proxies and gateways.

When the module offers quick-fill presets for a provider, each preset SHALL fill values that are true for that provider: the preset's name SHALL identify the provider without naming an access route that is not part of the provider's own service, and the filled Base URL and model identifiers SHALL be models that the provider actually serves. A preset MUST NOT fill a Base URL or model list that belongs to a different service, and TTS models for DashScope/Qwen speech providers SHALL reference valid audio speech models supported by the upstream service (`qwen-audio-3.0-tts-plus`, `qwen-audio-3.1-tts-plus`, `qwen-audio-3.1-tts-flash`).

When a preset fills a Base URL, it SHALL NOT overwrite an address the user has already entered, except when the current value is empty or is a well-known default for another provider.

#### Scenario: Adding an OpenAI-compatible provider
- **WHEN** user specifies an endpoint URL, protocol type "OpenAI Compatible", and associated credentials
- **THEN** the provider is persisted in `ai_config.json`, validated via a real HTTP `/models` connection test, and made available for model discovery.

#### Scenario: Adding an Agnes provider protocol
- **WHEN** user selects protocol type "Agnes" (or quick preset "Agnes")
- **THEN** the provider supports text chat via OpenAI-compatible endpoints (`/v1/chat/completions`), image generation via `/v1/images/generations` with standard payload `{model, prompt}`, and video generation via `/v1/videos`.

#### Scenario: Adding an Anthropic provider
- **WHEN** user specifies an Anthropic API Key and baseUrl (or defaults to `https://api.anthropic.com`)
- **THEN** connection testing and model discovery query `https://api.anthropic.com/v1/models` using `x-api-key` headers, and chat completions use `/v1/messages`.

#### Scenario: Adding a Gemini provider
- **WHEN** user specifies a Google Gemini API Key and baseUrl (or defaults to `https://generativelanguage.googleapis.com`)
- **THEN** connection testing and model discovery query `v1beta/models`, and chat completions use `v1beta/models/{model}:generateContent`.

#### Scenario: Automatic URL normalization for OpenAI-compatible providers
- **WHEN** user specifies an endpoint URL without `/v1` suffix (e.g. `https://host.com`) and OpenAI-compatible protocol
- **THEN** the system automatically probes and normalizes the endpoint to `/v1/models` and `/v1/chat/completions` if the bare path returns 404, preventing false connection failures.

#### Scenario: Gateway route adaptation for Anthropic providers
- **WHEN** user specifies an Anthropic provider whose gateway mounts endpoints under `/anthropic/v1/messages` instead of the root `/v1/messages`
- **THEN** the system automatically discovers and routes chat requests to `/anthropic/v1/messages` when `/v1/messages` returns 404, and caches the successful endpoint path for subsequent requests.

#### Scenario: Dual authentication header injection for Anthropic and OpenAI proxies
- **WHEN** dispatching requests to an Anthropic or OpenAI provider endpoint
- **THEN** the system injects both `x-api-key` and `api-key` headers for Anthropic, and both `Authorization: Bearer` and `api-key` headers for OpenAI where supported, ensuring compatibility with domestic gateway specifications.

#### Scenario: Quick-fill preset matches the provider it names
- **WHEN** user activates a provider's quick-fill preset
- **THEN** the filled Base URL SHALL be that provider's own service address, and the filled model identifiers SHALL be models that provider serves
- **AND** the preset SHALL NOT fill an address or model list belonging to a different service

#### Scenario: Preset does not clobber a user-entered address
- **WHEN** user has already entered a Base URL and then activates a quick-fill preset
- **THEN** the system SHALL NOT overwrite that address
- **AND** the system SHALL overwrite it only when the field is empty or holds another provider's well-known default

#### Scenario: Qwen quick-fill preset fills valid speech models
- **WHEN** user activates the Qwen quick-fill preset in AI Settings
- **THEN** the filled TTS models list SHALL contain valid DashScope speech models (`qwen-audio-3.0-tts-plus, qwen-audio-3.1-tts-plus, qwen-audio-3.1-tts-flash`).
