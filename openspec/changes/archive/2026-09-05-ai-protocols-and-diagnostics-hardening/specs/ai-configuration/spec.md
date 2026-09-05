## MODIFIED Requirements

### Requirement: Multi-protocol AI provider management
The AI configuration module SHALL support configuring multiple providers adhering to OpenAI-compatible, Anthropic, or Google Gemini protocols, executing authentic HTTP connection handshakes and chat requests according to each protocol's API specification.

#### Scenario: Adding an OpenAI-compatible provider
- **WHEN** user specifies an endpoint URL, protocol type "OpenAI Compatible", and associated credentials
- **THEN** the provider is persisted in `ai_config.json`, validated via a real HTTP `/models` connection test, and made available for model discovery.

#### Scenario: Adding an Anthropic provider
- **WHEN** user specifies an Anthropic API Key and baseUrl (or defaults to `https://api.anthropic.com`)
- **THEN** connection testing and model discovery query `https://api.anthropic.com/v1/models` using `x-api-key` headers, and chat completions use `/v1/messages`.

#### Scenario: Adding a Gemini provider
- **WHEN** user specifies a Google Gemini API Key and baseUrl (or defaults to `https://generativelanguage.googleapis.com`)
- **THEN** connection testing and model discovery query `v1beta/models`, and chat completions use `v1beta/models/{model}:generateContent`.

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT).

#### Scenario: Automatic model discovery
- **WHEN** user clicks "Detect Models" for an active provider
- **THEN** the system queries the provider's models endpoint via real HTTP request and populates returned model identifiers, or raises an informative error if the credentials/network fail.

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests text completion without specifying an explicit provider
- **THEN** the system resolves the provider and model bound to the default "Text" capability slot.
