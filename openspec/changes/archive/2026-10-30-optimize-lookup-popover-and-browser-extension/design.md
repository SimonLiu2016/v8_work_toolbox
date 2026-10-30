## Context

In the initial release of context-menu services, `⌥D` (lookup) and `⌥S` (note capture) caused screen disruptions due to `showMainWindow()`, top-left window positioning, overlapping macOS traffic-light buttons, and modifier leakage (`\D`/`ß`) during simulated keystrokes. Furthermore, macOS `NSServices` limitations prevent first-level context menu items with custom branding and icons in web browsers.

## Goals / Non-Goals

**Goals:**
- Eliminate all focus-stealing and window flashing on `⌥D` and `⌥S` in desktop applications.
- Anchor the desktop lookup popover adjacent to the mouse cursor position (`NSEvent.mouseLocation`) with edge collision avoidance.
- Eliminate traffic light buttons and inner duplicate close buttons, delivering a clean borderless card UI matching the reference design.
- Implement reliable text selection capture (Accessibility API prioritized + modifier-cleansed fallback) preventing `\D` and `ß` key leaks.
- Enable silent background note capture with native macOS HUD notification feedback.
- Provide a Manifest V3 Browser Companion Extension (`extensions/v8-browser-companion`) supporting first-level context menus with V8 icons and direct linkage to V8 Work Toolbox.

**Non-Goals:**
- Injecting native binary code into 3rd-party non-browser applications (which violates macOS system integrity protection).
- Replacing the existing Drift database or vocabulary book storage schema.

## Decisions

### 1. Borderless NSPanel Floating Popover
- **Decision**: Configure the secondary window as a borderless `NSPanel` (`[.borderless, .nonactivatingPanel]`, `level = .floating`), remove macOS traffic lights, and support automatic dismissal on blur and `Escape`.
- **Rationale**: A regular `NSWindow` displays traffic light buttons and takes focus with an active title bar, which disrupts reading. An `NSPanel` behaves like a system dictionary popover.
- **Alternative considered**: Full-screen transparent overlay. Rejected due to mouse-event pass-through complexities.

### 2. Cursor Positioning and Screen Boundary Flipping
- **Decision**: In the native layer (`AppDelegate.swift`), capture `NSEvent.mouseLocation` at the moment of trigger, convert Cocoa bottom-left coordinates to top-left screen coordinates, and position the popover window immediately below/right of the cursor. Flip upward or leftward if within 300px of screen edges.
- **Rationale**: Eliminates the jarring jump to the top-left corner of the screen.

### 3. Dual-Layer Selection Extraction (Accessibility API + Cleansed CGEvent)
- **Decision**: First attempt reading selected text via macOS Accessibility API (`AXUIElementCopyAttributeValue` with `kAXSelectedTextAttribute`). If unavailable (e.g. Electron apps with disabled accessibility), release the Option modifier key (`kVK_Option`) before dispatching `⌘C`.
- **Rationale**: Accessibility API is silent, doesn't touch the clipboard, and never leaks keystrokes. Cleansing Option modifier before fallback `⌘C` guarantees that `\D` (from `⌥D`) and `ß` (from `⌥S`) are never typed into active documents or inputs.

### 4. Background Silent Note Capture with HUD Notification
- **Decision**: Remove `showMainWindow()` on note capture. Process note extraction, HTML-to-Markdown conversion, and database commit asynchronously in the background. Post a native macOS user notification (`UNUserNotificationCenter`) on completion.
- **Rationale**: Note capture while reading should take zero seconds of focus and never interrupt the user's reading flow.

### 5. Manifest V3 Browser Extension & Deep Link Bridge
- **Decision**: Create `extensions/v8-browser-companion` using Chrome Manifest V3. Register `chrome.contextMenus` with top-level "V8 Work Toolbox" item and icon. Register `v8toolbox://` custom URL scheme in `Info.plist` to dispatch commands (`v8toolbox://lookup?text=...` and `v8toolbox://savenote?...`) directly into V8.
- **Rationale**: Solves the browser context-menu limitation 100% cleanly without hacks, matching Doubao's first-level menu UX.

## Risks / Trade-offs

- **[Risk] Accessibility Permissions on macOS**: Accessibility API requires Accessibility permission in System Settings.
  - **Mitigation**: Graceful fallback to cleansed `⌘C` keystroke simulation if permission is not granted.
- **[Risk] Unpacked Extension Installation**: Chrome/Edge requires developer mode to load unpacked extensions.
  - **Mitigation**: Provide one-click install script / instructions and prepare extension folder structure ready for Chrome Web Store packaging.
- **[Risk] Multi-Display Coordinate Mapping**: Displays with different scaling factors or vertical arrangements.
  - **Mitigation**: Use `NSScreen.screens` to locate the display containing the cursor and clamp within `visibleFrame`.
