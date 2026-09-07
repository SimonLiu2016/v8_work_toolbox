## ADDED Requirements

### Requirement: Multi-tier fast subtitle extraction and offline generation
The system SHALL provide a multi-tier fast generation pipeline prioritizing instant native/embedded subtitle extraction before falling back to single-pass audio transcription.

#### Scenario: Extract online native or auto subtitles
- **WHEN** user requests fast subtitle generation for a supported online URL (e.g. Bilibili or YouTube)
- **THEN** system uses yt-dlp to extract available native or auto-generated subtitles within seconds, saving and mounting the resulting SRT file

#### Scenario: Extract embedded soft subtitles from local file
- **WHEN** user requests fast subtitle generation for a local video containing embedded subtitle tracks
- **THEN** system uses ffmpeg to extract the primary subtitle track to an SRT file in less than 2 seconds and mounts it immediately

#### Scenario: Fallback to single-pass full audio transcription
- **WHEN** no native or embedded subtitle tracks exist on the video
- **THEN** system compresses audio into 32kbps mono MP3 and performs direct single-pass transcription, avoiding multi-chunk serial upload delays
