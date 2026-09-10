## 1. Embed Builders Implementation

- [x] 1.1 Implement `NoteImageEmbedBuilder` in `note_editor.dart` supporting local file paths and network URLs with rounded styling, constraints, and error fallbacks.
- [x] 1.2 Implement `NoteUnknownEmbedBuilder` in `note_editor.dart` to prevent uncaught exceptions on unsupported embed types.
- [x] 1.3 Register `NoteImageEmbedBuilder` and `NoteUnknownEmbedBuilder` in `QuillEditorConfig` inside `NoteEditor`.

## 2. Selection Transparency & Text Highlighting

- [x] 2.1 Update `textSelectionTheme` in `NoteEditor` to use translucent selection color (`Color(0x66BFDBFE)`).
- [x] 2.2 Ensure the note title `TextField` shares the translucent selection styling.

## 3. Verification & Testing

- [x] 3.1 Add unit tests in `test/notebook_editor_test.dart` for notes containing image embeds and unknown embeds.
- [x] 3.2 Run `flutter test` and `flutter analyze` to ensure 0 errors and all tests pass.
