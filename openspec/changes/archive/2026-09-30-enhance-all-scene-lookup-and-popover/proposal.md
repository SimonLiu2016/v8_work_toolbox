## Why

User testing revealed fundamental UX gaps across web browsing and external document reading:
1. **Browser In-Page Bubble**: Users expect an in-page floating popover directly anchored above/below the selected text (identical to the Doubao browser extension), rather than an external desktop OS window.
2. **External Document Access (PDF, Word, Pages)**: In Microsoft Word and PDF readers, macOS `NSServices` context menus are suppressed or buried. Users need a Bob/PopClip-style floating action icon that automatically appears next to selected text, plus reliable `⌥D`/`⌥S` cursor-anchored shortcuts.
3. **Dictionary Routing & Speed**: The current dictionary lookup hangs for 8+ seconds due to overseas API timeouts before falling back to slow AI generation. Dictionary lookup must be sub-second fast via high-availability domestic endpoints, and AI analysis should only be triggered on-demand by explicit user click.
4. **Theme Adaptation**: The solid black popover is visually harsh in daylight and light-themed reading environments; it needs a clean macOS-native light theme and system appearance following.
5. **Note Rendering**: Saved notes contain literal Markdown syntax strings (`---`, `**来源：**`) instead of rendered rich-text styling (bold, divider line, hyperlinks).

## What Changes

- **Browser Companion Extension (Track 1 - Web)**:
  - Inject `content.js` in `extensions/v8-browser-companion` to listen for selection changes and compute the exact DOM range coordinates (`range.getBoundingClientRect()`).
  - Render a high-fidelity, in-page floating bubble (1:1 Doubao style) directly above/below the selection.
  - Deliver sub-second dictionary lookup within the bubble with audio pronunciation, definition chips, and one-click sync to V8 notebooks via deep link.
- **Desktop Floating Action Icon (Track 2 - PDF, Word, System)**:
  - Implement a Bob/PopClip-style floating micro-action button that appears near the mouse cursor when text is selected in external apps.
  - Clicking the icon unfolds the cursor-anchored lookup/note card.
  - Coordinate system synchronization between Flutter `window_manager` and Cocoa `NSWindow` to ensure shortcuts (`⌥D`, `⌥S`) and floating windows anchor precisely to cursor position without top-left jumps.
- **High-Availability Dictionary Priority**:
  - Replace overseas endpoints with fast, domestic dictionary API endpoints (providing phonetics, Chinese definitions, and audio URLs).
  - Remove automatic slow fallback to AI; display clean "no entry found" state with a prominent "AI Deep Analysis" button for manual invocation.
- **Light & System Theme Support**:
  - Implement a clean light theme (`#FFFFFF` background, `#E2E8F0` border, soft shadows, `#0F172A` text) inspired by Apple Dictionary.
  - Support `ThemeMode.system` so popovers seamlessly match macOS light/dark appearance.
- **Rich Note Delta Formatting**:
  - Use `MarkdownConverter.markdownToDelta` to transform captured Markdown into structured AppFlowy Delta AST nodes, rendering headers, bold text, divider lines, and hyperlinks cleanly.

## Capabilities

### New Capabilities
- `in-page-browser-bubble`: In-page DOM selection bubble for Chromium browsers with sub-second dictionary definitions, pronunciation, and note saving.
- `desktop-selection-action-bubble`: System-wide floating action icon appearing upon text selection in external documents (Word, PDF, text editors).
- `fast-dictionary-routing`: Sub-second domestic dictionary engine with manual on-demand AI escalation.
- `light-and-system-theme-adaptation`: Light card theme and automatic system appearance synchronization.
- `structured-note-delta-formatting`: Rich markdown-to-delta parsing for captured notes.

### Modified Capabilities
<!-- None: new capabilities supersede previous experimental behaviors -->

## Impact

- `extensions/v8-browser-companion/`: Added `content.js`, `content.css`, and selection bubble rendering.
- `macos/Runner/AppDelegate.swift`: Selection event monitoring, floating icon panel, and window coordinate clamping.
- `lib/tools/lookup_panel/services/`: High-availability dictionary service and coordinator routing adjustments.
- `lib/theme/app_theme.dart`: Addition of `lightTheme` tokens and dynamic theme switching.
- `lib/services/note_capture_service.dart`: Structured delta generation using `MarkdownConverter`.
