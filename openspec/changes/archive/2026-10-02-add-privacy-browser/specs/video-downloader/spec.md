# video-downloader Delta Specification
# Change: add-privacy-browser

## Purpose
Delta spec capturing additions to the `video-downloader` capability introduced by the `add-privacy-browser` change.

## ADDED Requirements

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
