## Context

During verification of the `disk-scanner-hardening` change against real macOS environments, three improvements were identified:
1. `_parseJsonArray` in `AiDiskDiagnosticsService` is unreferenced, triggering a static analysis warning.
2. System directories without `com.apple.` prefix (`AddressBook`, `GeoServices`, etc.) and developer CLI directories (`Homebrew`, `rtk`, `claude-cli-nodejs`, `mysql`, `ms-playwright`, `tabnine`, `docker desktop`) lack `.app` wrappers and were reported as "unmatched app remnants".
3. Lack of explicit FDA (Full Disk Access) permission detection and unconfigured AI navigation.

## Goals / Non-Goals

**Goals:**
- Zero errors and zero warnings on `flutter analyze --no-fatal-infos`.
- Comprehensive system & CLI whitelist in `AppOrphanDetector` to eliminate false positives on native services and developer tools.
- FDA permission restriction detection with a direct deep-link button (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).
- Helpful prompt when AI analysis is requested without configured AI keys.

## Decisions

### 1. System & Developer Tool Protection Whitelists
Add explicit sets in `AppOrphanDetector`:
- `_systemProtectedNames`: `{'addressbook', 'geoservices', 'coretelephony', 'clouddocs', 'mobilesync', 'callhistory', 'callhistorydb', 'accountsettings', 'identityservices', 'passkit'}`.
- `_developerCliProtectedNames`: `{'homebrew', 'rtk', 'claude-cli-nodejs', 'mysql', 'ms-playwright', 'tabnine', 'docker desktop', 'docker', 'wetype', 'pip', 'npm', 'pnpm', 'cargo', 'rustup'}`.
Any directory whose lower-case name matches either set is skipped immediately.

### 2. FDA Permission Sensing
- In `DiskScannerService`, track `bool hasPermissionError = false`.
- If `FileSystemException` with `osError.errorCode == 1` (Operation not permitted) or `osError.errorCode == 13` (Permission denied) is caught on top-level Library subdirectories, set `hasPermissionError = true`.
- Surface `hasPermissionError` in `ScanProgress` and `SmartDiskSlimmerPage` banner.
