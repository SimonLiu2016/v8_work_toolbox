## 1. PDF Export CJK Font Fidelity

- [ ] 1.1 In `export_service.dart`, implement offline-first CJK font loader looking up macOS `/System/Library/Fonts/Supplemental/Arial Unicode.ttf` with in-memory caching and online fallback
- [ ] 1.2 Inject CJK font into `pw.ThemeData.withFont` in `_exportToPdf` across document headers, paragraphs, bullets, and metadata
- [ ] 1.3 Add test asserting that PDF generation with Chinese characters produces valid output without missing glyph errors

## 2. Multi-Window Sub-Window for Single Note

- [ ] 2.1 In `main.dart`, handle `subWindowArgument.startsWith('note:')` to launch `_SingleNoteWindowApp` rendering the target note
- [ ] 2.2 Add launcher helper in `notebook_page.dart` using `WindowController.create` to spawn a standalone note sub-window

## 3. Right-Click Context Menu Implementation

- [ ] 3.1 Wrap note cards in `_buildCenterPanel` with `GestureDetector(onSecondaryTapDown: ...)` to capture tap coordinate and trigger `_showNoteContextMenu`
- [ ] 3.2 Build macOS-style context menu with icons and separators for all 13 items
- [ ] 3.3 Implement action handlers for new note, standalone window, toggle pin/shortcuts, task checklist append, share dialog, presentation mode, export dialog, save attachments to folder, copy link, move to notebook, copy to notebook, duplicate note, and delete note

## 4. Verification, Build & Deployment

- [ ] 4.1 Run unit and integration tests verifying context menu actions and PDF CJK output
- [ ] 4.2 Run `flutter build macos --release` and update `/Applications/V8WorkToolbox.app` via `ditto`
