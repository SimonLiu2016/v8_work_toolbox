# private-media-player Specification

## Purpose
Provides a high-performance cross-format media player supporting both local and online video/audio streams, full playback controls, history tracking, favorites management, and private directory access.
## Requirements
### Requirement: Cross-format local and online media playback
The system SHALL play local media files and parsed online streams across popular formats (.mp4, .mkv, .mov, .webm, .flv, .ts, .mp3, .wav, .m4a) with hardware acceleration.

#### Scenario: Open local media file
- **WHEN** user selects or drops a local audio/video file into the player
- **THEN** player loads the media stream, displays video surface (for video) or audio waveform cover (for audio), and starts playback

#### Scenario: Stream parsed online video
- **WHEN** user initiates playback of a parsed online video URL
- **THEN** player streams the media using appropriate network headers without requiring full file download

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

### Requirement: Playback history and favorites persistence
The system SHALL store playback progress timestamps and user favorites in private local storage, enabling one-click resumption and organized media bookmarking.

#### Scenario: Resume from last played timestamp
- **WHEN** user opens a previously played video from the History list
- **THEN** player prompts or automatically resumes playback from the exact recorded timestamp

#### Scenario: Add to favorites
- **WHEN** user clicks the Star/Favorite button on an active or parsed video
- **THEN** system saves the item to the private Favorites collection with title, duration, and thumbnail

### Requirement: Private storage directory reveal in Finder
The system SHALL store private media in an application support folder and provide an explicit button to open the folder directly in macOS Finder.

#### Scenario: Open private directory in Finder
- **WHEN** user clicks the "Open Private Folder" button
- **THEN** system reveals and focuses the private media folder in macOS Finder

### Requirement: Playback state coordination with privacy lock
The system SHALL coordinate the media player playback state with the privacy security service to suppress auto-lock while playing and automatically pause playback when locked.

#### Scenario: Register playback inhibitor
- **WHEN** media playback starts or pauses
- **THEN** player controller notifies the privacy security service of its active playing state to inhibit or resume the idle countdown

#### Scenario: Respond to manual lock
- **WHEN** the privacy space is locked either manually or through timeout
- **THEN** the player immediately pauses audio/video playback to prevent unwanted sound emission while locked

### Requirement: Mount external subtitle files
The system SHALL permit users to select and mount external subtitle files (.srt, .vtt) directly during playback and associate them with the media item in playback history.

#### Scenario: Mount local subtitle file
- **WHEN** user clicks the Mount Subtitles button and selects a valid .srt or .vtt file
- **THEN** player parses the subtitle segments, displays them synchronized to the video timecode, sets subtitle visibility to active, and updates playback history

