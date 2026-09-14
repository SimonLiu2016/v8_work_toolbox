# disk-analyzer Delta

## MODIFIED Requirements

### Requirement: Tiered on-demand disk scanning
The disk analyzer SHALL NOT trigger automatic scanning on component initialization or page load; it SHALL wait until the user explicitly initiates scanning, presenting an idle overview with live volume capacity before execution, and detecting Full Disk Access permission restrictions during scans. The tiered scan SHALL consist of four tiers, where the fourth tier scans project-tree build artifacts discovered via project-root detection rather than any unbounded whole-disk walk.

#### Scenario: Instant tier completion
- **WHEN** user explicitly clicks the start scanning button
- **THEN** high-impact targets (Xcode DerivedData, top-level caches, large downloaded packages) display immediate reclaimable metrics within 3 seconds while background deep scans continue.

#### Scenario: Idle initial presentation
- **WHEN** user navigates to the Smart Disk Slimmer tool or launches the application
- **THEN** no disk I/O scan is performed, and the UI displays the Macintosh HD volume overview and an explicit start scan trigger button.

#### Scenario: Full Disk Access permission restriction guidance
- **WHEN** the scan encounters `FileSystemException` with permission denied on protected directories (e.g. `~/Library/Containers`)
- **THEN** a warning banner is shown on the UI providing an action button to open macOS "System Settings > Privacy & Security > Full Disk Access".

#### Scenario: AI unconfigured guidance
- **WHEN** user triggers AI single or batch analysis and no AI provider is configured in `AiConfigStore`
- **THEN** a dialog informs the user and provides a button navigating directly to the AI Configuration workspace.

#### Scenario: Project artifact tier follows discovery, not a whole-disk walk
- **WHEN** the fourth tier starts
- **THEN** it scans only inside directories identified as project roots, and the number of scanned directory paths stays bounded by the discovery budget rather than growing with the total directory count of the user's home directory

### Requirement: Safe disposal via native macOS Trash
The cleanup action SHALL move selected files and directories to the macOS Trash via native macOS mechanisms, SHALL execute physical post-operation verification to ensure files no longer exist at their original paths, and MUST NOT report success or remove items from the UI if physical deletion failed due to permission or sandboxing restrictions. When failures occur, the system SHALL accurately diagnose the underlying cause (distinguishing Full Disk Access from root/administrator ownership) and provide an option for secure administrator-elevated recycling. Project build artifacts SHALL use the same Trash-based disposal and MUST NOT be removed with irreversible permanent deletion.

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

#### Scenario: Build artifact cleanup is reversible
- **WHEN** user cleans a selected project build artifact item
- **THEN** the artifact is moved to the macOS Trash and is recoverable from Trash, and the UI describes the operation as reversible rather than permanent

#### Scenario: No permanent deletion path
- **WHEN** the user selects only project build artifacts and confirms cleanup
- **THEN** the system performs no irreversible `delete(recursive: true)` style removal for those items

## ADDED Requirements

### Requirement: Project build artifact discovery with manifest gating

The slimmer SHALL discover build artifacts inside project trees as a fourth scan tier. The scan MUST operate in two layers: a shallow manifest-discovery layer that identifies project roots by build-manifest signals (`.git`, `package.json`, `pubspec.yaml`, `build.gradle`, `build.gradle.kts`, `Podfile`, `CMakeLists.txt`) within a bounded depth of the user's home directory, and a pruned artifact-collection layer that only walks inside identified project roots. Manifest gating applies to any other signal as well: a directory is a valid candidate only when it sits inside an identified project root. Artifacts MUST NOT be discovered by a whole-disk walk of the home directory.

#### Scenario: Project artifact tier surfaces project-tree artifacts
- **WHEN** user explicitly starts a scan and the fourth tier completes
- **THEN** project-tree build artifacts (`node_modules`, `build`, `dist`, `.gradle`, `.dart_tool`, `.git` 无关的产物目录等) are listed as reclaimable candidates and are grouped under a project-build-artifact category distinct from global shared caches

#### Scenario: Manifest gating excludes name collisions outside project roots
- **WHEN** the home directory contains a `node_modules` directory that is not inside any directory identified as a project root (for example a stray top-level `~/node_modules` next to a `package-lock.json`)
- **THEN** that directory does not appear as a cleanup candidate

#### Scenario: The home directory itself is never a project root
- **WHEN** a build-manifest signal exists directly in the user's home directory (for example a stray `~/package.json`)
- **THEN** the home directory itself is not reported as a project root, and the other project roots discovered beneath it are all preserved rather than being absorbed by it

#### Scenario: Discovery budget is explicit, never silent
- **WHEN** a project root exceeds its per-root time budget or its artifact-count budget during collection
- **THEN** the resulting item is marked as "扫描超时 / 未完整" with the discovered portion still shown, and the system does not silently omit the remainder

#### Scenario: Watchlist supplements automatic discovery
- **WHEN** user adds an extra project root through the settings retained from the previous build-artifact cleaner
- **THEN** artifacts inside that root are discovered and aggregated alongside automatically discovered roots, without requiring the root to have a recognized build manifest

### Requirement: Artifact category separation between global and project scopes

The system SHALL present global shared development caches (Xcode DerivedData, Gradle caches, CocoaPods cache) and per-project build artifacts as two separate categories, so a user can filter them independently. The category descriptions MUST make the scope difference explicit — global caches are shared across all projects and safe to delete wholesale, while project artifacts live inside individual project trees.

#### Scenario: Categories are independently filterable
- **WHEN** user selects the project build artifacts category filter chip
- **THEN** only project-tree artifact items are shown, and global shared cache items (DerivedData, Gradle cache, CocoaPods cache) are excluded

#### Scenario: Category descriptions distinguish the two scopes
- **WHEN** user inspects the label and description of both the global build cache and the project artifact categories
- **THEN** the descriptions state that one is a cross-project shared cache and the other is per-project, so the two are not conflated

### Requirement: Project-root aggregation and technology-stack grouping

Each identified project root MUST be presented as a single aggregated candidate item; the item's subtitle MUST show the total number of artifact directories inside that root plus a per-technology composition summary (for example "23 个产物目录 · node_modules ×5 / build ×8"). The item MUST be expandable to reveal the per-directory detail (path and size). Only roots with at least one artifact hit and a total size of at least 10 MB are presented in the list. List rows MUST be grouped by technology stack (for example Flutter/Dart, Node, Gradle/Android), where each group row shows the root count and aggregated size, and expanding a group reveals the per-root items.

#### Scenario: Aggregation prevents list explosion
- **WHEN** a machine contains several hundred identified project roots
- **THEN** the candidate list contains one item per qualifying root rather than one row per matched artifact directory

#### Scenario: Composition summary and expandable detail
- **WHEN** user expands an aggregated project root item
- **THEN** the user sees the individual artifact directories inside that root with their paths and sizes

#### Scenario: Threshold filters small roots
- **WHEN** a project root contains artifact directories whose combined size is below 10 MB
- **THEN** it is not shown in the list, and the aggregated freed-space total excludes it

#### Scenario: Technology-stack grouping rows
- **WHEN** user views the project artifact results after the fourth tier completes
- **THEN** results are grouped by technology stack, each group showing the number of project roots and the aggregated reclaimable size
