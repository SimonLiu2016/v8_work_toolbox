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

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (e.g., stdio command or SSE endpoint) to consume external tool calls.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, transport type (stdio/SSE), command or URL, and parameters
- **THEN** the configuration is saved and registered in the application AI service for downstream tool invocation.
