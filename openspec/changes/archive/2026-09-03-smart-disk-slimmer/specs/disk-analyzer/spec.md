## Purpose

Provides tiered disk inspection, orphaned application remnant detection, multi-version runtime/IDE bloat management, and safe macOS Trash recycling.

## ADDED Requirements

### Requirement: Tiered on-demand disk scanning
The disk analyzer SHALL execute scanning in three staged tiers: Phase 1 Instant Scan for known heavy directories (< 3s), Phase 2 Runtime and IDE multi-version detection (< 10s), and Phase 3 full orphan detection in the background.

#### Scenario: Instant tier completion
- **WHEN** user initiates a disk scan
- **THEN** high-impact targets (Xcode DerivedData, top-level caches, large downloaded packages) display immediate reclaimable metrics within 3 seconds while background deep scans continue.

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
