# unattended-approver Specification

## Purpose
Provides a secure, globally controlled unattended auto-approval service for AI coding agents across multiple projects and terminal environments, enforcing mechanical safety floors and audit tracking.
## Requirements
### Requirement: Global Unattended Mode State Machine
The system SHALL maintain a machine-wide unattended state file recording whether unattended mode is active, the activation timestamp, the expiration timestamp (TTL), and active safety rules. When inactive or expired, the system MUST fallback to standard manual confirmation without requiring background daemons.

#### Scenario: Enable unattended mode with TTL
- **WHEN** user enables unattended mode with a duration (e.g. 2 hours) via desktop UI or CLI
- **THEN** state is updated with `enabled: true` and `expiresAt` calculated from the TTL, and subsequent AI tool calls within this period are evaluated for auto-approval.

#### Scenario: Lazy expiration fallback
- **WHEN** the current time passes `expiresAt` and an AI tool hook evaluates permissions
- **THEN** the system automatically treats the mode as inactive, updates the state file, and routes the request to standard user confirmation prompts.

#### Scenario: Manual disable
- **WHEN** user manually toggles unattended mode to off
- **THEN** `enabled` is set to false immediately, and all subsequent tool calls require explicit manual approval.

### Requirement: Mechanical Safety Floor Blocking
The system SHALL intercept and refuse to auto-approve commands or tool operations matching the mechanical safety floor denylist, regardless of the unattended mode setting. The blocked action MUST trigger a macOS desktop alert notification.

#### Scenario: Block destructive filesystem operations
- **WHEN** an AI tool requests execution of destructive delete commands (such as `rm -rf /`, `rm -rf ~`, `rm -rf .`, or block device operations)
- **THEN** the system MUST deny automatic approval, return a blocked decision, and dispatch a macOS system notification.

#### Scenario: Block dangerous git push operations
- **WHEN** an AI tool requests execution of forced git updates (such as `git push --force` or `git push -f`)
- **THEN** the system MUST deny automatic approval and preserve repository remote integrity.

#### Scenario: Block secret credentials overwrite
- **WHEN** an AI tool requests write or edit operations targeting credential files (`.env`, `*.pem`, `*.key`, `id_rsa`)
- **THEN** the system MUST block automated authorization and require explicit human intervention.

### Requirement: AI Client Protocol Hook Integration
The system SHALL provide a lightweight proxy hook executable compatible with Claude Code (`PreToolUse`) and Antigravity / Gemini CLI (`BeforeTool`) protocols, returning structured permission decisions (`allow` or `deny`) in sub-10ms latency.

#### Scenario: Auto-allow safe Claude Code tool execution
- **WHEN** Claude Code calls PreToolUse for a safe shell command while unattended mode is active and unexpired
- **THEN** the proxy outputs `{"permissionDecision": "allow"}` and Claude Code executes the command without user confirmation prompts.

#### Scenario: Auto-allow safe Antigravity CLI tool execution
- **WHEN** Antigravity CLI calls BeforeTool for a safe shell command while unattended mode is active
- **THEN** the proxy authorizes the action and logs an audit record.

#### Scenario: Compatibility with existing tool hooks
- **WHEN** the user has existing global hooks configured (such as RTK token optimization hooks)
- **THEN** the system preserves the existing hooks in settings.json while chaining the unattended approval proxy.

### Requirement: Desktop Control Panel and Real-Time Audit Stream
The system SHALL provide a dedicated tool page in V8WorkToolbox with real-time status indicators, dynamic countdown timer, client hook installation diagnostics, and a persistent audit event table.

#### Scenario: Real-time status display and dynamic countdown
- **WHEN** user views the Unattended Assistant page in V8WorkToolbox
- **THEN** the UI displays current activation state, remaining time with live countdown, quick duration selectors (30m, 1h, 2h, 4h, 8h), and global hook installation badges.

#### Scenario: Audit logging and stream inspection
- **WHEN** an AI authorization decision is processed (allowed or blocked)
- **THEN** an audit entry containing timestamp, client type, target command, and decision is recorded to `audit.jsonl` and rendered in the real-time audit stream in the desktop UI.

#### Scenario: One-click hook configuration and verification
- **WHEN** user clicks "Check and Install Hooks" in the desktop UI
- **THEN** the system inspects `~/.claude/settings.json` and `~/.gemini/settings.json`, configures missing hooks idempotently, and updates status badges to ready.

### Requirement: System Sleep and Display Keep-Awake Prevention
The system SHALL prevent macOS from entering idle system sleep while unattended mode is active, ensuring continuous background AI execution and network connectivity. The system MAY optionally prevent display sleep based on user preference.

