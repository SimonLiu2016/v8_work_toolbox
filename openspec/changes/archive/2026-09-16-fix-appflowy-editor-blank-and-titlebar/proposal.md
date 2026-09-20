## Why

After migrating the notebook editor core from `flutter_quill` to `appflowy_editor`, the desktop app presents two critical visual defects:
1. The editor body below the toolbar renders completely blank and cannot be clicked or edited because `AppFlowyEditor` is wrapped inside an unconstrained `SingleChildScrollView`, breaking Flutter's layout contract and gesture event propagation.
2. The macOS window titlebar (top 28px under window traffic lights) displays a dark background that contrasts unnaturally with the pure white paper notebook editor.

## What Changes

- Remove outer `SingleChildScrollView` around `AppFlowyEditor` in `lib/tools/notebook/ui/note_editor.dart` and bind native `EditorScrollController`.
- Provide an explicit `EditorStyle.desktop` with defined cursor, selection, text colors, and responsive horizontal padding.
- Add an interactive tap-to-focus gesture handler on the editor container so clicking empty canvas areas instantly focuses the document.
- Correct the macOS titlebar background and safe area in `lib/tools/notebook/ui/notebook_page.dart` and `main.dart` sub-window (`_SingleNoteWindowApp`), giving the top export bar and editor header seamless white/neutral styling and proper top traffic-light margin.
- Add comprehensive `testWidgets` tests verifying that `NoteEditor` mounts, lays out with finite bounds, and receives keyboard focus without throwing exceptions.

## Capabilities

### Modified Capabilities
- `notebook-editor`: Update editor canvas layout and styling requirements to eliminate bounded layout collisions and support macOS transparent titlebar integration.

## Impact

- Files: `lib/tools/notebook/ui/note_editor.dart`, `lib/tools/notebook/ui/notebook_page.dart`, `lib/main.dart`.
- Tests: Add `test/note_editor_widget_test.dart` with real Flutter widget layout & pump tests.
