## Purpose

Provides a secure, anonymous, desktop-optimized short drama theater experience inside the Privacy Space, featuring 16:9 widescreen playback, AES-128 cover decryption, mirror routing, local private watch history and favorites, and offline download integration.

## ADDED Requirements

### Requirement: Privacy Space tool registration and security lifecycle
The system SHALL register the Casual Short Drama tool under the Privacy Space category, accessible only after successful PIN verification, and SHALL immediately mute and pause active media playback whenever the Privacy Space locks.

#### Scenario: Tool access restricted by PIN lock
- **WHEN** user attempts to access the Casual Short Drama tool while Privacy Space is locked
- **THEN** system denies access and presents the 6-digit PIN entry lock view

#### Scenario: Auto-mute and pause on manual lock
- **WHEN** user clicks the lock button in the header while a short drama episode is actively playing
- **THEN** system immediately pauses the player, halts audio output, and clears active session visibility

#### Scenario: Auto-mute and pause on idle timeout
- **WHEN** Privacy Space enters idle timeout state
- **THEN** system automatically locks the space, pauses short drama playback, and requires PIN re-entry

### Requirement: Upstream short drama catalog, search, and mirror line routing
The system SHALL support browsing recommended, trending, and category-filtered short drama feeds, searching by keyword, and switching between configurable mirror lines.

#### Scenario: Loading recommended feed
- **WHEN** user opens the Casual Short Drama home view
- **THEN** system queries the upstream edge gateway and displays the initial paginated list of short drama cards with decrypted covers and titles

#### Scenario: Keyword search
- **WHEN** user inputs a search keyword and presses Enter or clicks Search
- **THEN** system retrieves matching short drama results and displays them in a grid view

#### Scenario: Mirror line switching
- **WHEN** user selects an alternative mirror line from the line settings dropdown
- **THEN** system verifies line connectivity, persists the selected origin locally, and routes subsequent requests through the new line

### Requirement: AES-128 cover decryption and local secure caching
The system SHALL automatically decrypt AES-128-CBC encrypted drama cover images using the static key and IV, and cache the decrypted image bytes in memory and private storage.

#### Scenario: Decrypting encrypted cover bytes
- **WHEN** system loads a drama card whose cover payload is encrypted with AES-128-CBC
- **THEN** system decrypts the ciphertext using static key `f5d965df75336270` and IV `97b60394abc2fbe1`, strips PKCS7 padding, and renders the valid image

#### Scenario: Serving cover from cache
- **WHEN** system requests a cover image that has already been decrypted in the current session
- **THEN** system retrieves the decrypted bytes directly from cache without redundant network or decryption operations

### Requirement: 16:9 desktop theater playback and controls
The system SHALL render the playback surface in a 16:9 desktop widescreen aspect ratio, centering the video stream with immersive ambient background fill, and supporting standard desktop keyboard shortcuts.

#### Scenario: 16:9 theater playback rendering
- **WHEN** user clicks on a drama card to start watching
- **THEN** system opens the theater view with a 16:9 container, displaying the video centered with blurred ambient background or pure black letterboxing

#### Scenario: Desktop keyboard shortcut controls
- **WHEN** user presses Space, Arrow keys, M, or F while focusing the theater view
- **THEN** system toggles play/pause (Space), seeks +/- 5 seconds (Left/Right), switches previous/next episode (Up/Down), toggles mute (M), or enters/exits fullscreen (F)

### Requirement: Episode selection drawer and continuous sequential playback
The system SHALL provide an episode drawer displaying all available episodes, highlighting the current playing episode, and automatically advancing to the next episode upon completion.

#### Scenario: Viewing and switching episodes
- **WHEN** user opens the episode selection drawer
- **THEN** system displays tabbed or paginated episode numbers, marking the currently playing episode and jumping to the selected episode upon click

#### Scenario: Auto-advance to next episode
- **WHEN** current episode reaches the end of its duration
- **THEN** system automatically fetches and begins playback of the next sequential episode in the series

### Requirement: Anonymous zero-tracking local favorites and watch history
The system SHALL operate in pure guest mode without requiring account registration or login, persisting user favorites and playback progress strictly in a local SQLite private database.

#### Scenario: Toggling drama favorite
- **WHEN** user clicks the favorite icon on a drama detail or player view
- **THEN** system toggles the favorite state and updates the local private database without transmitting user identifiers to remote servers

#### Scenario: Resuming playback progress
- **WHEN** user reopens a previously watched drama
- **THEN** system reads the last watched episode and timestamp from local storage and prompts or auto-resumes from that point

### Requirement: Offline download to private media library
The system SHALL allow users to queue drama episodes for offline download, saving stream segments into the isolated private storage directory for network-independent playback.

#### Scenario: Queuing episode for offline download
- **WHEN** user clicks the download button for one or multiple episodes
- **THEN** system registers download tasks with the private storage download manager and displays progress indicators until files are saved securely offline
