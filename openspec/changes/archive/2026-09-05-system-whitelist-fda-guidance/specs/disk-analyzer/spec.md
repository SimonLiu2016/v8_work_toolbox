## MODIFIED Requirements

### Requirement: Tiered on-demand disk scanning
The disk analyzer SHALL NOT trigger automatic scanning on component initialization or page load; it SHALL wait until the user explicitly initiates scanning, presenting an idle overview with live volume capacity before execution, and detecting Full Disk Access permission restrictions during scans.

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
