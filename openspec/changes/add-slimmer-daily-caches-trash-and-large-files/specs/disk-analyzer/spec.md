## ADDED Requirements

### Requirement: System Trash detection and permanent empty

The system SHALL detect the current user's macOS Trash directory (`~/.Trash` and volume-level trashes), calculate total reclaimable size and item count during scanning, and present a dedicated Trash overview. The system SHALL provide a dedicated "Empty Trash" action with a mandatory confirmation modal dialog explicitly informing the user that emptying the trash is permanent and cannot be undone.

#### Scenario: Detecting macOS Trash metrics
- **WHEN** user initiates a disk scan
- **THEN** the system calculates the byte size and item count of `~/.Trash` and presents a prominent Trash summary card in the UI.

#### Scenario: Permanent empty requires explicit modal confirmation
- **WHEN** user clicks the "清空废纸篓" (Empty Trash) action
- **THEN** a modal dialog prompts for confirmation, displaying the exact byte size and warning that the operation is irreversible, requiring explicit confirmation before proceeding.

#### Scenario: Empty Trash execution via native system command
- **WHEN** user confirms emptying the trash
- **THEN** the system instructs macOS Finder via AppleScript or POSIX delete to empty the trash, re-checks the trash directory to confirm 0 items remain, and resets the UI Trash counter.

#### Scenario: Ordinary item recycling preserves reversibility
- **WHEN** user cleans regular candidate items (caches, build artifacts, etc.)
- **THEN** those items are moved to Trash (`NSWorkspace.shared.recycle`), and the Trash item counter and size increment accordingly without being permanently emptied.

### Requirement: Active application cache and system log detection

The system SHALL scan `~/Library/Caches` and sandboxed app caches (`~/Library/Containers/*/Data/Library/Caches`), dynamically mapping them to currently installed applications (`/Applications/*.app` and `~/Applications/*.app`) to identify active daily application caches. The system SHALL also scan `~/Library/Logs` for accumulated user-level system and application logs.

#### Scenario: Dynamic installed application cache matching
- **WHEN** the scan inspects `~/Library/Caches` and sandboxed container cache directories
- **THEN** directories corresponding to installed apps (e.g. WeChat, DingTalk, QQ Music) are displayed with their localized display names and categorized under daily application caches rather than orphan remnants.

#### Scenario: Web browser cache discovery
- **WHEN** the scan detects cache directories for supported web browsers (Google Chrome, Microsoft Edge, Safari, Firefox, Brave)
- **THEN** browser cache items are classified under the daily/system cache category with a "safe" safety rating and auto-selected by default.

#### Scenario: User-level system log scanning
- **WHEN** the scan inspects `~/Library/Logs`
- **THEN** accumulated crash dumps and application execution logs exceeding 10MB are surfaced with a "safe" safety rating and auto-selected by default.

#### Scenario: Safety rating and selection differentiation for communication tools
- **WHEN** the scan identifies caches from messaging and communication applications (such as WeChat or DingTalk)
- **THEN** the items default to unselected with a "caution" safety rating, noting that clearing caches may require reloading media thumbnails.

### Requirement: Installation package detection across user workspaces

The system SHALL detect discarded installation packages (`.dmg`, `.pkg`, `.iso`) across common user locations including `~/Downloads`, `~/Desktop`, and `~/Documents`, while strictly excluding developer source repositories and dependencies (`node_modules`, `.git`, `deps`).

#### Scenario: Package discovery and age-based selection
- **WHEN** installation packages are detected
- **THEN** packages modified more than 7 days ago are auto-selected by default, while packages modified within the last 7 days default to unselected.

#### Scenario: Reveal installation package in Finder
- **WHEN** user clicks the "在访达中显示" (Reveal in Finder) action on an installation package candidate
- **THEN** macOS Finder opens with the target file highlighted.

### Requirement: Large file discovery and ranking

The system SHALL discover standalone files exceeding a designated threshold (such as 100MB) across user data directories using macOS Spotlight metadata (`mdfind`) or targeted directory scans, presenting them in descending order of file size. The scan SHALL exclude application bundles (`.app`) and internal git repository object directories (`.git/objects`).

#### Scenario: Instant large file indexing and ranking
- **WHEN** the large file scan tier completes
- **THEN** files exceeding 100MB are listed in descending order of size, displaying their file name, containing folder, file size, last modified date, and category tag (such as disk image, video, archive, or data export).

#### Scenario: Conservative safety policy for large user files
- **WHEN** large files are surfaced in the scan results
- **THEN** all large file candidates default to unselected with a "caution" safety rating, requiring explicit user review before any disposal action.

#### Scenario: Reveal large file in Finder
- **WHEN** user clicks the "在访达中显示" (Reveal in Finder) action on any large file entry
- **THEN** macOS Finder opens with the target file selected.
