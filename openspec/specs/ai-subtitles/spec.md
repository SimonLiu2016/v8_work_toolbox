# ai-subtitles Specification

## Purpose
Provides AI-powered speech-to-text subtitle generation, dual-mode interval or full transcription, real-time synchronized overlay rendering, and subtitle file export.
## Requirements
### Requirement: Integrated AI STT slot transcription
The system SHALL transcribe audio extracted from local media or online streams into timestamped subtitle segments utilizing the global AI STT slot binding.

#### Scenario: Audio extraction and pre-processing
- **WHEN** user initiates AI subtitle generation for a video
- **THEN** system extracts lightweight 16kHz mono audio using ffmpeg to meet STT payload constraints before dispatching API requests

#### Scenario: STT transcription with segment timestamps
- **WHEN** audio is submitted to the configured AI STT provider
- **THEN** system requests verbose JSON with segment timestamps (`start`, `end`, `text`) and parses them into structured subtitle lines

### Requirement: Dual-mode subtitle generation
The system SHALL support on-demand interval generation centered around the current playback timestamp, as well as full-video background transcription.

#### Scenario: On-demand playback interval generation
- **WHEN** user chooses on-demand subtitle generation during playback
- **THEN** system extracts and transcribes only the audio segment corresponding to the current playback window (e.g. within 10 minutes), displaying results within seconds

#### Scenario: Full-video background batch generation
- **WHEN** user chooses full-length subtitle generation
- **THEN** system splits long audio into sequenced chunks, transcribes them sequentially in background, and merges the segments with continuous timestamps

### Requirement: Real-time subtitle overlay and export
The system SHALL render synchronized subtitles over the video surface during playback, provide a display toggle switch, and allow exporting subtitles as .srt or .vtt files.

#### Scenario: Synchronized subtitle display with toggle
- **WHEN** playback progresses and subtitle switch is enabled
- **THEN** player dynamically highlights and renders the subtitle matching current playback position over a semi-transparent background

#### Scenario: Export and save subtitle
- **WHEN** user clicks the "Save Subtitle" button
- **THEN** system exports the generated subtitle as a standard .srt file to the private media directory or chosen destination

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

