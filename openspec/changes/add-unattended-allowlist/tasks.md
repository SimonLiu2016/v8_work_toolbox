## 1. Unattended Core Service & Allowlist Engine

- [x] 1.1 Update `UnattendedState` to include `allowlist: List<String>`, with serialization in `toJson`, `fromJson`, and `copyWith`.
- [x] 1.2 Implement allowlist management methods in `UnattendedService` (`addToAllowlist`, `removeFromAllowlist`, `updateAllowlist`, `isCommandAllowed`).
- [x] 1.3 Update `evaluateCommand` in Dart to evaluate `allowlist` with top priority before rm scope and denylist checks.
- [x] 1.4 Update `_buildApprovalProxyScript` and `evaluateSafety` in Node.js proxy script to prioritize `allowlist` matching.

## 2. Desktop UI & Intercepted Stream Actions

- [x] 2.1 Add "加入白名单" action button to intercepted items (`isDenied`) in `_buildAuditItemRow` on `UnattendedPage`, with disabled state when already whitelisted.
- [x] 2.2 Add Whitelist Management card and rules configuration dialog to `UnattendedPage`.
- [x] 2.3 Wire reactive SnackBar notifications and state updates when a command is added to the allowlist.

## 3. Verification & Deployment

- [x] 3.1 Add unit tests in `test/unattended_service_test.dart` for allowlist serialization, priority evaluation, and proxy script generation.
- [x] 3.2 Add widget tests in `test/unattended_page_test.dart` for whitelist UI card, dialog, and audit item allowlist button.
- [x] 3.3 Run `flutter analyze` to confirm 0 issues across modified files.
- [x] 3.4 Build macOS release binary and deploy to `/Applications/V8WorkToolbox.app` via `ditto`.
