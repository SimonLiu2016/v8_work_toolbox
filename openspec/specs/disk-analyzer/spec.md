# disk-analyzer Specification

## Purpose
Provides tiered disk inspection, orphaned application remnant detection, multi-version runtime/IDE bloat management, and safe macOS Trash recycling.
## Requirements
### Requirement: Tiered on-demand disk scanning
The disk analyzer SHALL NOT trigger automatic scanning on component initialization or page load; it SHALL wait until the user explicitly initiates scanning, presenting an idle overview with live volume capacity before execution.

#### Scenario: Instant tier completion
- **WHEN** user explicitly clicks the start scanning button
- **THEN** high-impact targets (Xcode DerivedData, top-level caches, large downloaded packages) display immediate reclaimable metrics within 3 seconds while background deep scans continue.

#### Scenario: Idle initial presentation
- **WHEN** user navigates to the Smart Disk Slimmer tool or launches the application
- **THEN** no disk I/O scan is performed, and the UI displays the Macintosh HD volume overview and an explicit start scan trigger button.

### Requirement: Orphaned app remnant detection
The analyzer SHALL match directories in `~/Library/Application Support`, `~/Library/Caches`, and `~/Library/Containers` against installed applications in `/Applications` and `~/Applications`, flagging items whose parent application bundle ID is absent.

#### Scenario: Identifying uninstalled software remnants
- **WHEN** user inspects the Application Remnants section
- **THEN** folders belonging to removed apps are highlighted with estimated size, last modified date, and flagged as recommended for removal.

### Requirement: Multi-version runtime and IDE management
The system SHALL detect parallel installations and historical upgrade versions of development environments (Python, Node.js, JDK) and IDEs (JetBrains products, Android Studio), displaying individual version sizes and allowing granular removal of obsolete versions.

#### Scenario: Detecting obsolete JetBrains versions
- **WHEN** the scan finds IntelliJ IDEA configuration and cache folders across multiple release years (e.g. 2022.3, 2023.2, 2024.2)
- **THEN** older unused versions are grouped and pre-selected for cleanup while preserving the most recent active version.

### Requirement: Safe disposal via native macOS Trash
The cleanup action SHALL move selected files and directories to the macOS Trash via `NSWorkspace.shared.recycle` rather than executing irreversible physical deletion.

#### Scenario: Reversible cleanup execution
- **WHEN** user clicks Clean Selected Items
- **THEN** the items are moved to the system Trash, allowing native Put Back restoration if needed, and UI updates free space metrics.

