## ADDED Requirements

### Requirement: Pre-scan privilege detection
The system SHALL inspect ownership and write permissions for detected candidate items during scanning, marking items owned by root or lacking write permissions as requiring administrator privileges, displaying a visible administrator badge in the UI, and ensuring they are not auto-selected by default.

#### Scenario: Marking root-owned candidate
- **WHEN** the scan discovers a directory owned by root (such as `uid == 0`)
- **THEN** the candidate item is marked as requiring administrator privileges, displays a "需管理员权限" badge in the UI, and defaults to unselected with caution safety rating.

## MODIFIED Requirements

### Requirement: Safe disposal via native macOS Trash
The cleanup action SHALL move selected files and directories to the macOS Trash via native macOS mechanisms, SHALL execute physical post-operation verification to ensure files no longer exist at their original paths, and MUST NOT report success or remove items from the UI if physical deletion failed due to permission or sandboxing restrictions. When failures occur, the system SHALL accurately diagnose the underlying cause (distinguishing Full Disk Access from root/administrator ownership) and provide an option for secure administrator-elevated recycling.

#### Scenario: Reversible cleanup execution
- **WHEN** user clicks Clean Selected Items
- **THEN** items that are verified as physically removed are deleted from the UI list and space metrics are updated.

#### Scenario: Physical verification on protected or sandboxed container paths
- **WHEN** a selected item (such as a sandbox directory in `~/Library/Containers`) fails to move to Trash due to lack of Full Disk Access
- **THEN** the system detects that the directory still exists physically, preserves the item in the UI candidate list, and displays an explicit error message prompting the user to grant Full Disk Access in macOS System Settings.

#### Scenario: Accurate failure diagnosis for root-owned items
- **WHEN** a selected item fails to move to Trash because it is owned by root or lacks user write permissions
- **THEN** the system displays a specific dialog indicating administrator privileges are required (without falsely prompting for Full Disk Access) and offers an "授权管理员清理" action alongside "在访达中显示".

#### Scenario: Administrator-elevated recycling
- **WHEN** user confirms "授权管理员清理" on root-owned items
- **THEN** the system validates paths against strict safety whitelists, invokes native macOS administrator authentication, reclaims or removes the target items, and physically verifies removal before clearing them from the UI.

#### Scenario: Sandboxed container payload fallback purge
- **WHEN** a selected item is a sandboxed container directory (`~/Library/Containers/*`) whose root directory is locked by macOS `containermanagerd`
- **THEN** the system falls back to deep payload purging (`cleanContainerPayload`), safe-recycling heavy non-symlink payload folders (`Data/Library/Caches`, `Application Support`, `WebKit`) with `followLinks: false` while strictly preserving user symlinks (`Desktop`, `Documents`, etc.), physically verifying disk space recovery, and removing the cleaned item once its payload drops below the orphan threshold.

#### Scenario: Partial failure reporting
- **WHEN** multiple items are selected and only a subset are successfully moved to Trash
- **THEN** the successfully removed items are cleared from the UI, while the failed items remain visible, and the user receives a detailed summary indicating which items failed.
