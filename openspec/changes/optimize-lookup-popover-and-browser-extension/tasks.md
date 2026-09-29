## 1. Native macOS: Zero Focus Steal & Cursor Positioning

- [x] 1.1 In `AppDelegate.swift`, remove all `showMainWindow()` calls from `simulateCopyAndInvoke`, `handleLookupService`, and `handleSaveNoteService` to guarantee silent execution
- [x] 1.2 In `AppDelegate.swift`, capture `NSEvent.mouseLocation` and compute screen-clamped coordinates (avoiding display edge overflow) on active display
- [x] 1.3 In `AppDelegate.swift`, configure the lookup window as a borderless `NSPanel` (`[.borderless, .nonactivatingPanel]`, `level = .floating`), hiding standard window buttons (close, miniaturize, zoom)
- [x] 1.4 Expose cursor position and window repositioning via `v8_work_toolbox/context_services` method channel

## 2. Native macOS: Safe Selection Extraction (Zero Key Leakage)

- [x] 2.1 Implement `getSystemSelectedText()` using macOS Accessibility API (`AXUIElementCreateSystemWide`, `kAXSelectedTextAttribute`) for non-destructive, zero-clipboard text extraction
- [x] 2.2 In `simulateCopyAndInvoke` fallback, release Option modifier key (`kVK_Option`) before dispatching `⌘C` and restore state afterward, preventing `\D` and `ß` key leaks
- [x] 2.3 Integrate Accessibility check with keystroke fallback in `handleLookupHotKey` and `handleSaveNoteHotKey`

## 3. Flutter: Popover Window UI Refinement

- [x] 3.1 In `lookup_window.dart`, eliminate window title bar decoration and traffic-light padding, styling the root container as a card popover with rounded corners and subtle shadow
- [x] 3.2 In `lookup_window.dart`, clean up search input field: remove duplicate clear buttons, ensure single clear action and auto-focus on text
- [x] 3.3 In `lookup_window.dart`, implement window dismiss on `Escape` key and window blur (`onWindowBlur`), smoothly closing the popover

## 4. Silent Note Capture & Feedback

- [x] 4.1 In `note_capture_service.dart`, verify end-to-end background saving without opening or flashing main window
- [x] 4.2 In `AppDelegate.swift`, implement native macOS banner notification (`UNUserNotificationCenter`) on note capture success with title and notebook name

## 5. Browser Companion Extension (Track 2)

- [x] 5.1 Create `extensions/v8-browser-companion/manifest.json` with Manifest V3 declaration, context menu permissions, and host permissions
- [x] 5.2 Create extension icons under `extensions/v8-browser-companion/icons/`
- [x] 5.3 Implement `extensions/v8-browser-companion/background.js` registering first-level "V8 Work Toolbox" context menu with V8 icon and submenus ("查词", "保存笔记")
- [x] 5.4 Register custom URL scheme `v8toolbox://` in `macos/Runner/Info.plist` under `CFBundleURLTypes`
- [x] 5.5 In `AppDelegate.swift`, handle incoming `v8toolbox://` URLs (`lookup` and `savenote` endpoints)
- [x] 5.6 In `extensions/v8-browser-companion/background.js`, dispatch lookup and note save commands via `v8toolbox://` protocol

## 6. Verification & Deployment

- [x] 6.1 Run `flutter analyze` and ensure all tests pass
- [x] 6.2 Execute `./scripts/deploy_local.sh` to build, sign, and update `/Applications/V8WorkToolbox.app`
- [ ] 6.3 Verify `⌥D` lookup popover near cursor without screen flash or `\D` leak in external apps
- [ ] 6.4 Verify `⌥S` silent note capture in external apps with native notification
- [ ] 6.5 Verify Chrome extension context menu with first-level V8 icon and submenus
