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
- **WHEN** user triggers the fullscreen action via control bar button, double-clicking video, or pressing `F` / `Enter`
- **THEN** player expands to full display resolution with auto-hiding control overlays and coordinates with macOS native window fullscreen

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

### Requirement: Local thumbnail management and list visualization
The system SHALL cache online poster thumbnails to private local storage, generate video screenshot frames for local media files, and display rounded thumbnail previews in the Download Tasks, Playback History, and Favorites lists.

#### Scenario: Cache online video poster
- **WHEN** online video information is parsed or added to download queue
- **THEN** system downloads the poster image to the private thumbnails directory and stores the local file path

#### Scenario: Capture local video screenshot frame
- **WHEN** a local video is downloaded or played without an existing thumbnail
- **THEN** system extracts a video frame screenshot using ffmpeg into the private thumbnails directory and associates it with the media record

#### Scenario: Render visual thumbnails in media lists
- **WHEN** user views Download Tasks, Playback History, or Favorites
- **THEN** each item renders a 64x44 rounded thumbnail image with graceful fallback to a media icon when unavailable

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

### Requirement: Extended browser-origin bookmark data model
The favorites system SHALL accept VideoBookmark entries originating from the private browser, which include additional fields: `source_url` (original web URL), `platform` (e.g. YouTube, MissAV), and `ai_summary`. These browser-origin entries SHALL be displayed alongside local file favorites, visually distinguished by a platform badge.

#### Scenario: Browser-origin bookmark appears in favorites list
- **WHEN** the user opens the private media player's Favorites view after having saved a video from the private browser
- **THEN** the browser-origin VideoBookmark appears in the list alongside local file favorites, displaying the cached thumbnail, title, platform badge (e.g. "YouTube", "MissAV"), and added_at timestamp

#### Scenario: Platform badge displayed on browser-origin entry
- **WHEN** a VideoBookmark with a non-nil `platform` field is rendered in the favorites list or detail view
- **THEN** a colored platform badge (using platform-specific branding color and abbreviated name) is overlaid on the thumbnail corner, distinguishing it from local file entries which have no badge

#### Scenario: Open browser-origin bookmark from favorites
- **WHEN** the user double-clicks or selects "Play" on a browser-origin VideoBookmark in the favorites list
- **THEN** the media player attempts to stream the `source_url` directly; if streaming fails or the URL is unavailable, the player presents an option to re-download via the browser's download queue

#### Scenario: AI summary visible in detail view
- **WHEN** the user opens the detail view of a browser-origin bookmark that has a non-empty `ai_summary` field
- **THEN** the `ai_summary` text is displayed in a dedicated "AI Summary" section within the detail panel, below the standard metadata fields

#### Scenario: Local file favorites unaffected
- **WHEN** the favorites list contains both local file entries and browser-origin VideoBookmark entries
- **THEN** local file favorites display without a platform badge and do not expose `source_url`, `platform`, or `ai_summary` fields; the two types coexist in the same list without layout or data conflicts

