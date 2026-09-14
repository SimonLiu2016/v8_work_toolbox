## Why

Currently, the unattended mode auto-approves safe commands but strictly blocks operations matching the mechanical safety floor denylist or rm scope boundaries. Developers frequently need to execute specific operations (such as deliberate git force pushes or resets in controlled feature branches) without being blocked by universal safety rules. Introducing a high-priority whitelist capability enables users to authorize explicit commands while maintaining general safety guardrails, complete with one-click allowlisting directly from the intercepted audit log stream.

## What Changes

- Add `allowlist: List<String>` to `UnattendedState` model and persist it to `~/.v8worktoolbox/unattended/state.json`.
- Implement high-priority evaluation order in both Dart (`UnattendedService.evaluateCommand`) and Node.js proxy (`v8-approval-proxy.js`): commands matching the whitelist are approved immediately with `reason: matched_whitelist`, bypassing denylist and rm scope checks.
- Support regex patterns with fallback to exact match, and automatically escape regex special characters when adding commands from the UI to prevent unintended pattern collisions.
- Add an "加入白名单" (Add to Whitelist) action button on intercepted audit stream items (`decision == 'deny'`), enabling one-click allowlisting with instant feedback.
- Add a Whitelist Management UI card and rules configuration dialog in the Unattended Assistant page, allowing users to view, edit, and reset whitelist entries.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `unattended-approver`: Add allowlist prioritization over denylist, one-click allowlisting from intercepted audit logs, and whitelist rule management.

## Impact

- `lib/services/unattended_service.dart`: Update `UnattendedState`, `evaluateCommand`, and `_buildApprovalProxyScript`.
- `lib/tools/unattended/unattended_page.dart`: Add whitelist UI controls, audit item actions, and state management.
- `test/unattended_service_test.dart`: Add unit tests for allowlist serialization, priority evaluation, and dynamic proxy script output.
- `test/unattended_page_test.dart`: Add widget tests for the allowlist card, dialog, and audit row action buttons.
