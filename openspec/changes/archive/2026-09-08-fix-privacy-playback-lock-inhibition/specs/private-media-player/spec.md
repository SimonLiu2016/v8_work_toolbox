## ADDED Requirements

### Requirement: Playback state coordination with privacy lock
The system SHALL coordinate the media player playback state with the privacy security service to suppress auto-lock while playing and automatically pause playback when locked.

#### Scenario: Register playback inhibitor
- **WHEN** media playback starts or pauses
- **THEN** player controller notifies the privacy security service of its active playing state to inhibit or resume the idle countdown

#### Scenario: Respond to manual lock
- **WHEN** the privacy space is locked either manually or through timeout
- **THEN** the player immediately pauses audio/video playback to prevent unwanted sound emission while locked
