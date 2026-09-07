## Purpose

Establishes a centralized AI capability infrastructure with secure Keychain credential storage, multi-protocol provider management, model slot binding, and external MCP client configuration.
## Requirements
### Requirement: Secure credential storage via macOS Keychain and Protected File Fallback
The application SHALL store all sensitive provider API keys and authentication tokens in the macOS Keychain with a fallback protected encrypted file (`.secrets.dat`) to guarantee persistence even in unsigned/development environments without entitlements.

#### Scenario: Storing and retrieving provider API key
- **WHEN** user inputs or updates an API key for a provider in the AI settings interface
- **THEN** the key is encrypted and stored in the macOS Keychain (and synced to local protected obfuscation store) using a unique identifier, and the on-disk config only stores the reference key ID.

#### Scenario: Keychain unavailable in dev/unsigned environment
- **WHEN** the macOS Keychain is unavailable due to missing code signature entitlements
- **THEN** the system automatically falls back to reading/writing the local obfuscated secret store, ensuring credentials are preserved across app restarts without throwing fatal crashes.

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

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT). Each slot SHALL support an ordered list of provider-model candidates instead of a single binding, with user-controllable priority ordering.

#### Scenario: Automatic model discovery
- **WHEN** user clicks "Detect Models" for an active provider
- **THEN** the system queries the provider's models endpoint via real HTTP request and populates returned model identifiers, or raises an informative error if the credentials/network fail.

#### Scenario: Adding a candidate to a slot
- **WHEN** user selects a provider and model and adds them to a slot's candidate list
- **THEN** the new candidate is appended at the lowest priority position, and the slot's ordered candidate list is persisted to `ai_config.json`

#### Scenario: Reordering slot candidates
- **WHEN** user drags a candidate to a new position within a slot's candidate list
- **THEN** the priority order is updated accordingly and persisted, and subsequent AI routing uses the new order

#### Scenario: Removing a candidate from a slot
- **WHEN** user removes a candidate from a slot's candidate list
- **THEN** the candidate is removed, remaining candidates retain their relative order, and the change is persisted

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests text completion without specifying an explicit provider
- **THEN** the system resolves the provider and model via the slot's ordered candidate list and the auto-healing routing engine

#### Scenario: Backward-compatible loading of legacy single-binding format
- **WHEN** the application loads an `ai_config.json` containing the legacy `defaultSlots` format with single `{providerId, model}` entries
- **THEN** each legacy binding is automatically migrated to a single-element candidate list, and the config is re-saved in the new format without data loss

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (e.g., stdio command or SSE endpoint) to consume external tool calls.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, transport type (stdio/SSE), command or URL, and parameters
- **THEN** the configuration is saved and registered in the application AI service for downstream tool invocation.

### Requirement: Slot health status visualization
The AI configuration UI SHALL display a real-time health indicator (green / yellow / red) for each capability slot, reflecting the aggregate health of its candidates, and SHALL show the currently active provider and most recent degradation event if any.

#### Scenario: All candidates healthy
- **WHEN** user views the slot configuration tab and all candidates for a slot are responsive
- **THEN** the slot displays a green health indicator and shows the primary candidate as active

#### Scenario: Primary degraded to fallback
- **WHEN** the primary candidate is unhealthy and requests are being served by a fallback
- **THEN** the slot displays a yellow health indicator, names the active fallback provider, and shows the time since the primary went unhealthy

#### Scenario: All candidates unhealthy
- **WHEN** all candidates for a slot are marked unhealthy
- **THEN** the slot displays a red health indicator with a message prompting the user to check provider configuration or network connectivity

### Requirement: Two-phase authentic connection and ping verification
The connection testing mechanism in the AI configuration interface SHALL execute two-phase verification: first probing model discoverability, followed immediately by a minimal test completion request (Ping) to verify that both model enumeration and chat inference endpoints are healthy before confirming success.

#### Scenario: Both model discovery and ping completion succeed
- **WHEN** user clicks "Test Connection" for a configured provider
- **THEN** the system successfully fetches models and receives a valid ping response, displaying a green success confirmation.

#### Scenario: Model discovery succeeds but chat completion endpoint fails
- **WHEN** model discovery endpoint returns 200 but chat endpoint returns 404 or authentication error
- **THEN** the connection test fails with a descriptive error indicating that chat completions failed, preventing false-positive configuration passes.

### Requirement: In-app real-time AI invocation observation and logging
The application SHALL provide an in-app visual dialog/panel that captures and displays AI requests, responses, warnings, and errors in real-time, allowing users to observe interactions, copy diagnostic details, and clear logs.

#### Scenario: Opening AI log viewer from AI configuration page
- **WHEN** user clicks the "View Invocation Logs" button on the AI infrastructure configuration page
- **THEN** the application displays a dialog showing recent AI invocation log entries with timestamps, provider name, protocol, status code, duration, and payloads.

#### Scenario: Opening AI log viewer from Smart Disk Slimmer page
- **WHEN** user clicks the "AI Log" button adjacent to the "AI Batch Diagnostics" button
- **THEN** the application opens the AI log viewer dialog displaying the latest batch diagnostic requests and responses.

#### Scenario: Real-time update of ongoing requests
- **WHEN** an AI request, response, retry warning, or error occurs while the log viewer dialog is open
- **THEN** the dialog updates reactively to display the new entry without requiring manual reload.

#### Scenario: Copying and clearing logs
- **WHEN** user clicks the copy button in the log viewer
- **THEN** the formatted plain-text log transcript is copied to the system clipboard.
- **WHEN** user clicks the clear button
- **THEN** all retained in-memory log entries are purged and the list view resets to an empty state.

