## Context

The editor engine has migrated to `appflowy_editor`. The blank canvas issue has been solved by removing the outer `SingleChildScrollView` and attaching `EditorScrollController`. However, the visual presentation, block component fidelity, and Markdown translation require refinement across 6 specific touchpoints.

## Goals / Non-Goals

**Goals:**
- Fix attachment image rendering for file paths with spaces (macOS `Application Support`).
- Unify code block AST parsing so both `'code'` and `'code_block'` map to the interactive code component.
- Convert code blocks from modal edit/view toggles to a direct, inline-editable, dark IDE container.
- Clean up title field styling by removing dark input theme inheritance.
- Stretch formatting toolbar horizontally across the full editor width.
- Refine table borders (1.0px) and provide automatic row 0 header background coloring and bold text.

**Non-Goals:**
- Adding complex spreadsheet formulas to tables.
- Rewriting the database storage layer (SQLite schema remains untouched).

## Decisions

### 1. Image Path Normalization in Markdown Decoder Pipeline
- **Decision**: In `AppFlowyCodec.parseToDocument`, before feeding Markdown to `markdownToDocument`, run a regex pass over `!\[(.*?)\]\((.*?)\)`. If the target URL contains unescaped spaces and is not already wrapped in `<...>`, wrap it in `<${path}>`. Additionally, in `markdown_converter.dart`, ensure `_handleEmbed` outputs `![]($url)` wrapped in `<>` if it contains spaces.
- **Alternative**: URL-encoding the path (`%20`). However, local file systems and `Image.file()` handle raw spaces better than `%20` encoded paths without an extra decode step.

### 2. Code Block AST Normalization & Inline Editable Component
- **Decision**: In `note_editor.dart`, register the same `NoteCodeBlockComponentBuilder` for both `NoteCodeBlockKeys.type` (`'code_block'`) and `'code'`. Refactor `NoteCodeBlockComponentWidget` so that its main body is directly a multi-line `TextField` with monospace font, dark background `#0F172A`, light text `#F1F5F9`, and syntax-styled header bar (with language dropdown and copy button). Any change to the text field updates node attributes and triggers document save.
- **Alternative**: Keeping the separate "Edit Code" button. Rejected because users expect modern desktop editors (Notion, Obsidian, Typora) to allow immediate typing upon clicking code.

### 3. Title Field & Toolbar Layout Optimization
- **Decision**:
  - In `NoteEditor`, configure the note title `TextField` with `decoration: InputDecoration(filled: false, fillColor: Colors.transparent, ...)`.
  - Wrap `NoteEditor` in a `Theme(data: ThemeData.light().copyWith(...))` to establish an authoritative light scope for the entire paper area.
  - Set `width: double.infinity` on `NoteEditorToolbar`'s container, and set `crossAxisAlignment: CrossAxisAlignment.stretch` on `NoteEditor`'s `Column`.

### 4. Table Styling & Header Cell Color Builder
- **Decision**:
  - Pass custom `TableStyle(borderWidth: 1.0, borderColor: Color(0xFFCBD5E1))` to `TableBlockComponentBuilder`.
  - Register `TableCellBlockKeys.type: TableCellBlockComponentBuilder(colorBuilder: (context, node) { ... })` where `rowPosition == 0` returns `Color(0xFFF1F5F9)` and other rows return `Colors.white`.
  - When toolbar executes `_insertTable`, populate row 0 with bold text attributes.

## Risks / Trade-offs

- [Risk] Custom `TableCellBlockComponentBuilder` might override standard cell behavior. → Mitigation: Inherit standard AppFlowy `TableCellBlockComponentBuilder` and only supply the `colorBuilder` callback without modifying cell hierarchy.
- [Risk] Direct `TextField` inside code block could capture arrow keys. → Mitigation: Code blocks are standard isolated multi-line inputs; Escape or clicking outside unfocuses smoothly.
