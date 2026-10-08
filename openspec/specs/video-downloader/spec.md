# video-downloader Specification

## Purpose
Provides online video metadata parsing, stream resolution, and single/batch download scheduling for Bilibili, YouTube, Pornhub, pornlulu.com, MissAV, and generic streaming links.
## Requirements
### Requirement: Multi-platform online video parsing
The system SHALL parse video metadata, available qualities, and playable stream URLs from Bilibili, YouTube, Pornhub, pornlulu.com, MissAV, and standard video links utilizing `yt-dlp`.

#### Scenario: Parse Bilibili video URL
- **WHEN** user inputs a Bilibili BV URL and clicks Parse
- **THEN** system extracts video title, author, duration, cover image, and available resolutions

#### Scenario: Parse YouTube video URL with challenge handling
- **WHEN** user inputs a YouTube video URL
- **THEN** system resolves streams utilizing remote component JS challenge handling without falling back to audio-only streams

#### Scenario: Parse MissAV and PornLulu streaming URLs
- **WHEN** user inputs a MissAV or pornlulu.com video URL
- **THEN** system applies impersonation extraction arguments to retrieve HLS m3u8 playlist streams and metadata

### Requirement: Single and batch download queue management
The system SHALL allow users to queue single or multiple video URLs for sequential or concurrent background downloading with real-time progress metrics.

#### Scenario: Single video download with quality selection
- **WHEN** user selects a desired quality (e.g. 1080P) and confirms download
- **THEN** system downloads video and audio tracks, merges them into MP4 using ffmpeg, and saves the result to the private media directory

#### Scenario: Multi-link batch download queue
- **WHEN** user inputs multiple URLs in batch mode and starts download
- **THEN** system queues tasks with controlled concurrency, displaying progress percentage, download speed, and ETA for each item

#### Scenario: Direct play from download list
- **WHEN** a download task finishes successfully
- **THEN** system shows a "Play" action allowing the user to immediately open the downloaded file in the private player

### Requirement: Browser toolbar download trigger
The download queue SHALL accept tasks initiated from the private browser's video enhancement toolbar. Each such task SHALL carry a `source = "browser"` field in the task record. Real-time download progress SHALL be surfaced back to the browser's enhancement toolbar button for the duration of the task.

#### Scenario: Download task enqueued from browser toolbar
- **WHEN** the user clicks the "Download" button on the video enhancement toolbar in the private browser
- **THEN** the video downloader enqueues a new download task for the current page URL with `source = "browser"` recorded on the task record, and the task appears in the downloader's queue list with the source label "Browser"

#### Scenario: Progress fed back to browser toolbar
- **WHEN** a browser-triggered download task is active and making progress
- **THEN** the video enhancement toolbar's Download button displays a real-time progress indicator (e.g. a circular progress ring or percentage label) reflecting the current download percentage reported by the yt-dlp process

#### Scenario: Download completes — toolbar button resets
- **WHEN** a browser-triggered download task completes successfully
- **THEN** the Download button on the enhancement toolbar returns to its idle state, and a brief success toast is shown in the browser chrome indicating the file has been saved to the private media directory

#### Scenario: Download fails — toolbar reflects error
- **WHEN** a browser-triggered download task fails (e.g. yt-dlp error, network timeout)
- **THEN** the Download button on the enhancement toolbar transitions to an error state (e.g. red icon or error badge), and tapping/clicking it shows the failure reason with an option to retry

#### Scenario: Browser task visible in downloader queue UI
- **WHEN** the user navigates to the video downloader's main UI while a browser-triggered task is running
- **THEN** the task appears in the queue list with source label "Browser", the current page URL as the task title, and the same progress metrics as any other queued download

