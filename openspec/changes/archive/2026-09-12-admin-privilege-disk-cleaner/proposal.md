# Proposal: Administrator-Elevated Disk Cleaning and Pre-scan Ownership Detection

## Why

In the "Smart Disk Slimmer" (智能磁盘瘦身) feature, some historical remnants (such as `/Users/simon/Library/Application Support/jsDesignAgent`) were created with root privileges (`drwxr-xr-x root:staff`). When a user attempts to recycle these items, macOS `FileManager.default.trashItem` rejects the operation with error 513 (`afpAccessDenied: Insufficient access privileges`). 

Currently, the app erroneously attributes this failure solely to missing "Full Disk Access" (TCC permission) and directs the user to macOS System Settings, even when Full Disk Access is already granted. Users are left confused and unable to clean root-owned remnants within the toolbox.

This change introduces pre-scan ownership detection (badging items that require admin privileges) and in-app administrator elevation (using native macOS Touch ID / password prompt via AppleScript with strict security boundaries) to seamlessly clean root-owned remnants while providing accurate diagnostic feedback.

## What Changes

- **Pre-scan Ownership Identification**: Detect file/directory ownership during scanning (checking if `uid == 0` or if write permission is missing for the current user), marking candidate items with `requiresAdmin: true`.
- **UI Admin Badge & Default Selection**: Display a clear `需管理员权限` badge on affected candidate items, and default their selection safely to avoid interrupting regular zero-touch cleaning.
- **Accurate Failure Diagnostics**: Differentiate between TCC (Full Disk Access) restrictions, root/POSIX permission limitations, and busy processes in the failure dialog, replacing misleading guidance.
- **In-App Administrator Elevated Cleaning**: Provide an "授权管理员清理" action in the failure dialog (and candidate flow) that invokes macOS native authentication (Touch ID / password via AppleScript `with administrator privileges`), transferring ownership back to the current user and recycling to Trash (with fallback to permanent removal), followed by rigorous post-operation physical verification.
- **Strict Security Boundaries**: Enforce strict path whitelist validation for all privileged operations, strictly forbidding path traversal (`..`), root `/`, home directory root `~`, or system directories (`/System`, `/usr`, `/Library`, etc.).

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `disk-analyzer`: Support detection of root-owned items, accurate failure diagnostics distinguishing POSIX root ownership from TCC permissions, and secure administrator-elevated recycling.

## Impact

- Affected files:
  - `lib/tools/slimmer/slimmer_models.dart`
  - `lib/tools/slimmer/app_orphan_detector.dart`
  - `lib/tools/slimmer/smart_disk_slimmer_page.dart`
  - `lib/services/system_service.dart`
  - Relevant test suites in `test/`.
- No breaking API changes to external modules.
