## Context

See `proposal.md` and `specs/unattended-approver/spec.md`. Currently, `UnattendedService` manages approval state in `~/.v8worktoolbox/unattended/state.json` and evaluates commands both in Dart (`evaluateCommand`) and in the generated hook script `~/.v8worktoolbox/bin/v8-approval-proxy.js` (`evaluateSafety`).

Both engines currently evaluate:
1. Active & unexpired check
2. `rm` scope safety check (`evaluateRmScope` / `isTargetSafe`)
3. `denylist` regular expression scan (`matched_danger_floor`)
4. Default allow (`unattended_active_and_safe`)

## Goals / Non-Goals

**Goals:**
- Add `allowlist: List<String>` to `UnattendedState` and `state.json`.
- Implement priority evaluation: matching `allowlist` immediately returns `isAllowed: true` with `reason: matched_whitelist`, bypassing `denylist` and `rm` scope checks in both Dart and Node.js engines.
- Add an "加入白名单" (Add to Whitelist) action button on intercepted audit stream items (`decision == 'deny'`) with instant reactive UI update.
- Support safe regex pattern matching with fallback to exact equality. Automatically escape regex special characters when adding from the audit stream.
- Provide a dedicated Whitelist Management card and dialog on `UnattendedPage` to view, add, edit, and clear whitelist patterns.

**Non-Goals:**
- Auto-approving whitelisted commands when unattended mode is turned off or expired (unattended mode must be active for auto-approvals).
- Remote or cloud syncing of approval rules.

## Decisions

### 1. Dual-Engine Priority Flow
- **Decision**: In both `UnattendedService.evaluateCommand` (Dart) and `evaluateSafety` in `v8-approval-proxy.js` (Node.js), evaluate `allowlist` immediately after confirming the session is active.
- **Evaluation Order**:
  1. Session active and unexpired check
  2. **Allowlist scan** (if match -> `isAllowed: true`, `reason: matched_whitelist`)
  3. `rm` scope boundaries check
  4. `denylist` scan
  5. Default allow
- **Alternatives Considered**: Evaluating allowlist after `rm` checks. Rejected because the user specifically requested that the whitelist has higher priority than the blacklist and destructive protections for deliberate overrides.

### 2. Pattern Matching & Auto-Escaping Strategy
- **Decision**: Entries in `allowlist` are evaluated as case-insensitive regular expressions, with fallback to exact trimmed string equality if regex compilation fails. When clicking "加入白名单" from an audit record, escape regex metacharacters (`RegExp.escape(cmd.trim())`) and anchor with `^...$` to ensure precise matching without unintended side effects.
- **Alternatives Considered**: Exact substring match only. Rejected because users need to define patterns in the rules dialog.

### 3. UI Integration in Audit Stream & Dashboard
- **Decision**:
  - In `_buildAuditItemRow`, if `item.isDenied`, render an action button on the right:
    - If `_service.isCommandAllowed(item.command)` is already true, display a disabled `TextButton` or badge labeled `已加白`.
    - Otherwise, display an `OutlinedButton.icon` with `Icons.playlist_add_check_rounded` labeled `加入白名单`.
  - Clicking calls `_service.addToAllowlist(item.command)`, triggers SnackBar feedback, and updates UI immediately.
  - On `UnattendedPage`, add a `_buildAllowlistSection()` card with a "规则管理" dialog identical in usability to the denylist rules dialog.

## Risks / Trade-offs

- **[Risk]** User enters an invalid regex in the management dialog.
  → **Mitigation**: Wrap regex construction in `try { ... } catch (_) { ... }` in both Dart and JS, and fallback to `command.trim() == pattern.trim()`.
- **[Risk]** Large allowlist slows down hook execution.
  → **Mitigation**: Pre-compile or iterate over cached pattern lists; standard lists have < 100 entries, executing in < 1ms.
