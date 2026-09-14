## MODIFIED Requirements

### Requirement: Global Unattended Mode State Machine
The system SHALL maintain a machine-wide unattended state file recording whether unattended mode is active, the activation timestamp, the expiration timestamp (TTL), and active safety rules, and SHALL synchronize this active status with the desktop application menu bar tray indicator. When inactive or expired, the system MUST fallback to standard manual confirmation without requiring background daemons.

#### Scenario: Enable unattended mode with TTL
- **WHEN** user enables unattended mode with a duration (e.g. 2 hours) via desktop UI or CLI
- **THEN** state is updated with `enabled: true` and `expiresAt` calculated from the TTL, subsequent AI tool calls within this period are evaluated for auto-approval, and the desktop menu bar tray indicator is signaled to switch to active state.

#### Scenario: Lazy expiration fallback
- **WHEN** the current time passes `expiresAt` and an AI tool hook evaluates permissions
- **THEN** the system automatically treats the mode as inactive, updates the state file, routes the request to standard user confirmation prompts, and signals the menu bar indicator to return to idle.

#### Scenario: Manual disable
- **WHEN** user manually toggles unattended mode to off
- **THEN** `enabled` is set to false immediately, all subsequent tool calls require explicit manual approval, and the menu bar indicator returns to idle.
