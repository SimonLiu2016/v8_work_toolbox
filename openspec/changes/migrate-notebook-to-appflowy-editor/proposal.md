## Why

The current notebook editor relies on `flutter_quill`, where tables, code blocks, and complex media are forced into custom `BlockEmbed` widgets. Because Flutter desktop only supports a single active text input client, nesting multiple Flutter `TextField` widgets inside a Quill document embed creates irreconcilable focus and gesture conflicts: dual blinking cursors, keystrokes leaking into outer note lines, broken cell drag-selection, and unreliable focus transitions.

Migrating to `appflowy_editor` fundamentally resolves these issues by adopting a unified document block tree (AST), where tables (`TableBlock`) and code blocks (`CodeBlock`) are native first-class citizens. Furthermore, because all notes in the toolbox are imported from Evernote via an intermediate clean Markdown representation, `appflowy_editor`'s native Markdown decoder (`markdownToDocument`) delivers superior fidelity without the baggage of legacy Quill Delta format conversion.

## What Changes

- **Core Editor Migration**: Replace `flutter_quill` with `appflowy_editor` as the underlying WYSIWYG note editing engine.
- **Native Table Support**: Replace the nested `TextField` table embed with `appflowy_editor`'s native `TableBlock`, enabling frictionless inline editing, Tab/Shift-Tab cell traversal, column width drag-resizing, and row/column additions/deletions.
- **Native Code Block Support**: Adopt native `CodeBlock` with built-in syntax highlighting, multi-language selection, line numbers, and copy actions under a unified cursor engine.
- **Interactive Image Manipulation**: Wrap `appflowy_editor`'s image component with interactive resize handles, preset percentage scaling (25%, 50%, 75%, 100%, Auto), and right-click context menu actions (copy, cut, delete).
- **macOS System Clipboard Image Paste**: Intercept Cmd+V to detect system bitmap images via AppleScript, save them to the note attachments store, and insert them directly into the document.
- **Mind Map Custom Block**: Register a custom `BlockComponentBuilder` (`mindmap`) that renders SVG vector graphics and hierarchical outline trees from Evernote imported notes.
- **Evernote Import Pipeline Optimization**: Feed clean Markdown from `evernote_import.py` directly into `appflowy_editor`'s `markdownToDocument`, eliminating the fragile hand-written `markdownToDelta` state machine while preserving todos (`- [ ]`), headers, bold/italic, attachments, and tables.
- **Export Service Realignment**: Wire Markdown and plain-text exports directly to `appflowy_editor`'s native serializers (`documentToMarkdown`, `toPlainText`), maintaining macOS CJK Arial Unicode font fidelity for PDF generation.

## Capabilities

### Modified Capabilities
- `notebook-editor`: Updates the rich-text editing engine requirements from `flutter_quill` Delta embeds to `appflowy_editor` block-based architecture with native `TableBlock`, `CodeBlock`, custom `mindmap` block, and Markdown/Evernote pipeline fidelity.

## Impact

- `pubspec.yaml`: Add `appflowy_editor` dependency; prune `flutter_quill` and Quill bridge packages once migration is validated.
- `lib/tools/notebook/ui/note_editor.dart`: Refactored to host `AppFlowyEditor`, custom block component builders, and floating/static toolbars.
- `lib/tools/notebook/evernote_import_service.dart`: Replaced `markdownToDelta` with AppFlowy document builder from Markdown.
- `lib/tools/notebook/export_service.dart`: Adjusted serialization sources to AppFlowy document nodes.
- `lib/tools/notebook/models.dart` & `note_database.dart`: Store note content as AppFlowy document JSON or standard Markdown string.
- `test/`: Rewrite table and editor interaction test suites to target AppFlowy Editor.
