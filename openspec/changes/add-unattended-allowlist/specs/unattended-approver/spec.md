## ADDED Requirements

### Requirement: High-Priority Whitelist Auto-Approval
The system SHALL maintain a configurable whitelist of command patterns that take precedence over the mechanical safety floor denylist and destructive rm scope checks during active unattended mode, automatically approving matching operations immediately.

#### Scenario: Auto-approve whitelisted command despite matching denylist
- **WHEN** an AI tool requests execution of a command matching an active whitelist pattern while unattended mode is active
- **THEN** the system immediately grants auto-approval with decision `allow` and reason `matched_whitelist`, bypassing denylist inspection and rm scope checks.

#### Scenario: Inactive unattended mode ignores whitelist auto-approval
- **WHEN** an AI tool requests execution of a whitelisted command while unattended mode is inactive or expired
- **THEN** the system does not auto-approve and leaves the request to standard user confirmation.

### Requirement: Intercepted Stream One-Click Whitelisting
The system SHALL provide a one-click action in the real-time audit stream to add intercepted commands to the whitelist and reflect the updated authorization state immediately.

#### Scenario: Add intercepted command to whitelist
- **WHEN** user clicks the "加入白名单" action button on an intercepted audit record in the desktop UI
- **THEN** the system adds the command to the whitelist with regex-safe escaping, updates `state.json`, displays a success notification, and reflects the item state as already whitelisted.

#### Scenario: Prevent duplicate whitelist entries
- **WHEN** an intercepted command in the audit stream already exists in the whitelist
- **THEN** the item action button is displayed in a disabled state indicating it is already whitelisted.

### Requirement: Whitelist Rule Management
The system SHALL provide a dedicated whitelist management interface on the unattended assistant page, allowing users to inspect, add, modify, and delete whitelist patterns.

#### Scenario: Inspect and update whitelist rules
- **WHEN** user opens the whitelist rules dialog from the unattended dashboard and modifies rules
- **THEN** the system persists the updated whitelist patterns to `state.json` and the evaluation engine applies the updated patterns to subsequent AI tool calls.
