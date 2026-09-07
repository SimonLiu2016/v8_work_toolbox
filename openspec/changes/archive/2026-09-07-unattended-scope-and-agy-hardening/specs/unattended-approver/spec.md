## Purpose

为 AI 编程助手（Antigravity CLI 与 Claude Code）提供具备动态随行生命周期、作用域与边界安全感知、零干涉保证及本地时间审计的无人值守全自动审批服务。

## ADDED Requirements

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
