## Context

See `proposal.md` — Why. This section covers only what shapes the approach.

Relevant current state:

- `LookupWindowLauncher.open()` (`lib/tools/lookup_panel/ui/lookup_window.dart:52`) creates the child window and then calls `await controller.show()`.
- `desktop_multi_window`'s native `window_show` handler (`FlutterWindow.swift:101`) does three things: `makeKeyAndOrderFront`, `setIsVisible(true)`, and `NSApp.activate(ignoringOtherApps: true)`. The third is what surfaces the main window.
- The same package's `CreateWindow` path (`FlutterMultiWindowPlugin.swift:111-114`) already does `window.orderFront(nil)` and `window.setIsVisible(!config.hiddenAtLaunch)` — so with `hiddenAtLaunch: false`, the window is already ordered front and visible *before* `show()` is called. `show()` duplicates that and adds the activation.
- `configureLookupWindow()` (`AppDelegate.swift:504`) already does `makeKeyAndOrderFront` without `activate` — the codebase already knew not to activate; the `show()` call simply runs first.
- The browser extension dispatches `v8toolbox://lookup?text=…` from a content script while Chrome is foreground, so the app being backgrounded at that moment is the common case, not an edge case.
- Four other sub-windows (`notebook`, `note:`, `ops-tool`, `password-vault`) also call `WindowController.create` + `show()`. For those, app activation is the expected outcome of an explicit open request.

## Goals / Non-Goals

**Goals:**
- The lookup popover appears without activating the desktop app.
- All lookup entry points share that behaviour (they already share one launcher).
- Other sub-windows keep activating.

**Non-Goals:**
- Changing the `desktop_multi_window` package (a hosted dependency).
- Adding an "activate or not" switch to the other four sub-windows.
- Bringing a hidden main window forward, or any main-window state management beyond "don't activate".

## Decisions

### Decision 1: Drop the redundant `show()` call rather than counteract the activation

- **Choice**: delete `await controller.show()` from `LookupWindowLauncher.open()`. The window is already ordered front and visible from the package's creation path.
- **Alternatives considered**:
  - Keep `show()` and hide the main window afterwards. Rejected: it needs a new platform channel for something the package already did for free, and hiding the main window is a different behaviour from not-activating — the user asked for the latter.
  - Patch the package. Rejected: hosted dependency; a fork would need re-pinning on every upgrade for one line.
  - Call `NSApp.hide(nil)` after `show()`. Rejected: hides the whole app including the popover we just made visible.
- **Rationale**: the activation is a side effect of a call whose other two effects are already satisfied. Removing the call is smaller than counteracting its side effect.

### Decision 2: Scope the change to the lookup popover only

- **Choice**: change only `LookupWindowLauncher.open()`. The four tool windows keep calling `show()`.
- **Alternatives considered**:
  - Make activation a per-window decision across all five. Rejected for now: the other four behave correctly, and a uniform switch would be a refactor with five call sites and no user-visible benefit. Worth doing only if a second window kind needs the popover's behaviour — at which point extract the shared helper.
- **Rationale**: fix what is broken; the generalisation has no current customer.

## Risks / Trade-offs

- **[Risk] The popover does not appear at all without `show()`.** → This is the risk that matters, and it is directly observable: if the window fails to appear, the user sees nothing, which is a loud failure rather than a silent one. The package's creation path does `orderFront` + `setIsVisible`, so this is unlikely, but it is the first thing to verify.
- **[Risk] `⌘D` / macOS Services / right-click paths change behaviour.** → Accepted and intended: all entry points share `open()`. When the app is already foreground (the common case for those paths), activating is a no-op, so users should see no difference.
- **[Risk] The popover's blur-to-close stops working when the app is not active.** → Not expected — `onWindowBlur` is per-window, not per-app — but it is on the verification list, because a popover that cannot be dismissed would be worse than one that activates the app.

## Migration Plan

1. Remove `await controller.show()` from `LookupWindowLauncher.open()`.
2. Verify by hand: trigger from the browser with the app backgrounded — popover appears, main window does not; blur still dismisses it.
3. Rollback: one line; restoring it restores the previous behaviour exactly.

## Open Questions

- None.
