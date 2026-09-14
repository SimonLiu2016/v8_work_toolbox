# secure-secret-storage Specification

## Purpose
Defines the rewritten secret storage layer: AES-256-GCM encryption with a data-encryption key held in the macOS Keychain, replacing XOR obfuscation — establishing the security foundation the password vault and all other secret consumers rely on.
## Requirements
### Requirement: AES-256-GCM encryption of secret data
The secret storage layer SHALL encrypt all persisted secret data with AES-256-GCM before writing to disk, using a 12-byte random nonce generated per write. Plaintext secret data SHALL never be written to disk.

#### Scenario: Writing secret data
- **WHEN** a secret is saved
- **THEN** the data written to disk is AES-256-GCM ciphertext with a fresh random nonce, and no plaintext equivalent exists on disk

#### Scenario: Tampered ciphertext rejected
- **WHEN** the on-disk ciphertext file is modified outside the application
- **THEN** decryption fails authentication and the layer reports an integrity error instead of returning corrupted data

### Requirement: Data-encryption key held in macOS Keychain
The secret storage layer SHALL store its 32-byte random data-encryption key (DEK) in the macOS Keychain under a fixed service name, and SHALL use it only in memory for encryption/decryption. The DEK SHALL never be written to application data directories.

#### Scenario: First run generates a DEK
- **WHEN** the layer initializes and no DEK exists in the Keychain
- **THEN** a fresh 32-byte random DEK is generated and stored in the Keychain under a fixed service name

#### Scenario: DEK persists across restarts
- **WHEN** the application restarts
- **THEN** the existing DEK is read from the Keychain and previously written ciphertext is readable

### Requirement: Fail-fast on missing DEK
The secret storage layer SHALL NOT silently fall back to unencrypted or obfuscated secret storage. When the DEK is unavailable from all sources (Keychain and file fallback), the layer SHALL surface a clear error identifying the recovery path (restore from key backup) instead of degrading security.

#### Scenario: Keychain unavailable at startup
- **WHEN** the Keychain rejects DEK access on startup
- **THEN** the layer attempts to read the DEK from the local file fallback; if that also fails, it reports a clear error naming the recovery path

#### Scenario: DEK lost with ciphertext present
- **WHEN** ciphertext exists on disk but the DEK cannot be retrieved from any source
- **THEN** the layer reports an unrecoverable-encryption error and prompts the user to restore from a key backup

### Requirement: Plaintext metadata and encrypted secret separation
The storage layer SHALL keep entry metadata (titles, URLs, usernames, tags, timestamps) in plaintext JSON for search and display, and SHALL encrypt only the secret-bearing fields. Read operations SHALL NOT require decrypting the entire vault to list or search entries.

#### Scenario: Searching without full decryption
- **WHEN** a search query is executed against stored entries
- **THEN** matching is performed over plaintext metadata without decrypting secret fields

#### Scenario: Secret fields not present in plaintext storage
- **WHEN** the on-disk metadata is inspected
- **THEN** no secret values (passwords, TOTP seeds, note contents) appear in it

### Requirement: Atomic writes
The secret storage layer SHALL write ciphertext atomically (write to a temporary file, flush, then rename over the target) so that a crash mid-write cannot corrupt existing data.

#### Scenario: Crash during write
- **WHEN** the application is interrupted while saving secrets
- **THEN** the previously written ciphertext remains intact and readable on next launch

### Requirement: Legacy XOR store removal
The secret storage layer SHALL NOT read or write the legacy XOR-obfuscated `.secrets.dat` store. Legacy data SHALL only be consumed by the one-time migration wizard, and the legacy file SHALL be deleted after successful migration.

#### Scenario: No fallback to XOR store
- **WHEN** the encrypted store is unavailable or unreadable
- **THEN** the layer does not silently fall back to reading the legacy obfuscated file

#### Scenario: Legacy file deleted after migration
- **WHEN** the migration wizard completes successfully
- **THEN** the legacy `.secrets.dat` file is deleted from disk

### Requirement: Stable Keychain service naming
The secret storage layer SHALL use a fixed, application-defined Keychain service name for the DEK (not a bundle-identifier-derived default) so that application renaming or re-signing does not orphan the DEK.

#### Scenario: Application renamed without DEK loss
- **WHEN** the application bundle is renamed or re-signed
- **THEN** the DEK remains retrievable under the fixed service name

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

