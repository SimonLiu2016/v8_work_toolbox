# unattended-approver Specification

## Purpose
Provides a secure, globally controlled unattended auto-approval service for AI coding agents across multiple projects and terminal environments, enforcing mechanical safety floors and audit tracking.
## Requirements
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

### Requirement: Allowlist Rule Consolidation via Rule Management Dialog

规则管理弹窗 SHALL 在「清空白名单」与「保存修改」按钮之间提供「AI整理」入口，用于将当前白名单中明显相似的规则合并为简单通用的宽规则。整理 MUST 先执行本地预整理（精确去重与相同前缀合并），再在 AI 可用时执行语义聚类合并；AI 只被允许合并本地簇检测判定为"明显相似"的规则，未归簇的规则 MUST 原样保留。整理结果 MUST NOT 直接写入白名单状态：AI 或本地整理产出的变更 MUST 以"合并前规则 ↔ 合并后规则"的对照形式展示给用户确认，确认后仅回填弹窗编辑框，由用户点击「保存修改」才生效。

#### Scenario: AI 可用时整理相似规则簇

- **WHEN** 白名单存在多条语义相同但文本不同的规则（例如多条仅 echo 文案或校验尾部不同的 deploy 命令规则），用户在规则管理弹窗点击「AI整理」
- **THEN** 系统执行本地预整理后调用 AI 将同簇规则合并为宽规则，并通过校验闸门后展示合并对照预览
- **AND** 用户确认后编辑框内容被替换为整理结果，白名单状态在用户点击「保存修改」前保持不变

#### Scenario: AI 不可用时退化为本地预整理

- **WHEN** 用户点击「AI整理」但 AI 文本槽位不可用或调用失败
- **THEN** 系统仍执行本地预整理（去重 + 相同前缀合并），将结果回填编辑框
- **AND** 以不阻塞的方式明确告知用户本次为本地降级整理，未执行 AI 语义合并

#### Scenario: 无冗余时整理为空操作

- **WHEN** 白名单规则经本地预整理与簇检测后无可合并项
- **THEN** 系统提示"未发现可合并的相似规则"，编辑框内容保持不变

### Requirement: Intelligent Merge on Add-to-Allowlist

审计流水的「加入白名单」动作 SHALL 升级为智能合并流程：首先检测命令是否已被现有规则覆盖，覆盖时 MUST 提示且不重复添加；未覆盖时执行本地同簇检测，若与现有规则明显相似则尝试调用 AI 将新命令与同簇旧规则泛化为一条宽规则，经校验闸门与用户确认后替换同簇旧规则；AI 不可用、调用失败或校验失败时 MUST 静默退回现行精确规则行为（转义后 `^...$` 锚定添加）。该流程 MUST NOT 设置调用频率节流——所有失败路径均为安全静默降级。

#### Scenario: 命令已被现有规则覆盖

- **WHEN** 用户对一条已被现有白名单规则（含此前合并出的宽规则）覆盖的命令点击「加入白名单」
- **THEN** 系统提示该命令已被哪条规则覆盖，白名单不新增任何规则

#### Scenario: 同簇命令经确认合并为宽规则

- **WHEN** 用户加入的新命令与现有规则同簇且 AI 可用
- **THEN** 系统调用 AI 产出宽规则，校验通过后展示"将替换这 N 条旧规则"的确认对话框
- **AND** 用户确认后同簇旧规则被宽规则替换；用户选择「只加精确规则」则按现行行为添加精确规则

#### Scenario: AI 失败静默降级

- **WHEN** 同簇检测命中但 AI 槽位不可用、调用超时或产出未通过校验闸门
- **THEN** 系统按现行行为添加精确规则，并以不阻塞的提示告知"AI 整理不可用，已按精确规则加入"

### Requirement: Consolidated Rule Validation Gate

任何由 AI 或本地整理产出、即将写入白名单的规则 MUST 通过三重校验闸门后方可提交给用户确认：① 语法校验——规则必须能编译为合法正则；② 回验——被合并的每条原始命令/规则必须仍能被新规则命中；③ 黑名单交叉校验——新规则 MUST NOT 命中机械安全硬地板的代表性危险命令样本。任一校验失败时系统 MUST 丢弃该合并结果并保留原规则（fail-safe 方向为不泛化）。该闸门 MUST 同时约束整理按钮（存量）与加入白名单（增量）两条路径。

#### Scenario: 回验失败丢弃合并

- **WHEN** AI 产出的宽规则无法命中被合并的某一条原始命令
- **THEN** 系统丢弃该合并结果，原有规则全部保留，并提示该簇合并失败

#### Scenario: 黑名单交叉命中丢弃合并

- **WHEN** AI 产出的宽规则命中了机械安全硬地板的危险命令样本（例如规则被过度泛化为 `rm -rf /Applications/.*`）
- **THEN** 系统丢弃该合并结果，原有规则全部保留，并向用户说明因安全风险未采纳

#### Scenario: 非法正则被拦截

- **WHEN** AI 产出的规则无法编译为合法正则
- **THEN** 系统丢弃该规则，不进入用户确认环节

### Requirement: Mechanical Similarity Clustering for Allowlist Rules

系统 SHALL 提供机械可算的"明显相似"判定，作为 AI 合并的前置约束：从规则或命令中提取字面锚点（正则反转义后的绝对路径字面量与首个动词），两条规则锚点交集非空且首个动词相同时判定为同簇。AI MUST NOT 合并跨簇规则。该判定 MUST 为纯本地计算，不依赖 AI。

#### Scenario: 尾部不同但锚点一致的命令同簇

- **WHEN** 多条规则的差异仅存在于 echo 文案、校验命令（shasum/stat/du）等尾部，而首个动词（如 `rm`）与目标路径锚点（如 `/Applications/V8WorkToolbox.app`）一致
- **THEN** 本地簇检测将它们判定为同簇，允许进入 AI 合并

#### Scenario: 锚点不交集不合并

- **WHEN** 两条规则的目标路径锚点无交集（例如 `rm -rf /Applications/AppA.app` 与 `rm -rf /Applications/AppB.app`）
- **THEN** 系统判定为不同簇，AI 不得将其合并为一条规则

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
