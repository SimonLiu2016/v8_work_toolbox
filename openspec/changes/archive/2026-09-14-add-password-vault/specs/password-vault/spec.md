# password-vault Delta

## Purpose

Provides a local-first password management tool with encrypted vault storage, password generation, TOTP two-factor codes, password health auditing, and clipboard hygiene — fully offline-capable, no account or cloud sync.

## ADDED Requirements

### Requirement: Vault entry management
The tool SHALL allow users to create, view, edit, and delete vault entries of three types: login (with URL/username/password), secure note (arbitrary text), and TOTP (Base32 secret). Entry metadata (title, URL, username, tags, notes) SHALL be user-visible in a list-detail layout; the secret field SHALL be hidden by default and revealed only on explicit user action.

#### Scenario: Creating a login entry
- **WHEN** user creates a new entry with type "login", title, URL, username, and password
- **THEN** the entry is persisted in the encrypted vault and appears in the entry list under its assigned tags

#### Scenario: Creating a secure note entry
- **WHEN** user creates a new entry with type "note" and multi-line text content
- **THEN** the content is stored in the encrypted vault and displayed only after explicit reveal action

#### Scenario: Deleting an entry
- **WHEN** user deletes an entry after confirmation
- **THEN** the entry is removed from the vault and the encrypted store is rewritten without it

#### Scenario: Organizing entries with tags
- **WHEN** user assigns one or more tags to entries
- **THEN** the sidebar shows per-tag counts and filtering by a tag shows only matching entries

### Requirement: Entry search
The tool SHALL filter entries in real time by title, username, or URL substring match (case-insensitive), scoped to the currently selected tag filter.

#### Scenario: Searching by title substring
- **WHEN** user types a query in the search field
- **THEN** only entries whose title, username, or URL contain the query (case-insensitive) are shown

### Requirement: Secret reveal and clipboard hygiene
The tool SHALL allow copying a secret to the system clipboard and SHALL automatically clear the clipboard after a configurable delay (default 20 seconds; options 10/20/30/60 seconds or disabled). The secret SHALL be masked in the UI until the user explicitly reveals it.

#### Scenario: Copy secret with auto-clear
- **WHEN** user copies a secret to the clipboard
- **THEN** the secret is available for pasting, and after the configured delay the clipboard is automatically cleared

#### Scenario: Revealing a secret
- **WHEN** user clicks the reveal action on a masked secret
- **THEN** the secret is shown in plaintext until the user hides it again or navigates away

### Requirement: Password generator
The tool SHALL generate random passwords using a cryptographically secure random source, with user-controlled length (8–128), character-set toggles (uppercase, lowercase, digits, symbols), an option to exclude visually ambiguous characters, and a passphrase mode using a word list with configurable word count, separator, and optional digit suffix. Generated passwords SHALL be immediately usable as a new entry's password or copyable to the clipboard.

#### Scenario: Generating a random password
- **WHEN** user requests a random password with length 20 and all character sets enabled
- **THEN** a 20-character password containing at least one character from each enabled set is produced

#### Scenario: Generating a passphrase
- **WHEN** user selects passphrase mode with 5 words and a hyphen separator
- **THEN** a passphrase of 5 dictionary words joined by hyphens is produced

#### Scenario: Excluding ambiguous characters
- **WHEN** the "exclude ambiguous characters" option is enabled
- **THEN** generated passwords contain none of the characters `Il1O0o`

### Requirement: TOTP two-factor codes
The tool SHALL compute RFC 6238 time-based one-time passwords (6 digits, 30-second period, HMAC-SHA1) from a Base32 secret stored in a TOTP entry, tolerate clock drift of ±1 period, and display a live countdown of seconds remaining in the current period. Entries whose secret is a valid `otpauth://` URI SHALL be parsed automatically for secret, issuer, and digits parameters.

#### Scenario: Computing a valid TOTP code
- **WHEN** a TOTP entry holds a Base32 secret and the current time is within a 30-second period
- **THEN** the displayed 6-digit code matches the RFC 6238 expected value for that secret and time

#### Scenario: Live countdown display
- **WHEN** a TOTP entry is selected
- **THEN** the remaining seconds until code rotation are displayed and update in real time

#### Scenario: Importing an otpauth URI
- **WHEN** user pastes an `otpauth://totp/...` URI into the secret field
- **THEN** the secret, issuer label, and digit count are extracted and populated automatically

### Requirement: Password health report
The tool SHALL provide an on-demand health report covering: password strength scores (zxcvbn-style, computed locally), duplicate password detection across entries, and password age flagging for entries older than 180 days. The report SHALL list affected entries with actionable navigation.

#### Scenario: Running a health audit
- **WHEN** user requests a health report
- **THEN** the report shows counts of weak, duplicate, and aged passwords, and lists each affected entry by title

#### Scenario: Navigating from report to entry
- **WHEN** user clicks an entry listed in the health report
- **THEN** the detail view navigates to that entry

### Requirement: Opt-in breach checking
The tool SHALL offer a per-entry "check breach" action that queries a k-anonymity breach API using only the first 8 hexadecimal characters of the secret's SHA-1 hash. Breach checking SHALL be opt-in per query (never automatic), and the full secret SHALL never leave the device.

#### Scenario: Checking an entry for breach exposure
- **WHEN** user clicks "check breach" on a login entry with network available
- **THEN** only the SHA-1 prefix is transmitted, and the UI shows whether the password appeared in known breaches

#### Scenario: No automatic breach queries
- **WHEN** the health report is generated
- **THEN** no network request is made as part of the report

### Requirement: Legacy migration wizard
The tool SHALL, on first launch, detect the legacy `.secrets.dat` obfuscated store and present a migration wizard that decrypts the legacy data, imports AI provider credentials into the new encrypted storage, and deletes the legacy file after successful migration. Until migration completes, the legacy file SHALL be preserved unchanged.

#### Scenario: First launch with legacy data present
- **WHEN** the password tool is first opened and a legacy `.secrets.dat` file exists
- **THEN** a migration wizard is offered, and legacy credentials are re-encrypted into the new store before the legacy file is deleted

#### Scenario: Migration failure preserves legacy data
- **WHEN** the migration fails partway (e.g. decrypt error)
- **THEN** the legacy file remains untouched and the user is informed the migration can be retried

### Requirement: DEK backup and restore
The tool SHALL allow the user to export a passphrase-encrypted copy of the vault's data-encryption key to a user-chosen file location, and to restore it on another machine by providing that passphrase. The exported file SHALL never contain vault plaintext.

#### Scenario: Exporting an encrypted DEK backup
- **WHEN** user chooses "export key backup", sets a passphrase, and picks a destination file
- **THEN** a passphrase-encrypted key backup file is written containing no vault plaintext

#### Scenario: Restoring on a new machine
- **WHEN** user provides a valid key backup file and its passphrase on a machine where the vault ciphertext exists
- **THEN** the vault becomes readable and entries are displayed

#### Scenario: Wrong passphrase rejected
- **WHEN** user provides an incorrect passphrase during restore
- **THEN** the restore fails with a clear error and vault data remains inaccessible but unharmed
