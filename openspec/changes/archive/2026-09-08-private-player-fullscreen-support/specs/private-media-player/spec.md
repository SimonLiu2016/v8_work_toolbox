## MODIFIED Requirements

### Requirement: Comprehensive playback controls
The system SHALL provide intuitive controls including play/pause, seek scrub, volume adjustment, speed switching (0.5x to 3.0x), aspect ratio toggle, fullscreen mode, and default-off subtitle toggle, ensuring continuous subtitle synchronization during seeking.

#### Scenario: Speed adjustment
- **WHEN** user selects a playback rate from 0.5x to 3.0x
- **THEN** player immediately adjusts audio pitch-compensated playback rate in real-time

#### Scenario: Fullscreen presentation
- **WHEN** user triggers the fullscreen action via control bar button, double-clicking video, or pressing `F` / `Enter`
- **THEN** player expands to full display resolution with auto-hiding control overlays and coordinates with macOS native window fullscreen

#### Scenario: Subtitle visibility default
- **WHEN** a video or audio track is initially loaded
- **THEN** subtitle visibility SHALL default to off until explicitly toggled or mounted

#### Scenario: Seek scrub retains subtitle synchronization
- **WHEN** user scrubs or seeks playback position via mouse along the timeline
- **THEN** player immediately evaluates and renders the subtitle matching the new timestamp across the entire video duration without losing subtitle tracking

## ADDED Requirements

### Requirement: Fullscreen mouse and keyboard shortcuts
The system SHALL support standard desktop keyboard and mouse shortcut interactions to manage playback and toggle fullscreen presentation.

#### Scenario: Double-click to toggle fullscreen
- **WHEN** user double-clicks anywhere on the active video viewport
- **THEN** the system toggles between standard embedded mode and fullscreen mode

#### Scenario: Keyboard shortcut fullscreen toggle
- **WHEN** user presses `F` or `Enter` while focused on the video player
- **THEN** the system toggles fullscreen presentation

#### Scenario: Escape key to exit fullscreen
- **WHEN** user presses `Escape` while the player is in fullscreen mode
- **THEN** the player immediately exits fullscreen mode and restores the standard embedded view

#### Scenario: Playback control shortcuts
- **WHEN** user presses `Space` or arrow keys (`Left` / `Right`) while focused on the player
- **THEN** `Space` toggles play/pause, and `Left`/`Right` jumps backward/forward 10 seconds without disrupting subtitle synchronization
