## 1. Dependencies & Foundation

- [x] 1.1 Add `appflowy_editor` to `pubspec.yaml` and verify dependency resolution and clean compilation.
- [x] 1.2 Define document serialization utilities between Markdown, document JSON, and AppFlowy `EditorState`.

## 2. Editor Core Migration (`NoteEditor`)

- [x] 2.1 Replace `flutter_quill` editor widget in `lib/tools/notebook/ui/note_editor.dart` with `AppFlowyEditor` and initialize `EditorState`.
- [x] 2.2 Wire up note title, 800ms debounce auto-save, notebook selector, and tag chips with `EditorState`.
- [x] 2.3 Configure native `TableBlock` and `CodeBlock` component builders with language highlighting, line numbers, and copy action.
- [x] 2.4 Register custom `BlockComponentBuilder` for `mindmap` vector graphics and interactive outline card view.
- [x] 2.5 Register custom image component builder with interactive resize handles (25%, 50%, 75%, 100%, Auto) and context menu.
- [x] 2.6 Implement Cmd+V clipboard image paste interceptor in AppFlowy shortcut command pipeline.

## 3. Evernote Import & Export Service Realignment

- [x] 3.1 Update `lib/tools/notebook/evernote_import_service.dart` to decode Markdown directly into AppFlowy document nodes with local attachment mapping.
- [x] 3.2 Update `lib/tools/notebook/export_service.dart` to serialize notes from AppFlowy document nodes to Markdown, HTML, plain text, and CJK-fidelity PDF.

## 4. Comprehensive 11-Module Verification & Release

- [x] 4.1 Test Module 1 - Table: Verify native inline editing, Tab/Shift-Tab cell navigation, column width drag-resizing, and row/column additions/deletions with zero cursor/input conflicts.
- [x] 4.2 Test Module 2 - Code Block: Verify syntax highlighting, language selector, line numbers, and one-click copy functionality.
- [x] 4.3 Test Module 3 - Image Interaction: Verify interactive resize handles, preset percentage scaling (25%, 50%, 75%, 100%, Auto), and right-click context menu (copy, cut, delete).
- [x] 4.4 Test Module 4 - Clipboard Image Paste: Verify macOS Cmd+V captures clipboard bitmaps, saves to attachments directory, and embeds image node.
- [x] 4.5 Test Module 5 - Mind Map: Verify SVG vector rendering, zoom in/out controls, and outline card display from Evernote imported notes.
- [x] 4.6 Test Module 6 - Todo List: Verify checkbox toggling between checked/unchecked and Enter-key new item continuation.
- [x] 4.7 Test Module 7 - Typography & Inline Styles: Verify bold, italic, underline, strikethrough, text colors, H1~H3 headers, bullet/numbered lists, and blockquotes.
- [x] 4.8 Test Module 8 - Export Formats: Verify exports to Markdown, HTML, TXT, and PDF with macOS Arial Unicode CJK font rendering.
- [x] 4.9 Test Module 9 - Auto-Save & Debounce: Verify 800ms debounce triggers clean SQLite updates for both title and note content.
- [x] 4.10 Test Module 10 - Metadata & Header: Verify notebook classification dropdown, tag chip add/delete, pin toggle, and trash banner restore/destroy actions.
- [x] 4.11 Test Module 11 - Multi-Window & Context Menu: Verify independent single-note child window editing and 10 right-click card context menu actions.
- [x] 4.12 Build macOS release binary, deploy to `/Applications/V8WorkToolbox.app`, and complete end-to-end desktop verification across all 11 modules.
