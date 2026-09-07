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

