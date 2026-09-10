## Context

See proposal.md and specs/notebook-tool/spec.md. The current implementation renders a dark toolbar over white paper due to theme inheritance, collides with macOS traffic lights, fails to render mind maps because SVG data URIs and mind map trees are unhandled, renders code blocks without syntax highlighting or tools, and lacks interactive image manipulation.

## Goals / Non-Goals

**Goals:**
- Shift sidebar header down by 30px to clear native macOS traffic lights.
- Enforce unified light theme across `QuillSimpleToolbar`, metadata headers, and note canvas.
- Support `flutter_svg` to render Evernote mind map SVGs and structured outline views.
- Provide professional code blocks with language selection, syntax highlighting (`flutter_highlight`), line numbers, formatting, and one-click copy.
- Implement interactive image selection, drag-to-resize handles, size presets, context menu (copy/cut/delete), and clipboard image paste.

**Non-Goals:**
- Full-featured external mind map drawing tool (this iteration focuses on viewing, zooming, and navigating imported and created mind maps).
- Complex IDE-level code autocompletion.

## Decisions

### 1. Titlebar Clearance
- **Decision**: Update `_buildLeftPanel()` header in `notebook_page.dart` to `height: 68`, `padding: const EdgeInsets.only(top: 30, left: 16, right: 12, bottom: 8)`.
- **Rationale**: Follows standard macOS Human Interface Guidelines for transparent titlebars with `fullSizeContentView`.

### 2. Editor Light Theme Isolation
- **Decision**: Wrap the entire `NoteEditor` build tree in `Theme(data: ThemeData.light().copyWith(...))` and configure `QuillIconTheme`.
- **Rationale**: Completely isolates the paper-style note editor from the rest of the application's dark theme without affecting other tools.

### 3. Mind Map SVG & Outline Rendering
- **Decision**: Add `flutter_svg` to `pubspec.yaml`. In `evernote_import.py` and `markdown_converter.dart`, extract `data:image/svg+xml` data into `.svg` files in `notebook_attachments` and extract JSON outline trees. In `NoteEditor`, register `NoteMindMapEmbedBuilder` to render vector SVG with zoom/pan and outline switching.
- **Rationale**: Restores 36 existing user mind map notes with vector clarity.

### 4. Professional Code Block Embed
- **Decision**: Register `NoteCodeBlockEmbedBuilder` in `QuillEditor`.
- **Structure**:
  - Header: language dropdown (Dart, Python, JS, TS, Java, SQL, JSON, Go, Bash, Rust, etc.), format button, copy button.
  - Body: line numbers gutter + syntax-highlighted code block using `flutter_highlight` + horizontal scroll.
  - Editing: double-click or inline editing mode.

### 5. Interactive Image Resize and Paste
- **Decision**:
  - Update `NoteImageEmbedBuilder` into a stateful interactive widget with selection ring, 4 corner drag handles, and percentage preset buttons.
  - Persist chosen width into Quill Delta image attribute.
  - Add Cmd+V clipboard listener in `NoteEditor` that detects image bytes and inserts a new image embed.

## Risks / Trade-offs

- **[Risk]**: SVG rendering may encounter non-standard SVG elements in some older Evernote notes.
  - **Mitigation**: Wrap SVG rendering in an error boundary that falls back to the structured JSON outline view.
- **[Risk]**: Code block embeds need to serialize cleanly into Quill Delta.
  - **Mitigation**: Use standard custom embed format `{"code_block": {"code": "...", "language": "dart", "width": ...}}` with markdown fallback ````lang\ncode\n````.
