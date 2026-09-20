# Proposal: Fix Invisible Text on "Open System Settings" Button in Smart Disk Slimmer Dialog

## Why

In the "Smart Disk Slimmer" (智能磁盘瘦身) feature, when a file fails to be moved to Trash (e.g. due to sandbox or Full Disk Access permissions), the "移入废纸篓失败" (Move to Trash Failed) dialog appears. In this dialog, the action button next to "稍后处理" (Later) only displays as an elongated purple bar without visible text or icon because the `ElevatedButton` background is set to `AppTheme.accent` while its text/icon foreground defaults to `colorScheme.primary` (same purple `#6366F1`), resulting in zero contrast. 

Fixing this now ensures users can clearly read the "打开系统设置" (Open System Settings) button, understand how to resolve the permission error, and establishes a safe global `ElevatedButtonThemeData` in `AppTheme` to prevent similar invisible button text issues across the app.

## What Changes

- **Disk Slimmer Trash Failure Dialog**: Add explicit `foregroundColor: Colors.white` to the "打开系统设置" `ElevatedButton.icon` in `smart_disk_slimmer_page.dart`.
- **Global Theme Protection**: Add `elevatedButtonTheme` to `AppTheme.darkTheme` with `backgroundColor: accent` and `foregroundColor: Colors.white`, ensuring any `ElevatedButton` using the accent background has high-contrast white text by default.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `theme-and-brand`: Define global button contrast standards for elevated buttons using theme accent backgrounds.
- `disk-analyzer`: Ensure the Full Disk Access resolution button in the trash failure dialog displays high-contrast readable icon and text ("打开系统设置").

## Impact

- Affected files:
  - `lib/tools/slimmer/smart_disk_slimmer_page.dart`
  - `lib/theme/app_theme.dart`
  - Test files for theme and disk slimmer dialog UI verification.
- No breaking API changes or dependency modifications.
