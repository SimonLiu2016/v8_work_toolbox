# Design: Unattended Mode Dynamic Menu Bar Tray Indicator

## Context

See `proposal.md` for motivation.
When Unattended Mode is running, AI agents have permission to auto-approve tool calls. Users need ambient awareness via the macOS menu bar tray icon so they know at a glance whether unattended mode is running without opening the window.

## Goals / Non-Goals

**Goals:**
- Retain the authentic V8 brand logo (`TrayIcon`) in the menu bar at all times to maintain strong product identity.
- Render a smooth, gentle breathing pulse animation (alpha oscillation between 1.0 and 0.35 at ~0.8s intervals) on the V8 icon to capture ambient attention without annoyance.
- Update the tray tooltip dynamically to display remaining countdown time and unattended status.
- Ensure 0 CPU/battery waste when inactive, and clean timer invalidation on disable or app termination.

**Non-Goals:**
- Replacing the application's brand logo with third-party or arbitrary symbols.
- Playing intrusive sound effects.
- Displaying persistent modal windows over the user's workspace.

## Decisions

### Decision 1: Preserve Native V8 Logo & Indicate Via Breathing Pulse
- **Choice**: Keep the native V8 mobius-ribbon template logo (`TrayIcon`) as the status item image without replacing it with external SF Symbols.
- **Rationale**: The menu bar icon is the primary visual anchor for the application. Retaining the V8 logo preserves brand identity and recognition, while the gentle breathing pulse and dynamic tooltip clearly communicate the active background state.

### Decision 2: Alpha-based breathing pulse via `NSView.alphaValue`
- **Choice**: Animate `statusItem.button.alphaValue` between 1.0 and 0.35 using a 0.8s periodic `Timer` and `NSAnimationContext.runAnimationGroup` with a 0.4s ease-in-out duration.
- **Rationale**: `NSStatusBarButton` is an `NSView`. Modulating `alphaValue` provides a fluid breathing effect natively without creating multiple bitmap assets or causing redraw churn.

### Decision 3: State synchronization via `v8_work_toolbox/launcher` MethodChannel
- **Choice**: Add `setUnattendedStatus` method to `v8_work_toolbox/launcher` channel with parameters:
  `{ 'active': bool, 'tooltip': String }`
  Invoked from `UnattendedService` whenever `_state` is updated, toggled, or loaded.
- **Rationale**: Centralizes menu bar status item management in `AppDelegate.swift` where `statusItem` already lives, avoiding duplicate channels.

## Risks / Trade-offs

- **[Risk] Background timer keeping CPU awake when unattended is disabled.**
  - **Mitigation**: Timer is created only when `active == true`. As soon as `active == false`, `unattendedTimer?.invalidate()` is called and set to `nil`, resetting `button.alphaValue = 1.0`.
