## MODIFIED Requirements

### Requirement: Privacy space session and auto-lock management
The system SHALL maintain unlock status strictly in memory during an active session and automatically lock the Privacy Space upon inactivity or manual request, while inhibiting auto-lock during active media playback.

#### Scenario: Manual quick lock
- **WHEN** user clicks the Lock button in the Privacy Space header
- **THEN** system immediately pauses any active media playback, clears the in-memory unlock state, and returns to the PIN lock screen

#### Scenario: Automatic lock on idle
- **WHEN** user remains inactive in Privacy Space for longer than the configured timeout (e.g. 5 minutes) and no media is actively playing
- **THEN** system automatically locks the Privacy Space and requires PIN re-entry

#### Scenario: Auto-lock inhibited during active playback
- **WHEN** media is actively playing in the Privacy Space even if the user provides no mouse or keyboard input for longer than the idle timeout
- **THEN** system suppresses the automatic lock and keeps the playback uninterrupted

#### Scenario: Activity timer reset on user interaction
- **WHEN** user moves the pointer, clicks, scrolls, or presses keys within the Privacy Space view
- **THEN** system refreshes the user activity timestamp to prevent premature idle locking
