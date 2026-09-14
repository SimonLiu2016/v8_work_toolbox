## 1. Native Tray Animation Implementation

- [x] 1.1 Preserve native V8 logo and implement breathing pulse timer in `macos/Runner/AppDelegate.swift`
- [x] 1.2 Handle `setUnattendedStatus` in `v8_work_toolbox/launcher` MethodChannel in `AppDelegate.swift`
- [x] 1.3 Ensure clean timer cancellation and default state restoration on deactivate

## 2. Flutter IPC and Service Integration

- [x] 2.1 Add `setUnattendedStatus` method to `LauncherService` in `lib/services/launcher_service.dart`
- [x] 2.2 Wire `UnattendedService` state updates to notify `LauncherService` of active status and formatted remaining time
- [x] 2.3 Ensure initial status sync on app launch and `UnattendedService.init()`

## 3. Verification & Testing

- [x] 3.1 Write unit tests for `LauncherService` and `UnattendedService` state synchronization
- [x] 3.2 Run flutter analyze and flutter test to ensure zero errors and zero warnings
- [x] 3.3 Build release macOS binary and deploy to `/Applications/V8WorkToolbox.app`
