## MODIFIED Requirements

### Requirement: Tiered on-demand disk scanning
The disk analyzer SHALL NOT trigger automatic scanning on component initialization or page load; it SHALL wait until the user explicitly initiates scanning, presenting an idle overview with live volume capacity before execution.

#### Scenario: Instant tier completion
- **WHEN** user explicitly clicks the start scanning button
- **THEN** high-impact targets (Xcode DerivedData, top-level caches, large downloaded packages) display immediate reclaimable metrics within 3 seconds while background deep scans continue.

#### Scenario: Idle initial presentation
- **WHEN** user navigates to the Smart Disk Slimmer tool or launches the application
- **THEN** no disk I/O scan is performed, and the UI displays the Macintosh HD volume overview and an explicit start scan trigger button.
