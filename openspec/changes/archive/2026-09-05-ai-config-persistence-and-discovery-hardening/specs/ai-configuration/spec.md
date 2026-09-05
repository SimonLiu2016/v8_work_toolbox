## MODIFIED Requirements

### Requirement: Secure credential storage via macOS Keychain
The application SHALL store all sensitive provider API keys and authentication tokens in the macOS Keychain with an automatic encrypted local file fallback mechanism to ensure credential durability across restarts.

#### Scenario: Storing and retrieving provider API key
- **WHEN** user inputs or updates an API key for a provider in the AI settings interface
- **THEN** the key is encrypted and stored in the macOS Keychain (or persisted into the encrypted local credentials fallback file if Keychain is unavailable), and the on-disk `ai_config.json` only stores the reference key ID.

#### Scenario: Keychain fallback or retrieval error
- **WHEN** the application fails to access system Keychain due to environment or entitlement constraints
- **THEN** the system seamlessly reads from the encrypted local fallback file, ensuring credentials persist across application restarts.

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT), without masking failures with fake fallback models.

#### Scenario: Automatic model discovery with existing saved credentials
- **WHEN** user opens an existing provider dialog without re-entering the API Key and clicks "Detect Models"
- **THEN** the system resolves the provider's stored credential and queries the models endpoint, reporting authentic errors if the request fails.

#### Scenario: Transparent error feedback on detection failure
- **WHEN** model detection fails due to network or authentication issues
- **THEN** an error message showing the root cause (e.g. HTTP 401/404 or connection timeout) is presented to the user, and no synthetic/fake model list is populated.
