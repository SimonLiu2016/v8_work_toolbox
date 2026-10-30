# secure-secret-storage Delta

## MODIFIED Requirements

### Requirement: DEK file fallback for unsigned environments
When the macOS Keychain rejects DEK writes (unsigned/adhoc builds), the layer SHALL persist the DEK to a local file (`~/Library/Application Support/V8WorkToolbox/.dek`) with POSIX 0600 permissions (owner-read-only), so secrets remain encrypted at rest without requiring code signing. A freshly generated file-fallback DEK MUST pass DEK-ciphertext match verification before activation when ciphertext already exists; if it does not match, the controlled mismatch-recovery flow applies instead of silent activation. The file fallback SHALL be maintained as a mirror of the Keychain DEK whenever a DEK is written, not only when Keychain writes throw — because Keychain writes can succeed (no exception thrown) yet remain invisible to subsequent reads under ad-hoc signing, and that half-succeeded state MUST be detected and recovered by falling back to the file.

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

#### Scenario: Keychain write succeeds but is invisible to later reads
- **WHEN** a DEK write to the Keychain returns without error, but a read-back immediately after cannot retrieve the value
- **THEN** the layer treats the Keychain as effectively unavailable for this install, and persists the DEK to the file fallback so the next restart can recover it
- **AND** the layer MUST NOT consider the DEK durably stored on the basis of a non-throwing write alone

#### Scenario: File mirror maintained alongside Keychain
- **WHEN** the layer writes a DEK to the Keychain (whether or not the write throws)
- **THEN** the same DEK is also written to the file fallback with 0600 permissions
- **AND** on restart, if the Keychain is unreadable, the file DEK decrypts the existing ciphertext without entering mismatch recovery

### Requirement: Controlled mismatch recovery with evidence backup
When the DEK cannot authenticate existing ciphertext and the original DEK is unrecoverable from BOTH the Keychain and the file fallback, the layer SHALL: (1) preserve the unreadable ciphertext as a timestamped backup file (never delete it silently); (2) reinitialize an empty secret store encrypted with the current DEK so writes succeed immediately; (3) surface a one-time, user-facing signal that the secret store was rebuilt and previously stored secrets are unrecoverable and must be re-entered. Mismatch recovery MUST NOT trigger merely because the Keychain is unreadable on restart — the file fallback SHALL be attempted first, and only when both DEK sources fail to authenticate the ciphertext does recovery run.

#### Scenario: Mismatch triggers backup and rebuild
- **WHEN** the active DEK fails to authenticate `.secrets.bin` AND no recoverable DEK exists in either the Keychain or the file fallback
- **THEN** the existing ciphertext is copied to a timestamped backup (e.g. `.secrets.bin.mismatch-<timestamp>`), an empty store is written with the current DEK, and subsequent reads/writes succeed

#### Scenario: File fallback prevents spurious mismatch on restart
- **WHEN** the Keychain is unreadable on restart but a valid file-stored DEK exists that authenticates the existing ciphertext
- **THEN** the layer uses the file DEK, reads succeed, and mismatch recovery does NOT run

#### Scenario: User is informed once after rebuild
- **WHEN** the mismatch-recovery rebuild completes
- **THEN** the consuming UI surfaces a clear message that secrets were reset and must be re-entered, referencing the backup file location

#### Scenario: Backup is never silently deleted
- **WHEN** mismatch recovery runs
- **THEN** the original ciphertext bytes remain on disk in the backup file until the user removes them manually

### Requirement: Single KekManager instance
The DEK lifecycle manager SHALL be a process-wide singleton, so that all secret consumers (the AI config keychain, the password vault, and the settings panel) share one in-memory DEK cache. Multiple instances with independent caches MUST NOT coexist, because a cache invalidation in one (e.g. lock) would not propagate to others, and independent instances can resolve different DEKs depending on which Keychain partition they hit.

#### Scenario: All consumers share one DEK cache
- **WHEN** the AI config service, the password vault, and the settings panel each need the DEK
- **THEN** they all obtain it from the same singleton lifecycle manager, sharing the in-memory cache

#### Scenario: Lock propagates across consumers
- **WHEN** any consumer calls lock on the shared lifecycle manager
- **THEN** the in-memory DEK cache is cleared for all consumers, so none can read the DEK from a stale cache afterward
