## MODIFIED Requirements

### Requirement: Comprehensive playback controls
The system SHALL provide intuitive controls including play/pause, seek scrub, volume adjustment, speed switching (0.5x to 3.0x), aspect ratio toggle, fullscreen mode, and default-off subtitle toggle, ensuring continuous subtitle synchronization during seeking.

#### Scenario: Speed adjustment
- **WHEN** user selects a playback rate from 0.5x to 3.0x
- **THEN** player immediately adjusts audio pitch-compensated playback rate in real-time

#### Scenario: Fullscreen presentation
- **WHEN** user triggers the fullscreen action
- **THEN** player expands to full display resolution with auto-hiding control overlays

#### Scenario: Subtitle visibility default
- **WHEN** a video or audio track is initially loaded
- **THEN** subtitle visibility SHALL default to off until explicitly toggled or mounted

#### Scenario: Seek scrub retains subtitle synchronization
- **WHEN** user scrubs or seeks playback position via mouse along the timeline
- **THEN** player immediately evaluates and renders the subtitle matching the new timestamp across the entire video duration without losing subtitle tracking
