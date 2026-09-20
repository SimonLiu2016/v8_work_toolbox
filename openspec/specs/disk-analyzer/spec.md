# disk-analyzer Specification

## Purpose
Provides tiered disk inspection, orphaned application remnant detection, multi-version runtime/IDE bloat management, and safe macOS Trash recycling.
## Requirements
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

### Requirement: Orphaned app remnant detection
The analyzer SHALL match directories in `~/Library/Application Support`, `~/Library/Caches`, and `~/Library/Containers` against installed applications in `/Applications` and `~/Applications` using multi-layered verification: Bundle ID exact match, known alias mapping, bidirectional substring match, and recency-based safety downgrade. Items not matching any layer SHALL default to "caution" safety rating, MUST NOT default to "safe".

#### Scenario: Identifying uninstalled software remnants
- **WHEN** user inspects the Application Remnants section
- **THEN** folders belonging to removed apps are highlighted with estimated size, last modified date, and flagged as recommended for removal.

#### Scenario: Active application not misidentified
- **WHEN** an Application Support directory belongs to an installed app whose .app name differs from the directory name (e.g., `Code` → `Visual Studio Code.app`)
- **THEN** the directory is matched via Bundle ID or alias mapping and excluded from orphan candidates.

#### Scenario: Recently modified directory safety downgrade
- **WHEN** an unmatched directory was modified within the last 30 days
- **THEN** its safety rating is downgraded to "caution" or "danger" based on recency, and it is not auto-selected for cleanup.

### Requirement: Multi-version runtime and IDE management
The system SHALL detect parallel installations and historical upgrade versions of development environments (Python, Node.js, JDK) and IDEs (JetBrains products, Android Studio), displaying individual version sizes with directory source labels (configuration vs cache) and allowing granular removal of obsolete versions.

#### Scenario: Detecting obsolete JetBrains versions
- **WHEN** the scan finds IntelliJ IDEA configuration and cache folders across multiple release years (e.g. 2022.3, 2023.2, 2024.2)
- **THEN** older unused versions are grouped and pre-selected for cleanup while preserving the most recent active version.

#### Scenario: JetBrains directory source disambiguation
- **WHEN** the scan finds both `~/Library/Application Support/JetBrains/IntelliJIdea2026.2` and `~/Library/Caches/JetBrains/IntelliJIdea2026.2`
- **THEN** each entry displays a source label in its title (e.g., "IntelliJIdea 2026.2（配置）" vs "IntelliJIdea 2026.2（缓存）") so the user can distinguish them.

### Requirement: Pre-scan privilege detection
The system SHALL inspect ownership and write permissions for detected candidate items during scanning, marking items owned by root or lacking write permissions as requiring administrator privileges, displaying a visible administrator badge in the UI, and ensuring they are not auto-selected by default.

#### Scenario: Marking root-owned candidate
- **WHEN** the scan discovers a directory owned by root (such as `uid == 0`)
- **THEN** the candidate item is marked as requiring administrator privileges, displays a "需管理员权限" badge in the UI, and defaults to unselected with caution safety rating.

### Requirement: Safe disposal via native macOS Trash
The cleanup action SHALL move selected files and directories to the macOS Trash via native macOS mechanisms, SHALL execute physical post-operation verification to ensure files no longer exist at their original paths, and MUST NOT report success or remove items from the UI if physical deletion failed due to permission or sandboxing restrictions. When failures occur, the system SHALL accurately diagnose the underlying cause (distinguishing Full Disk Access from root/administrator ownership) and provide an option for secure administrator-elevated recycling. Project build artifacts SHALL use the same Trash-based disposal and MUST NOT be removed with irreversible permanent deletion.

#### Scenario: Reversible cleanup execution
- **WHEN** user clicks Clean Selected Items
- **THEN** items that are verified as physically removed are deleted from the UI list and space metrics are updated.

#### Scenario: Physical verification on protected or sandboxed container paths
- **WHEN** a selected item (such as a sandbox directory in `~/Library/Containers`) fails to move to Trash due to lack of Full Disk Access
- **THEN** the system detects that the directory still exists physically, preserves the item in the UI candidate list, and displays an explicit error dialog with a clearly legible high-contrast "打开系统设置" button guiding the user to grant Full Disk Access in macOS System Settings.

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

### Requirement: Interactive cleanup selection
The cleanup candidate list SHALL support manual checkbox toggling for every item. The scan result list MUST be stored as a mutable collection, MUST NOT use `List.unmodifiable`.

#### Scenario: Manual checkbox toggle
- **WHEN** user clicks a checkbox on any cleanup candidate item
- **THEN** the item's selection state toggles immediately, and the total reclaimable size in the action button updates accordingly.

#### Scenario: User override persistence
- **WHEN** user manually deselects an item that was auto-selected as "safe to clean"
- **THEN** the deselection decision is persisted to configuration, and the item is automatically deselected on future scans.


### Requirement: Project build artifact discovery with manifest gating

The slimmer SHALL discover build artifacts inside project trees as a fourth scan tier. The scan MUST operate in two layers: a shallow manifest-discovery layer that identifies project roots by build-manifest signals (`.git`, `package.json`, `pubspec.yaml`, `build.gradle`, `build.gradle.kts`, `Podfile`, `CMakeLists.txt`, `go.mod`, `xcodeproj`, `pom.xml`, `Cargo.toml`) within a bounded depth of 5 from the user's home directory, and a pruned artifact-collection layer that only walks inside identified project roots. The discovery layer MUST prune package-manager cache directories (`.pub-cache`, `.npm`, `.yarn`, `.cache`, `.cargo`, `.rustup`, `.local`) which are download caches rather than user projects, and MUST prune `~/Applications` in this tier (application bundles are scanned by the orphaned-app tier, not by project-artifact discovery). Manifest gating applies to any other signal as well: a directory is a valid candidate only when it sits inside an identified project root. Artifacts MUST NOT be discovered by a whole-disk walk of the home directory.

