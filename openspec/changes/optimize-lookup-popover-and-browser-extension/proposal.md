## Why

In the initial implementation of context-menu lookup and note capture (`add-context-menu-lookup-vocab-note`), user testing uncovered significant friction and architectural UX limitations:
1. **macOS Services Limitation**: macOS `NSServices` are buried deep under secondary "Services" submenus without app branding or custom icons. In web browsers, users expect a first-level context menu with an icon and submenus (identical to Doubao/豆包) or in-page selection toolbars.
2. **Window Disruption & Screen Flashing**: Triggering `⌥D` (lookup) or `⌥S` (save note) causes the main V8 window to flash and force itself into the foreground (`showMainWindow()`), disrupting reading and document workflows.
3. **Visual & Layout Defects**: The floating lookup window pops up at the top-left corner instead of following the cursor; macOS traffic-light window controls overlap the search input; redundant clear buttons clutter the input field; and key simulation (`⌘C`) leaks characters (e.g. `\D` or `ß`) into input fields instead of capturing selected text.

This change delivers a dual-track architecture:
1. **Desktop Native Overhaul**: A non-activating, borderless, cursor-anchored floating popover for external documents (PDF, editors, text), with zero main window focus-stealing, reliable selection capture (via Accessibility API or clean keystroke simulation), and a card UI matching the reference design.
2. **Browser Companion Extension**: A lightweight Manifest V3 Web Extension providing first-level right-click menu items with the V8 icon, in-page floating selection bubble, and direct integration with V8 Work Toolbox.

## What Changes

- **Desktop Popover Architecture**:
  - Remove all `showMainWindow()` calls on hotkeys (`⌥D`, `⌥S`) and services; run completely silently in the background.
  - Native cursor positioning: Position the floating panel adjacent to the mouse pointer (`NSEvent.mouseLocation`) with multi-display and edge-flipping logic.
  - Window styling: Configure the secondary window as a borderless `NSPanel` (`.nonactivatingPanel`), removing title bar and traffic light controls (`closeButton`, `miniaturizeButton`, `zoomButton`).
  - Input field cleanup: Remove redundant inner close/clear buttons, align styling with the reference card design (clean typography, phonetics, audio playback, part-of-speech chips).
  - Blur & dismiss handling: Dismiss smoothly on `Escape` or window blur without stealing focus.
- **Selection Capture Reliability**:
  - Implement macOS Accessibility API (`AXUIElementCopyAttributeValue` for `kAXSelectedTextAttribute`) for direct, zero-clipboard, zero-keystroke selection extraction.
  - As fallback, improve `CGEvent` copy simulation to ensure Option modifier flags are cleared before posting `⌘C`, preventing `\D` and `ß` key leakage.
- **Silent Note Capture**:
  - `⌥S` captures notes silently in the background without opening the main window.
  - Display non-intrusive macOS HUD or system notification on completion.
- **Browser Companion Extension (`extensions/v8-browser-companion`)**:
  - Manifest V3 Chrome/Edge/Chromium extension with V8 icon.
  - First-level right-click context menu: "V8 Work Toolbox" → "查词 (Lookup)", "保存笔记 (Save Note)".
  - Content script with optional in-page floating bubble upon text selection.
  - Communication bridge with the desktop V8 app via deep-link protocol (`v8toolbox://...`) or local loopback HTTP service.

## Capabilities

### New Capabilities
- `desktop-lookup-popover`: Borderless, cursor-anchored, non-activating floating lookup popover with clean card layout and zero main-window disruption.
- `silent-selection-capture`: Clean selection text extraction without modifier key leaks (`\D`/`ß`) and silent background note capture with HUD feedback.
- `browser-companion-extension`: Manifest V3 browser extension providing first-level right-click context menu with V8 branding and in-page selection actions.

### Modified Capabilities
<!-- None: new capabilities supersede initial experimental behavior without altering core notebook/vocab data specifications -->

## Impact

- Native macOS layer: `AppDelegate.swift` window setup, mouse location queries, and CGEvent/AXUIElement selection capture.
- Flutter UI: `lookup_window.dart` card styling, window controls, and keyboard handling.
- New sub-project: `extensions/v8-browser-companion/` (standalone Manifest V3 extension ready for unpacked loading in Chrome/Edge).
- Local protocol / URL scheme handler in macOS Runner.
