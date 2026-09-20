## 1. Editor Canvas Layout & Styling Refactor

- [x] 1.1 Remove `SingleChildScrollView` around `AppFlowyEditor` in `lib/tools/notebook/ui/note_editor.dart` and bind native `EditorScrollController`.
- [x] 1.2 Define standard `EditorStyle.desktop` with black text, crisp font hierarchy, custom cursor color, and proper horizontal margins.
- [x] 1.3 Implement tap-on-empty-canvas gesture handling to focus document when clicking below existing text.

## 2. macOS Window Titlebar & Header Alignment

- [x] 2.1 Refactor `NotebookPage` right panel and export header in `lib/tools/notebook/ui/notebook_page.dart` with consistent white/light background.
- [x] 2.2 Refactor `_SingleNoteWindowApp` in `lib/main.dart` with light theme override and 28px macOS window control clearance.

## 3. Real Widget Testing & Desktop Release Verification

- [x] 3.1 Create `test/note_editor_widget_test.dart` using `testWidgets` to mount `NoteEditor` and verify non-zero render dimensions and lack of layout exceptions.
- [x] 3.2 Run `flutter test test/note_editor_widget_test.dart` to verify passing widget test.
- [x] 3.3 Build macOS release binary (`flutter build macos --release`) and deploy to `/Applications/V8WorkToolbox.app` (built at `build/macos/Build/Products/Release/V8WorkToolbox.app`).
