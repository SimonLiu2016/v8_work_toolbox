## Purpose

Establishes a centralized AI capability infrastructure with secure Keychain credential storage, multi-protocol provider management, model slot binding, and external MCP client configuration.

## Requirements

### Requirement: Secure credential storage via macOS Keychain
The application SHALL store all sensitive provider API keys and authentication tokens in the macOS Keychain rather than plain text JSON configuration files.

#### Scenario: Storing and retrieving provider API key
- **WHEN** user inputs or updates an API key for a provider in the AI settings interface
- **THEN** the key is encrypted and stored in the macOS Keychain using a unique identifier, and the on-disk config only stores the reference key ID.

#### Scenario: Keychain fallback or retrieval error
- **WHEN** the application fails to retrieve a key from Keychain
- **THEN** the system logs a non-fatal warning, indicates the missing credential status in the UI, and prevents requests to that provider without crashing.

### Requirement: Multi-protocol AI provider management
The AI configuration module SHALL support configuring multiple providers adhering to OpenAI-compatible, Anthropic, or Google Gemini protocols.

#### Scenario: Adding an OpenAI-compatible provider
- **WHEN** user specifies an endpoint URL, protocol type "OpenAI Compatible", and associated credentials
- **THEN** the provider is persisted in `ai_config.json`, validated via a connection test, and made available for model discovery.

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via provider API or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT).

#### Scenario: Automatic model discovery
- **WHEN** user clicks "Detect Models" for an active OpenAI-compatible or supported provider
- **THEN** the system queries the provider's models endpoint and populates the model choices into the configuration dialog.

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests text completion without specifying an explicit provider
- **THEN** the system resolves the provider and model bound to the default "Text" capability slot.

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (e.g., stdio command or SSE endpoint) to consume external tool calls.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, transport type (stdio/SSE), command or URL, and parameters
- **THEN** the configuration is saved and registered in the application AI service for downstream tool invocation.
