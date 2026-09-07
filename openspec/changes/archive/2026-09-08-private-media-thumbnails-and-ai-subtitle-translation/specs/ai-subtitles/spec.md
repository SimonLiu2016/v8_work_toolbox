## ADDED Requirements

### Requirement: Offline local video subtitle generation and AI Chinese translation
The system SHALL extract temporary audio from local downloaded videos, transcribe speech to text, and translate full subtitle files into Chinese using the global text LLM slot.

#### Scenario: Offline local video audio extraction and ASR
- **WHEN** user initiates subtitle generation on a local downloaded video
- **THEN** system extracts lightweight temporary audio and transcribes it into timestamped subtitle segments

#### Scenario: Full-track subtitle translation via text LLM
- **WHEN** subtitle translation is requested or enabled
- **THEN** system invokes the configured global text model slot in structured batches to translate subtitle segments into natural Chinese

#### Scenario: Bilingual or pure Chinese subtitle persistence and mount
- **WHEN** subtitle translation finishes
- **THEN** system writes a standard .srt file into the private subtitles directory, updates media history, and mounts it to the player
