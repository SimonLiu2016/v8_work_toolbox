# ai-configuration Delta

## MODIFIED Requirements

### Requirement: Secure credential storage via macOS Keychain and Protected File Fallback
The application SHALL store all sensitive provider API keys and authentication tokens in the macOS Keychain with a fallback encrypted file (AES-256-GCM ciphertext whose data-encryption key is held in the Keychain) to guarantee persistence. The fallback SHALL NOT be an obfuscated store: when the DEK is unavailable, the system SHALL surface a clear error identifying the recovery path (key backup restore) instead of silently degrading security.

#### Scenario: Storing and retrieving provider API key
- **WHEN** user inputs or updates an API key for a provider in the AI settings interface
- **THEN** the key is encrypted and stored in the macOS Keychain (and synced to the AES-256-GCM encrypted local store) using a unique identifier, and the on-disk config only stores the reference key ID.

#### Scenario: Keychain unavailable in dev/unsigned environment
- **WHEN** the macOS Keychain is unavailable due to missing code signature entitlements and the data-encryption key cannot be retrieved
- **THEN** the system surfaces a clear error identifying the recovery path (restore from key backup), and does not silently fall back to an obfuscated plaintext-equivalent store; previously stored credentials are not silently exposed or overwritten.
