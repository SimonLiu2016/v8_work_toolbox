# privacy-space Specification

## Purpose
Provides a secure privacy space with 6-digit numeric PIN protection, session unlock management, automatic locking, and complete tool/history isolation from the general workspace.
## Requirements
### Requirement: 6-digit numeric PIN security protection
The system SHALL require the user to configure and verify a 6-digit numeric PIN code before granting access to any tools, history, or media stored in the Privacy Space.

#### Scenario: First-time PIN setup
- **WHEN** user clicks on the Privacy Space navigation item for the first time
- **THEN** system prompts the user to create and confirm a 6-digit numeric PIN code, storing its salted hash securely in Keychain storage

#### Scenario: PIN verification upon access
- **WHEN** user navigates to the Privacy Space while in locked state
- **THEN** system displays a 6-digit PIN entry lock screen covering both sub-navigation and main view, denying access until the correct PIN is provided

#### Scenario: Incorrect PIN entry
- **WHEN** user enters an incorrect 6-digit PIN code
- **THEN** system rejects the attempt, clears the input, shakes the PIN field with visual feedback, and preserves the locked state

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

### Requirement: Complete isolation from general workspace
The system SHALL hide all private tools, recently played media records, and downloaded files from the general All Tools view, recent tools list, and global search bar.

#### Scenario: Private tools excluded from global search
- **WHEN** user enters queries in the global tool search bar on the home screen
- **THEN** system excludes all tools registered under the Privacy Space from search results

