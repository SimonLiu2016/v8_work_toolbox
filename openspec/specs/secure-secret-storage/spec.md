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
The secret storage layer SHALL NOT silently fall back to unencrypted or obfuscated secret storage. When the DEK is unavailable from all sources (Keychain and file fallback), the layer SHALL surface a clear error identifying the recovery path (restore from key backup) instead of degrading security. Failure classes MUST be distinguished: (a) DEK missing entirely, (b) DEK present but not matching ciphertext (enters controlled mismatch recovery instead of fail-fast), (c) ciphertext corrupt independent of DEK (integrity error, fail-fast with backup preserved).

#### Scenario: Keychain unavailable at startup
- **WHEN** the Keychain rejects DEK access on startup
- **THEN** the layer attempts to read the DEK from the local file fallback; if that also fails, it reports a clear error naming the recovery path

#### Scenario: DEK lost with ciphertext present
- **WHEN** ciphertext exists on disk but the DEK cannot be retrieved from any source
- **THEN** the layer reports an unrecoverable-encryption error and prompts the user to restore from a key backup

#### Scenario: DEK present but mismatched with ciphertext
- **WHEN** a DEK is available but fails to authenticate existing ciphertext
- **THEN** the layer enters controlled mismatch recovery (backup + rebuild + user signal) instead of reporting an unrecoverable error

#### Scenario: Ciphertext corrupt with matching DEK
- **WHEN** ciphertext fails integrity checks for reasons other than DEK mismatch (truncated, malformed layout)
- **THEN** the layer reports a corruption error and preserves the damaged file for inspection

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
When the macOS Keychain rejects DEK writes (unsigned/adhoc builds), the layer SHALL persist the DEK to a local file (`~/Library/Application Support/V8WorkToolbox/.dek`) with POSIX 0600 permissions (owner-read-only), so secrets remain encrypted at rest without requiring code signing. A freshly generated file-fallback DEK MUST pass DEK-ciphertext match verification before activation when ciphertext already exists; if it does not match, the controlled mismatch-recovery flow applies instead of silent activation.

#### Scenario: First run without Keychain access
- **WHEN** the Keychain rejects the initial DEK write on first run
- **THEN** a fresh DEK is generated and written to the local file with 0600 permissions, and the application starts normally

#### Scenario: Restart with file-stored DEK
- **WHEN** the Keychain is unavailable but a valid file-stored DEK exists
- **THEN** previously encrypted secrets are readable and new secrets can be written

#### Scenario: File permissions enforced
- **WHEN** the DEK file is created or rewritten
- **THEN** its POSIX permissions are set to 0600 (owner read/write only)

#### Scenario: Regenerated file DEK with pre-existing ciphertext
- **WHEN** the DEK file was lost and a fresh DEK is generated while old ciphertext remains
- **THEN** the match verification fails and the controlled mismatch-recovery flow runs (backup + rebuild + user signal) rather than leaving reads/writes deadlocked

### Requirement: DEK-ciphertext match verification before activation
The secret storage layer SHALL verify that any resolved DEK (from Keychain, file fallback, or fresh generation) can authenticate the existing `.secrets.bin` ciphertext before using it for reads or writes. A DEK that fails this verification MUST NOT be cached, used for encryption, or silently activated; the layer SHALL instead enter the controlled mismatch-recovery flow. When no ciphertext exists, any valid DEK MAY activate directly.

#### Scenario: DEK matches existing ciphertext
- **WHEN** a DEK is resolved and `.secrets.bin` decrypts and authenticates with it
- **THEN** the DEK activates normally and reads/writes proceed unchanged

#### Scenario: Fresh DEK with no existing ciphertext
- **WHEN** a fresh DEK is generated and no `.secrets.bin` exists
- **THEN** the DEK activates directly and an empty secret store is initialized

#### Scenario: DEK does not match existing ciphertext
- **WHEN** a resolved or freshly generated DEK fails to authenticate the existing `.secrets.bin`
- **THEN** the DEK is not used for any read or write, and the layer enters the controlled mismatch-recovery flow

### Requirement: Controlled mismatch recovery with evidence backup
When the DEK cannot authenticate existing ciphertext and the original DEK is unrecoverable, the layer SHALL: (1) preserve the unreadable ciphertext as a timestamped backup file (never delete it silently); (2) reinitialize an empty secret store encrypted with the current DEK so writes succeed immediately; (3) surface a one-time, user-facing signal that the secret store was rebuilt and previously stored secrets are unrecoverable and must be re-entered.

#### Scenario: Mismatch triggers backup and rebuild
- **WHEN** the active DEK fails to authenticate `.secrets.bin` and no recoverable DEK exists
- **THEN** the existing ciphertext is copied to a timestamped backup (e.g. `.secrets.bin.mismatch-<timestamp>`), an empty store is written with the current DEK, and subsequent reads/writes succeed

#### Scenario: User is informed once after rebuild
- **WHEN** the mismatch-recovery rebuild completes
- **THEN** the consuming UI surfaces a clear message that secrets were reset and must be re-entered, referencing the backup file location

#### Scenario: Backup is never silently deleted
- **WHEN** mismatch recovery runs
- **THEN** the original ciphertext bytes remain on disk in the backup file until the user removes them manually

### Requirement: Secret write operations never deadlock on mismatch
Secret write operations (save API key, save vault entry) MUST either succeed or return an error carrying actionable recovery guidance. A DEK-ciphertext mismatch MUST NOT leave the store in a state where every subsequent write fails.

#### Scenario: Write succeeds after recovery
- **WHEN** a write follows a completed mismatch-recovery rebuild
- **THEN** the write succeeds against the reinitialized store

#### Scenario: Write failure carries recovery guidance
- **WHEN** a write fails for any reason (DEK unavailable, I/O error, unrecovered mismatch)
- **THEN** the error surfaced to the caller identifies the failure class and the recovery action (restore from key backup, re-enter secrets, or check disk permissions)

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

