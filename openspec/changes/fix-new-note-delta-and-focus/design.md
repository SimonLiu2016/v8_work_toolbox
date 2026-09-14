## Context

See `proposal.md` - Why. The note editor recently migrated from `flutter_quill` to `appflowy_editor`. The new note creation entry still generated Quill Delta `[{"insert":"\n"}]`, which slipped through a fallthrough check in `AppFlowyCodec.parseToDocument` and was treated as Markdown text. Furthermore, AppFlowy's selection service actively clears selection when clicks miss existing block bounding boxes unless intercepted.

## Goals / Non-Goals

**Goals:**
- Guarantee newly created notes are clean, completely blank documents with 0 raw JSON or punctuation leakage.
- Safely handle legacy notes or database entries containing `[{"insert":"\n"}]` by mapping them to `Document.blank(withInitialText: true)`.
- Enable immediate caret display and keyboard editing upon clicking anywhere in the editing viewport, including the blank space below the first line.

**Non-Goals:**
- Schema changes or SQLite database migrations.
- Altering Evernote import or export converters.

## Decisions

### Decision 1: Strict Delta Guard in `AppFlowyCodec.parseToDocument`
When `content.startsWith('[')`, it represents a JSON array from Quill. If `MarkdownConverter.deltaToMarkdown` returns an empty string (as is the case for `[{"insert":"\n"}]`) or if JSON decoding fails, return `Document.blank(withInitialText: true)` immediately. Never allow JSON array strings to fall through to `_parseMarkdownWithCustomBlocks`.

*Alternatives considered*:
- Checking specifically for `content == '[{"insert":"\\n"}]'`: Too brittle; any other empty or whitespace-only Quill Delta would still leak. Strict handling of all `[` prefixes is comprehensive.

### Decision 2: Canonical Payload for New Notes
In `notebook_page.dart`, `_createNote` will pass `AppFlowyCodec.documentToJson(Document.blank(withInitialText: true))` as the initial `deltaJson`.

### Decision 3: AppFlowy Editor `FocusNode` & Footer Tap Target
- Instantiate `late FocusNode _editorFocusNode` in `_NoteEditorState`, properly disposed on teardown, and pass it to `AppFlowyEditor(focusNode: _editorFocusNode)`.
- Provide a `footer` widget to `AppFlowyEditor`: a `GestureDetector` that spans full width and reasonable height (~300px).
- AppFlowy wraps its `footer` in `IgnoreEditorSelectionGesture`, preventing `DesktopSelectionServiceWidget` from calling `clearSelection()`.
- On tapping the footer or editor background, invoke:
  ```dart
  _editorFocusNode.requestFocus();
  _editorState!.updateSelectionWithReason(
    Selection.single(
      path: lastNode.path,
      startOffset: lastNode.delta?.length ?? 0,
    ),
    reason: SelectionUpdateReason.uiEvent,
  );
  ```

## Risks / Trade-offs

- **[Risk] Footer extends document scroll length** → *Mitigation*: Keep footer height reasonable (e.g. 240-300px) and combine with outer container `onTap` so clicks in large desktop viewports seamlessly focus without excessive scroll elongation.
