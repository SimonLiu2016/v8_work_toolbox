## 1. Data Model & Scanner Detection

- [x] 1.1 Add `requiresAdmin` field to `SlimCandidateItem` in `lib/tools/slimmer/slimmer_models.dart`
- [x] 1.2 Implement root/privilege check helper in `lib/tools/slimmer/app_orphan_detector.dart`
- [x] 1.3 Ensure root-owned items default to `SafetyRating.caution` and `isSelected = false`

## 2. System Service & Privileged Cleaning

- [x] 2.1 Enhance `SystemService.recyclePaths` to detect root-owned failures (`hasRootOwnedItems`)
- [x] 2.2 Implement `SystemService.recyclePathsWithAdminPrivileges` with strict security path whitelist and AppleScript elevation
- [x] 2.3 Add path safety validator ensuring no traversal, injection, or root directory modification

## 3. UI Diagnostics & Privileged Action Flow

- [x] 3.1 Display "需管理员权限" badge with lock icon in `lib/tools/slimmer/smart_disk_slimmer_page.dart`
- [x] 3.2 Update failure dialog to accurately differentiate root-owned failures from Full Disk Access
- [x] 3.3 Add "授权管理员清理" action button in dialog to trigger privileged cleanup and reload candidate list

## 4. Verification & Testing

- [x] 4.1 Write unit and widget tests for privilege detection, security validation, and dialog actions
- [x] 4.2 Run flutter analyze and flutter test to ensure zero errors and zero warnings
- [x] 4.3 Build release macOS binary and deploy to `/Applications/V8WorkToolbox.app`
