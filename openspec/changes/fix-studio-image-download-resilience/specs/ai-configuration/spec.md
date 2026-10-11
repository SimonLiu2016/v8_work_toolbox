## MODIFIED Requirements

### Requirement: Multi-protocol AI provider management
The AI configuration module SHALL support configuring multiple providers adhering to OpenAI-compatible, Anthropic, Google Gemini, or Agnes protocols, executing authentic HTTP connection handshakes and chat/image/video requests according to each protocol's API specification, with adaptive path normalization, fixed endpoint conventions, resilient CDN media asset downloading with automatic retry, and credential compatibility for third-party reverse proxies and gateways.

#### Scenario: Adding an OpenAI-compatible provider
- **WHEN** user specifies an endpoint URL, protocol type "OpenAI Compatible", and associated credentials
- **THEN** the provider is persisted in `ai_config.json`, validated via a real HTTP `/models` connection test, and made available for model discovery.

#### Scenario: Adding an Agnes provider protocol
- **WHEN** user selects protocol type "Agnes" (or quick preset "Agnes / 中转站 (视/图多模态)")
- **THEN** the provider supports text chat via OpenAI-compatible endpoints (`/v1/chat/completions`), image generation via `/v1/images/generations` with standard payload `{model, prompt}`, and video generation via `/v1/videos`.

#### Scenario: Resilient download of generated image assets from CDN
- **WHEN** image generation API returns a remote media URL on cloud storage CDN (e.g. Tencent Cloud COS)
- **THEN** the system downloads the image asset using isolated short connections and browser headers, and automatically retries upon connection resets or transient socket errors to ensure successful local disk persistence.

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
