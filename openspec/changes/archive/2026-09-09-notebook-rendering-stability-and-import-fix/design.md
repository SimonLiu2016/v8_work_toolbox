## Context

See proposal.md - Why.
In release builds, Flutter converts unhandled widget exceptions during build into solid grey boxes. The current `NoteEditor` passed a manually-instantiated `DefaultStyles` to `QuillEditorConfig`, leaving properties such as `link`, `lists`, `indent` null. When documents with hyperlinks (such as "Docker常规操作") or lists are opened, Quill attempts to read `styles.link!.style`, throwing a null-check runtime error. Concurrently, title inputs inherit `AppTheme.darkTheme` fill color (#3C3C3C), and the ENML import converter truncates nested code block divs and appends non-image files as images.

## Goals / Non-Goals

**Goals:**
- Eliminate the solid grey crash box when viewing any note with links, lists, or custom attributes.
- Ensure the title input row in `NoteEditor` renders with a transparent background.
- Overhaul ENML-to-Markdown code block extraction in `scripts/evernote_import.py` to preserve multi-line code blocks regardless of inner `<div>` structures or single/double dash attributes.
- Enforce strict image MIME verification in `evernote_import_service.dart` and isolate block image embeds on their own lines.

**Non-Goals:**
- Replacing Flutter Quill with another rich text engine.
- Writing a full HTML browser rendering engine.

## Decisions

1. **Use `DefaultStyles.getInstance(context).merge(...)`**:
   - *Rationale*: Guarantees every single style token required by Flutter Quill has a complete fallback implementation.
   - *Alternative Considered*: Providing manual defaults for each omitted style. Rejected because upstream updates can introduce new required style getters.

2. **Explicit `filled: false` and transparent color on title TextField**:
   - *Rationale*: Bypasses the dark theme's global `inputDecorationTheme.fillColor`.

3. **Tag-balancing or state-aware code block extraction in Python**:
   - *Rationale*: Evernote ENML wraps every single line in a code block with `<div>...</div>`. A simple regex with `(.*?)` always terminates at the first line's closing `</div>`. A tag-balanced block scanner or BeautifulSoup/minidom tree extraction ensures the complete code block is captured.

4. **Isolate `BlockEmbed.image` with Newlines and Filter by Image MIME**:
   - *Rationale*: In Quill Delta specification, block embeds cannot share a line with text segments. Preceding and following each image embed with `
` ensures a valid Delta document tree. Only MIME types matching `image/*` or valid image extensions will generate image embeds.

## Risks / Trade-offs

- [Risk] Legacy imported notes already in the database might have corrupted Deltas from previous runs.
  → Mitigation: The editor applies defensive error handling when building QuillController, falling back to plain text recovery if a Delta document is corrupt.