The watchlist supplements automatic discovery but MUST NOT absorb it. When a watchlist entry contains automatically discovered project roots beneath it, the watchlist entry itself MUST be discarded and the discovered roots preserved. A watchlist entry is only itself a project root when no automatically discovered root lies beneath it. The watchlist MUST NOT function as a parent prefix that swallows nested roots.

#### Scenario: Project artifact tier surfaces project-tree artifacts
- **WHEN** user explicitly starts a scan and the fourth tier completes
- **THEN** project-tree build artifacts (`node_modules`, `build`, `dist`, `.gradle`, `.dart_tool`, `.git` 无关的产物目录等) are listed as reclaimable candidates and are grouped under a project-build-artifact category distinct from global shared caches

#### Scenario: Maven and Rust projects without .git are discovered
- **WHEN** a project root contains `pom.xml` or `Cargo.toml` but no `.git`
- **THEN** the root is identified as a project root and its `target` artifact is collected

#### Scenario: Package-manager cache directories are not project roots
- **WHEN** the home directory contains `.pub-cache` with thousands of `pubspec.yaml` files, `.npm` with thousands of `package.json` files, or `.cargo` with `Cargo.toml` files
- **THEN** these cache directories are pruned from discovery and do not contribute project roots

#### Scenario: Applications directory is not scanned for build artifacts
- **WHEN** the fourth tier runs
- **THEN** `~/Applications` is pruned from project-root discovery, but the orphaned-app-remnant tier (which inspects `~/Library/Application Support`, `~/Library/Caches`, and `~/Library/Containers`) is unaffected and still detects remnants of apps installed in `~/Applications`

#### Scenario: Manifest gating excludes name collisions outside project roots
- **WHEN** the home directory contains a `node_modules` directory that is not inside any directory identified as a project root (for example a stray top-level `~/node_modules` next to a `package-lock.json`)
- **THEN** that directory does not appear as a cleanup candidate

#### Scenario: The home directory itself is never a project root
- **WHEN** a build-manifest signal exists directly in the user's home directory (for example a stray `~/package.json`)
- **THEN** the home directory itself is not reported as a project root, and the other project roots discovered beneath it are all preserved rather than being absorbed by it

#### Scenario: Discovery budget is explicit, never silent
- **WHEN** a project root exceeds its per-root time budget or its artifact-count budget during collection
- **THEN** the resulting item is marked as "扫描超时 / 未完整" with the discovered portion still shown, and the system does not silently omit the remainder

#### Scenario: Watchlist supplements without absorbing discovered roots
- **WHEN** user adds an extra project root through the settings retained from the previous build-artifact cleaner, and that root contains automatically discovered project roots beneath it
- **THEN** the automatically discovered roots are each preserved as their own candidate items, the broad watchlist entry itself is not reported as a project root, and no discovered root is absorbed by the watchlist entry

#### Scenario: Watchlist entry is a root only when it has no discovered descendants
- **WHEN** user adds an extra project root that contains no automatically discovered project roots beneath it (for example a project lacking a recognized build manifest)
- **THEN** artifacts inside that root are discovered and aggregated, without requiring the root to have a recognized build manifest

### Requirement: Artifact category separation between global and project scopes

The system SHALL present global shared development caches (Xcode DerivedData, Gradle caches, CocoaPods cache) and per-project build artifacts as two separate categories, so a user can filter them independently. The category descriptions MUST make the scope difference explicit — global caches are shared across all projects and safe to delete wholesale, while project artifacts live inside individual project trees.

#### Scenario: Categories are independently filterable

- **WHEN** user selects the project build artifacts category filter chip
- **THEN** only project-tree artifact items are shown, and global shared cache items (DerivedData, Gradle cache, CocoaPods cache) are excluded

#### Scenario: Category descriptions distinguish the two scopes

- **WHEN** user inspects the label and description of both the global build cache and the project artifact categories
- **THEN** the descriptions state that one is a cross-project shared cache and the other is per-project, so the two are not conflated

### Requirement: Project-root aggregation and technology-stack grouping

Each identified project root MUST be presented as a single aggregated candidate item; the item's subtitle MUST show the total number of artifact directories inside that root plus a per-technology composition summary (for example "23 个产物目录 · node_modules ×5 / build ×8"). The item MUST be expandable to reveal the per-directory detail (path and size). Only roots with at least one artifact hit and a total size of at least 10 MB are presented in the list. List rows MUST be grouped by technology stack, and the grouping MUST include a Maven / Java group derived from the `pom.xml` signal, alongside the Flutter/Dart, Node, and Gradle/Android groups. Roots with no recognized manifest signal MUST fall into a clearly-labeled catch-all group rather than being silently omitted.

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

#### Scenario: Maven project is grouped under Maven / Java, not the catch-all group
- **WHEN** a project root contains `pom.xml` and a `target` artifact directory
- **THEN** the root is grouped under the Maven / Java group rather than the catch-all group, and the Maven / Java group is visible in the technology-stack filter chips

#### Scenario: Catch-all group is explicitly labeled
- **WHEN** a project root has artifact directories but no recognized manifest signal
- **THEN** it is grouped under an explicitly-labeled catch-all group, and is not silently omitted from the results
