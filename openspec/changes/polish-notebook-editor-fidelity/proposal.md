## Why

Following the migration to AppFlowy Editor and initial blank canvas fix, six distinct UI and fidelity defects remain:
1. Attachment images whose file path contains spaces (macOS `Application Support`) fail to render and display as raw Markdown syntax `![image](...)`.
2. Existing Markdown code blocks fail to format with syntax highlighting because the AST emits `code` nodes while only `code_block` is registered in builders.
3. The note title input field has an unnatural dark gray `#3C3C3C` background caused by inheriting the global dark input decoration theme.
4. The formatting toolbar width collapses horizontally and leaves gaps instead of stretching across the full note width.
5. Inserted tables lack header styling, visual hierarchy, and border polish.
6. Inserted code blocks display as small white boxes in view mode and cannot be directly typed into without finding an obscure edit button.

Resolving these issues elevates the notebook experience to desktop-grade polish and complete Evernote import parity.

## What Changes

- **Attachment Image Space-Path Handling**: Preprocess image URLs containing spaces (e.g. `Application Support`) with CommonMark angle brackets `<...>` or directly decode to native `imageNode`, ensuring images render as real inline visuals.
- **Code Block Node Normalization**: Register both `'code'` and `'code_block'` builders, mapping all Markdown code blocks to syntax-highlighted code components with language tags and copy support.
- **Title Theme Isolation**: Explicitly disable `filled` background on the note title `TextField` and wrap the editor in an isolated light theme to prevent dark theme leakage.
- **Toolbar Full-Width Stretch**: Configure `width: double.infinity` on `NoteEditorToolbar` and `crossAxisAlignment: CrossAxisAlignment.stretch` on the editor column layout.
- **Table Visual Hierarchy & Style**: Register `TableCellBlockComponentBuilder` with `colorBuilder` giving row 0 an elegant `#F8FAFC` header background, set `TableStyle` border to 1.0px `#E2E8F0`, and generate bold text for initial header cells.
- **Inline Editable Code Block**: Refactor `NoteCodeBlockComponentWidget` so the code block is directly clickable and editable with monospace font, eliminating modal toggles and removing the discordant white background block.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `notebook-editor`: Enhances image rendering for local paths with spaces, code block syntax and inline editing, table header hierarchy, title styling, and full-width toolbar alignment.

## Impact

- **Affected Files**:
  - `lib/tools/notebook/appflowy_codec.dart`: Preprocess image URLs with spaces, normalize `code` and `code_block` AST nodes.
  - `lib/tools/notebook/markdown_converter.dart`: Standardize image markdown formatting.
  - `lib/tools/notebook/ui/note_editor.dart`: Theme isolation, block builders registration (`code`, `code_block`, `table/cell`), layout stretch.
  - `lib/tools/notebook/ui/components/note_editor_toolbar.dart`: Width infinity stretch, header cell bolding.
  - `lib/tools/notebook/ui/components/note_code_block_component.dart`: Inline direct editable code body, dark IDE styling.
- **Dependencies**: No new external dependencies required; utilizes existing `appflowy_editor` and `flutter_highlight` packages.
