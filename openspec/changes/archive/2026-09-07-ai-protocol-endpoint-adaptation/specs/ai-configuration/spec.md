## MODIFIED Requirements

### Requirement: Multi-protocol AI provider management
The AI configuration module SHALL support configuring multiple providers adhering to OpenAI-compatible, Anthropic, or Google Gemini protocols, executing authentic HTTP connection handshakes and chat requests according to each protocol's API specification, with adaptive path normalization and dual authentication header compatibility for third-party reverse proxies and gateways.

#### Scenario: Adding an OpenAI-compatible provider
- **WHEN** user specifies an endpoint URL, protocol type "OpenAI Compatible", and associated credentials
- **THEN** the provider is persisted in `ai_config.json`, validated via a real HTTP `/models` connection test, and made available for model discovery.

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

## ADDED Requirements

### Requirement: Two-phase authentic connection and ping verification
The connection testing mechanism in the AI configuration interface SHALL execute two-phase verification: first probing model discoverability, followed immediately by a minimal test completion request (Ping) to verify that both model enumeration and chat inference endpoints are healthy before confirming success.

#### Scenario: Both model discovery and ping completion succeed
- **WHEN** user clicks "Test Connection" for a configured provider
- **THEN** the system successfully fetches models and receives a valid ping response, displaying a green success confirmation.

#### Scenario: Model discovery succeeds but chat completion endpoint fails
- **WHEN** model discovery endpoint returns 200 but chat endpoint returns 404 or authentication error
- **THEN** the connection test fails with a descriptive error indicating that chat completions failed, preventing false-positive configuration passes.