#### Scenario: Prevent idle system sleep on unattended mode activation
- **WHEN** user activates unattended mode with a duration (e.g. 2 hours)
- **THEN** the system launches a caffeinate process with `-i` (idle sleep prevention), bound to the host process PID (`-w`) and duration timeout (`-t`), ensuring AI operations and network connections are not suspended.

#### Scenario: Optional display keep-awake toggle
- **WHEN** user enables the "Keep Display Awake" option in unattended mode
- **THEN** caffeinate includes the `-d` flag in addition to `-i`, preventing screen lock or display dimming during unattended runs.

#### Scenario: Automatic sleep assertion release upon deactivation or timeout
- **WHEN** unattended mode is manually disabled by the user or reaches its TTL expiration
- **THEN** the caffeinate process is promptly terminated and system sleep assertions are released. If the application exits abnormally, the `-w <pid>` and `-t <seconds>` arguments ensure the assertion automatically releases without orphaning.

### Requirement: Dynamic Accompanying Hook Lifecycle
The system SHALL dynamically manage AI client hook registrations such that hooks exist only while unattended mode is actively enabled, guaranteeing zero interference when unattended mode is inactive or expired.

#### Scenario: Dynamic hook injection upon activation
- **WHEN** the user enables unattended mode with a duration TTL
- **THEN** the system idempotently registers the approval proxy into Antigravity CLI's configuration (`~/.gemini/config/hooks.json`) and Claude Code's configuration (`~/.claude/settings.json`), initiates keep-awake assertions, and enters active approval state.

#### Scenario: Automatic hook uninstallation upon deactivation or expiration
- **WHEN** unattended mode is manually disabled or its TTL expires
- **THEN** the system automatically removes its hook entries from both `~/.gemini/config/hooks.json` and `~/.claude/settings.json`, restoring pristine client configurations and ensuring no further AI actions are intercepted.

#### Scenario: Passive zero-interference fallback
- **WHEN** the proxy executable is invoked while unattended state is inactive or disabled
- **THEN** the proxy immediately terminates with exit code 0 without producing stdout output or recording audit entries, allowing client tools to execute without interference.

### Requirement: Scope-Aware and Boundary-Based Path Safety
The system SHALL evaluate destructive operations (such as `rm -rf`) based on target path boundaries and current execution context (`Cwd`), distinguishing safe development cleanup from cataclysmic system destruction.

#### Scenario: Allow in-workspace development cleanups
- **WHEN** an AI tool requests deletion targeting subdirectories within the current workspace (such as `rm -rf build/`, `rm -rf .dart_tool/`, `rm -rf dist/`, or `rm -rf scratch/`)
- **THEN** the system recognizes the target as an internal workspace path and automatically approves the operation.

#### Scenario: Allow system temporary directory cleanups
- **WHEN** an AI tool requests deletion targeting temporary paths (such as `rm -rf /tmp/xxx` or `rm -rf /var/tmp/xxx`)
- **THEN** the system identifies the target within the allowed temporary scopes and automatically approves the operation.

#### Scenario: Block catastrophic top-level and user root deletions
- **WHEN** an AI tool requests deletion targeting system root (`/`), system directories (`/System`, `/usr`, `/Library`), user home root (`~` or `/Users/<name>`), current root (`.`), or parent escape (`..`)
- **THEN** the system hard-blocks the operation, records a denied audit entry, and triggers a macOS desktop alert.

### Requirement: Antigravity CLI and Claude Code Native Protocol Integration
The system SHALL natively parse and respond to Antigravity CLI (`PreToolUse` on `run_command`) and Claude Code (`PreToolUse` on `Bash`) input formats, eliminating interactive terminal permission prompts during active unattended sessions.

#### Scenario: Silent auto-approval for Antigravity CLI
- **WHEN** Antigravity CLI invokes `PreToolUse` with `toolCall.args.CommandLine` for a safe command during active unattended mode
- **THEN** the proxy outputs `{"decision": "allow"}` with exit code 0, and the agent executes the tool immediately without prompting the user.

#### Scenario: Safe block for Antigravity CLI
- **WHEN** Antigravity CLI invokes `PreToolUse` for a command violating the safety floor
- **THEN** the proxy outputs `{"decision": "deny", "reason": "..."}` and blocks execution.

### Requirement: Real-Time Audit Stream with Local Timezone Accuracy
The system SHALL display audit stream timestamps converted to the local device timezone and accurately identify the originating client tool.

#### Scenario: Accurate local time display
- **WHEN** an audit record with ISO timestamp is rendered in the desktop UI
- **THEN** the timestamp is formatted in local time (e.g., `13:xx:xx`) rather than raw UTC, accurately reflecting the actual execution time.

#### Scenario: Client identification in audit stream
- **WHEN** an operation is intercepted from Antigravity CLI or Claude Code
- **THEN** the audit stream displays the corresponding badge (`AGY` or `Claude Code`) indicating the exact originating client.

