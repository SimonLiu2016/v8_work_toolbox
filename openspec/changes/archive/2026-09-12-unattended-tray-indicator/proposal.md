# Proposal: Unattended Mode Dynamic Menu Bar Tray Indicator

## Why

When "Unattended Mode" (无人值守模式) is active, AI coding agents (Claude Code, Antigravity) can automatically execute commands and approvals without user intervention. Currently, the menu bar tray icon remains in its static default state regardless of whether unattended mode is running, making it easy for users to forget that unattended mode is active or to remain unaware of its live status when working in other applications.

Providing a dedicated active icon and gentle breathing/pulsing animation on the macOS menu bar tray icon gives users an intuitive, eye-catching reminder that unattended mode is currently guarding and auto-approving actions, while restoring to the quiet default state as soon as unattended mode expires or is turned off.

## What Changes

- **Active State Tray Icon**: When unattended mode is active, switch the menu bar status icon from the default template icon to a dedicated active security guardian icon (`bolt.shield.fill`).
- **Breathing Pulse Animation**: Run a gentle, low-overhead pulsing/breathing animation (smooth alpha transition between 1.0 and 0.35 at ~0.8s interval) while unattended mode is active.
- **Dynamic Tooltip & Context Menu**: Update the tray tooltip to reflect the unattended status and remaining countdown time (e.g. `V8 工作工具箱 - 无人值守运行中 (剩余 01:45:00)`), and display an active status entry at the top of the tray menu.
- **State Synchronization**: Bridge `UnattendedService` state changes to native macOS via `v8_work_toolbox/launcher` MethodChannel so that activation, manual deactivation, and timer expirations instantly update the menu bar icon state.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `menu-bar-launcher`: Support active state icon switching, breathing pulse animation, and dynamic tooltip updates for background services.
- `unattended-approver`: Synchronize unattended mode active status with the menu bar tray indicator.

## Impact

- Affected files:
  - `macos/Runner/AppDelegate.swift`
  - `lib/services/launcher_service.dart`
  - `lib/services/unattended_service.dart`
  - Relevant test suites in `test/`.
- No breaking API changes or database migrations.
