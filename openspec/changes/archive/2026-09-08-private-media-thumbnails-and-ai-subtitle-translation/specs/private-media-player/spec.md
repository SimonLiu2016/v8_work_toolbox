## ADDED Requirements

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
