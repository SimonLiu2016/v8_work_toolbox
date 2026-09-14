## 1. Dialog Button Styling Fix

- [x] 1.1 Add `foregroundColor: Colors.white` to "打开系统设置" button in `lib/tools/slimmer/smart_disk_slimmer_page.dart`
- [x] 1.2 Add `elevatedButtonTheme` with `backgroundColor: accent` and `foregroundColor: Colors.white` to `AppTheme.darkTheme` in `lib/theme/app_theme.dart`

## 2. Verification and Tests

- [x] 2.1 Add widget test verifying the contrast and text readability of the trash failure dialog action button
- [x] 2.2 Run flutter test and flutter analyze to ensure zero errors and zero warnings
- [x] 2.3 Build release macOS binary and deploy to `/Applications/V8WorkToolbox.app`
