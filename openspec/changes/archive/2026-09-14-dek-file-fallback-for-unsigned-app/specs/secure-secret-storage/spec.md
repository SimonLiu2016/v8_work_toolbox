# secure-secret-storage Delta

## MODIFIED Requirements

### Requirement: Fail-fast on missing DEK
The secret storage layer SHALL NOT silently fall back to unencrypted or obfuscated secret storage. When the DEK is unavailable from all sources (Keychain and file fallback), the layer SHALL surface a clear error identifying the recovery path (restore from key backup) instead of degrading security.

#### Scenario: Keychain unavailable at startup
- **WHEN** the Keychain rejects DEK access on startup
- **THEN** the layer attempts to read the DEK from the local file fallback; if that also fails, it reports a clear error naming the recovery path

#### Scenario: DEK lost with ciphertext present
- **WHEN** ciphertext exists on disk but the DEK cannot be retrieved from any source
- **THEN** the layer reports an unrecoverable-encryption error and prompts the user to restore from a key backup

## ADDED Requirements

### Requirement: DEK file fallback for unsigned environments
When the macOS Keychain rejects DEK writes (unsigned/adhoc builds), the layer SHALL persist the DEK to a local file (`~/Library/Application Support/V8WorkToolbox/.dek`) with POSIX 0600 permissions (owner-read-only), so secrets remain encrypted at rest without requiring code signing.

#### Scenario: First run without Keychain access
- **WHEN** the Keychain rejects the initial DEK write on first run
- **THEN** a fresh DEK is generated and written to the local file with 0600 permissions, and the application starts normally

#### Scenario: Restart with file-stored DEK
- **WHEN** the Keychain is unavailable but a valid file-stored DEK exists
- **THEN** previously encrypted secrets are readable and new secrets can be written

#### Scenario: File permissions enforced
- **WHEN** the DEK file is created or rewritten
- **THEN** its POSIX permissions are set to 0600 (owner read/write only)

### Requirement: DEK source visibility
The layer SHALL expose which source currently holds the DEK (keychain, file, or none) so the UI can inform the user of the effective security level.

#### Scenario: UI displays current DEK source
- **WHEN** the user opens the vault settings
- **THEN** the current DEK source is displayed (macOS 钥匙串 or 本地文件 0600 权限)

### Requirement: Automatic migration to Keychain when available
When the Keychain becomes writable (e.g., after the app is properly signed) and a file-stored DEK exists, the layer SHALL migrate the DEK to the Keychain and delete the file fallback.

#### Scenario: Keychain becomes writable after signing
- **WHEN** the app starts with a file-stored DEK and the Keychain now accepts writes
- **THEN** the DEK is written to the Keychain and the file fallback is deleted
