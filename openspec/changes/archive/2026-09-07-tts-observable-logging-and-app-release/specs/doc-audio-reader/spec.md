## ADDED Requirements

### Requirement: Observable TTS synthesis telemetry and diagnostic logging
The system SHALL record structured telemetry entries into AiLogger for every TTS synthesis request, successful response, and synthesis error, enabling real-time inspection in the in-app AI Log Viewer.

#### Scenario: Commercial AI TTS request logging
- **WHEN** user initiates playback using a commercial or system AI TTS provider
- **THEN** system logs a structured request entry in AiLogger with provider name, protocol, model, endpoint, voice, and text summary

#### Scenario: Synthesis response and duration logging
- **WHEN** a TTS synthesis request completes successfully
- **THEN** system logs an AiLogger response entry with status code, elapsed milliseconds, and byte size

#### Scenario: Synthesis error logging
- **WHEN** a TTS synthesis request encounters an HTTP or network failure
- **THEN** system logs an AiLogger error entry containing the exact failure reason and status code
