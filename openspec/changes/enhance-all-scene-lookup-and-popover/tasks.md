## 1. Browser Companion In-Page Bubble (Track 1 - Web)

- [x] 1.1 In `extensions/v8-browser-companion/manifest.json`, register `content_scripts` for `<all_urls>` with `content.js` and `content.css`
- [x] 1.2 Implement `extensions/v8-browser-companion/content.js`: attach Shadow DOM to isolate styles, listen to selection changes, and anchor floating bubble to `range.getBoundingClientRect()`
- [x] 1.3 In `content.js`, implement sub-second dictionary lookup and audio pronunciation in the in-page card
- [x] 1.4 In `content.js`, implement "保存笔记" and "加入生词本" actions communicating with desktop app via `v8toolbox://` or background message

## 2. Desktop Selection Action Bubble (Track 2 - PDF, Word, System)

- [x] 2.1 In `AppDelegate.swift`, implement `SelectionBubblePanel`: a 28x28 non-activating borderless floating `NSPanel` with the V8 emblem
- [x] 2.2 In `AppDelegate.swift`, register global `NSEvent` mouse-up monitor to detect selection changes and present the bubble at cursor location with auto-dismiss
- [x] 2.3 Wire click on the floating bubble to trigger lookup and expand the full popover
- [x] 2.4 Reconcile Cocoa `NSWindow.setFrame` and Flutter `window_manager` coordinate systems to eliminate top-left window jumps on `⌥D`

## 3. Fast Domestic Dictionary & On-Demand AI

- [x] 3.1 Enhance `YoudaoService` to parse full phonetics, audio URLs, part-of-speech groupings, and example sentences with sub-300ms latency
- [x] 3.2 In `LookupCoordinator`, prioritize domestic dictionary lookup and remove automatic slow fallback to `_aiTranslation`
- [x] 3.3 In `LookupPanelView`, display an explicit "使用 AI 深度解析" button when a word has no dictionary entries or when user wants deeper analysis

## 4. Light Theme & System Appearance Following

- [x] 4.1 In `lib/theme/app_theme.dart`, create `lightTheme` token suite matching Apple Dictionary aesthetics
- [x] 4.2 In `LookupWindowApp`, configure `theme: AppTheme.lightTheme`, `darkTheme: AppTheme.darkTheme`, and `themeMode: ThemeMode.system`
- [x] 4.3 In `LookupPanelView`, dynamically adjust card borders and background colors to current theme brightness

## 5. Rich Note Markdown Delta Formatting

- [x] 5.1 In `note_capture_service.dart`, replace `_markdownToDelta` with `MarkdownConverter.markdownToDelta(fullContent)`
- [x] 5.2 Verify captured notes in `NoteStore` display actual divider lines, bold source tags, and active links without raw syntax characters

## 6. Verification & Deployment

- [x] 6.1 Run unit tests and `flutter analyze lib/`
- [x] 6.2 Execute `./scripts/deploy_local.sh` to update `/Applications/V8WorkToolbox.app`
- [x] 6.3 Verify in-page bubble in Chrome on selected text
- [x] 6.4 Verify floating action icon in PDF Preview and Microsoft Word on selected text
