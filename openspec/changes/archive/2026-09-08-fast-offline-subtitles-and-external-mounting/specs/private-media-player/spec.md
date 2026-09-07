## MODIFIED Requirements

### Requirement: Comprehensive playback controls
The system SHALL provide intuitive controls including play/pause, seek scrub, volume adjustment, speed switching (0.5x to 3.0x), aspect ratio toggle, fullscreen mode, and default-off subtitle toggle.

#### Scenario: Speed adjustment
- **WHEN** user selects a playback rate from 0.5x to 3.0x
- **THEN** player immediately adjusts audio pitch-compensated playback rate in real-time

#### Scenario: Fullscreen presentation
- **WHEN** user triggers the fullscreen action
- **THEN** player expands to full display resolution with auto-hiding control overlays

#### Scenario: Subtitle visibility default
- **WHEN** a video or audio track is initially loaded
- **THEN** subtitle visibility SHALL default to off until explicitly toggled or mounted

## ADDED Requirements

### Requirement: Mount external subtitle files
The system SHALL permit users to select and mount external subtitle files (.srt, .vtt) directly during playback and associate them with the media item in playback history.

#### Scenario: Mount local subtitle file
- **WHEN** user clicks the Mount Subtitles button and selects a valid .srt or .vtt file
- **THEN** player parses the subtitle segments, displays them synchronized to the video timecode, sets subtitle visibility to active, and updates playback history
