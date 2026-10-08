# private-browser/video-enhancer Specification

## Purpose
Detects video elements in the browser's active page and presents an enhancement toolbar with download, cache-play, favorite, and subtitle actions.

## ADDED Requirements

### Requirement: Video detection
The system SHALL inject a WKUserScript into each page load to detect `<video>` elements after page load and on DOM mutation. For known platforms (YouTube, Bilibili, MissAV, PornHub, jav.sb, 91porn, pornlulu), the system SHALL additionally detect when a video starts playing (via the `play` event), even if the element was present before page load completed.

#### Scenario: Generic page with a video element
- **WHEN** a page finishes loading and contains one or more `<video>` elements
- **THEN** the injected script detects the presence of a video, notifies the native layer, and the enhancement toolbar becomes visible

#### Scenario: Video dynamically added to DOM
- **WHEN** a `<video>` element is added to the page DOM after initial load (e.g. via a JavaScript-driven player initialization)
- **THEN** the MutationObserver in the injected script detects the new element, notifies the native layer, and the enhancement toolbar appears

#### Scenario: Known-platform play event detection
- **WHEN** the user presses play on a YouTube, Bilibili, MissAV, PornHub, jav.sb, 91porn, or pornlulu video player
- **THEN** the injected script captures the `play` event on the detected video element, confirms the platform match, and ensures the native enhancement toolbar is displayed even if the element was present before page load completed

#### Scenario: Page with no video elements
- **WHEN** a page finishes loading and contains no `<video>` elements
- **THEN** the enhancement toolbar remains hidden and no video-enhancer UI is shown

### Requirement: Enhancement toolbar
When a video is detected, a native floating toolbar SHALL appear anchored to the browser chrome (not injected into the page DOM) with four buttons: Download, Cache & Play, Favorite, and Subtitles. The toolbar SHALL remain visible while the page contains an active video element.

#### Scenario: Toolbar appears on video detection
- **WHEN** the native layer receives a video-detected notification from the injected script
- **THEN** the native enhancement toolbar slides into view above the browser's address bar area, displaying Download, Cache & Play, Favorite, and Subtitles buttons

#### Scenario: Toolbar hides when video is removed
- **WHEN** the `<video>` element is removed from the DOM or the user navigates to a new page with no video
- **THEN** the native enhancement toolbar hides automatically

#### Scenario: Toolbar does not affect page layout
- **WHEN** the toolbar is visible
- **THEN** it is rendered as a native macOS overlay view, not injected into the WKWebView's DOM, so it does not alter page scroll behavior, z-index, or any page element positioning

### Requirement: Download action
Clicking the Download button SHALL trigger a yt-dlp download task for the current page URL, saving the output to the private media directory via the existing download queue.

#### Scenario: Download initiated from toolbar
- **WHEN** the user clicks the "Download" button on the enhancement toolbar
- **THEN** the system enqueues a yt-dlp download task for the current tab's URL in the download queue, and the Download button shows a loading/queued state indicator

#### Scenario: Download task added to queue
- **WHEN** the download task is enqueued
- **THEN** it appears in the video downloader's task list with source labeled "Browser", and real-time progress is reported back to the browser toolbar button

#### Scenario: Download fails due to unsupported URL
- **WHEN** yt-dlp cannot parse or download the current page URL
- **THEN** the toolbar download button returns to its idle state and a brief error toast is shown to the user with the failure reason

### Requirement: Cache & Play action
Clicking the Cache & Play button SHALL trigger a yt-dlp download for the current page URL. Once the download completes, the downloaded file SHALL automatically open in the private media player.

#### Scenario: Cache & Play initiated
- **WHEN** the user clicks "Cache & Play" on the enhancement toolbar
- **THEN** the system enqueues a yt-dlp download task with the intent flag `openOnComplete`, and the button shows a download-progress indicator

#### Scenario: Auto-open on download completion
- **WHEN** the download task with `openOnComplete` flag finishes successfully
- **THEN** the system automatically opens the downloaded file in the private media player, starting playback from the beginning

#### Scenario: Cache & Play with player already open
- **WHEN** the private media player is already displaying another file and Cache & Play completes
- **THEN** the player switches to the newly downloaded file, prompting the user to confirm if they want to interrupt current playback

### Requirement: Favorite action
Clicking the Favorite button SHALL save the current page's video metadata (title, URL, platform, thumbnail via og:image or favicon) to the private video library and trigger automatic AI tagging.

#### Scenario: Favorite current page video
- **WHEN** the user clicks "Favorite" on the enhancement toolbar
- **THEN** the system reads the page's title, URL, og:image (or falls back to favicon), and detects the platform; creates a VideoBookmark entry in the private video library; and the Favorite button changes to a filled/highlighted state

#### Scenario: Thumbnail cached locally
- **WHEN** the VideoBookmark is created
- **THEN** the system downloads the og:image (or favicon) and stores it as a local file, referencing the local path in the `thumbnail_path` field of the bookmark

#### Scenario: AI tagging triggered on favorite
- **WHEN** a VideoBookmark is successfully saved
- **THEN** the system automatically submits the title, URL, and platform to the AI library assistant for smart tagging; tags are applied to the bookmark once the AI response is received

#### Scenario: Duplicate favorite attempt
- **WHEN** the user clicks "Favorite" on a page whose URL is already in the video library
- **THEN** the system shows a brief toast indicating the video is already saved and does not create a duplicate entry

### Requirement: Subtitle action
Clicking the Subtitles button SHALL open a subtitle panel offering two options: (a) Fast Extract — use yt-dlp to pull native or auto-generated subtitles from the page URL; (b) AI Generate — use the AI STT pipeline on the video's audio.

#### Scenario: Open subtitle panel
- **WHEN** the user clicks "Subtitles" on the enhancement toolbar
- **THEN** a panel or popover appears presenting two options: "Fast Extract" and "AI Generate"

#### Scenario: Fast Extract subtitle
- **WHEN** the user selects "Fast Extract" from the subtitle panel
- **THEN** the system invokes yt-dlp with subtitle extraction flags for the current page URL, retrieves the subtitle file (VTT or SRT format), parses it into {start, end, text} segments, and mounts it to the browser subtitle overlay

#### Scenario: Fast Extract finds no subtitles
- **WHEN** yt-dlp reports no native or auto-generated subtitles for the current URL
- **THEN** the system shows an informational message in the panel indicating no subtitles were found and suggests using AI Generate instead

#### Scenario: AI Generate subtitle
- **WHEN** the user selects "AI Generate" from the subtitle panel
- **THEN** the system routes the current page's video audio through the AI STT pipeline; upon completion, the resulting subtitle segments are mounted to the browser subtitle overlay and the overlay is enabled
