## Why

When editing tables in the notebook editor, users experience several critical interaction issues:
1. Pressing the "Delete/Backspace" key within an active cell fails to delete text due to broken text input channel binding caused by premature and repeated `setState` on pointer events.
2. Dragging the mouse to select text inside a cell selects the entire table block instead of cell contents because `setState` unmounts and remounts the cell's `RenderEditable` mid-gesture, forfeiting the gesture arena to the outer Quill editor.
3. Clicking outside the table while in cell edit mode fails to dismiss the cell edit state or place the cursor in the Quill editor because `quillController.readOnly = true` and `editorFocusNode.canRequestFocus = false` cause Quill's gesture detectors to silently swallow clicks and prevent `TapRegion` outside tap detection.

## What Changes

- **Fix cell text selection & editing gesture flow**: Prevent unneeded full-widget `setState` calls on cell pointer down and preserve native `TextField` gesture handling within cells so text drag-selection and cursor placement work properly.
- **Fix keyboard input & Delete key handling**: Ensure `TextField` maintains active hardware keyboard / platform text input binding without being reset or clobbered by post-frame focus requests.
- **Fix outside click & focus dismissal**: Allow smooth transition between table editing and outer Quill text editing by ensuring Quill's editor focus node and controller remain accessible or handling blur/outside taps without locking out Quill's gesture detection.

## Capabilities

### Modified Capabilities
- `notebook-editor`: Enhanced table editing interactions ensuring cell text drag-selection, standard keyboard editing (including Delete), and natural outside-tap focus transitions.

## Impact

- `lib/tools/notebook/ui/note_editor.dart`: `_NoteTableWidgetState`, `_NoteTableWidgetBase`, `_enterEditMode`, `_exitEditMode`, cell gesture handling and Quill editor focus interplay.
- Automated tests in `test/` for table cell interaction, keyboard input, and focus transitions.
