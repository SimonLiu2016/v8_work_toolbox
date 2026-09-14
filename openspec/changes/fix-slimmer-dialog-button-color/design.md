# Design: Fix Invisible Text on "Open System Settings" Button in Smart Disk Slimmer Dialog

## Context

See `proposal.md` for motivation.
In Flutter's Material 3 theme implementation, `ElevatedButton` foreground color defaults to `colorScheme.primary` unless explicitly specified or configured in `elevatedButtonTheme`. In `AppTheme.darkTheme`, `colorScheme.primary` is configured as `AppTheme.accent` (`#6366F1`). When an `ElevatedButton` uses `backgroundColor: AppTheme.accent` without specifying `foregroundColor: Colors.white`, both foreground (text and icon) and background share the exact same purple hue, rendering the button content completely invisible.

## Goals / Non-Goals

**Goals:**
- Guarantee high-contrast white text and icon for the "打开系统设置" button in `smart_disk_slimmer_page.dart`.
- Configure `AppTheme.darkTheme.elevatedButtonTheme` with `backgroundColor: accent` and `foregroundColor: Colors.white` to prevent recurring contrast failures across all tools.
- Verify through widget/unit tests and ensure 0 analyzer warnings.

**Non-Goals:**
- Restyling other buttons (e.g. `OutlinedButton`, `TextButton`) that already display high contrast.
- Modifying the business logic of Full Disk Access checking or Trash recycling.

## Decisions

### Decision 1: Direct button styling plus global theme default (Defense in Depth)
- **Choice**:
  1. Add `foregroundColor: Colors.white` directly to `ElevatedButton.styleFrom(...)` in `smart_disk_slimmer_page.dart`.
  2. Add `elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white))` in `AppTheme.darkTheme`.
- **Rationale**: Direct styling guarantees the fix specifically where the bug was reported, while theme-level configuration ensures any current or future `ElevatedButton` across the entire app has consistent white foreground text when using primary accent styling.
- **Alternatives Considered**: Only fixing `AppTheme`. While elegant, local `ElevatedButton.styleFrom(backgroundColor: ...)` calls without local foregroundColor can still inherit standard Material 3 primary-colored text if button theme overrides are partial. Fixing both ensures rock-solid contrast.

## Risks / Trade-offs

- **Risk**: Global `elevatedButtonTheme` could alter existing buttons that relied on default foreground coloring.
  - **Mitigation**: Existing buttons using `ElevatedButton` either specify their own `foregroundColor` or use the default theme. Setting white text on accent background is the intended brand design for all filled primary buttons in V8 Work Toolbox.
