## Context

See `proposal.md` for motivation.
`flutter_quill` uses an extensible Embed architecture (`EmbedBuilder`) for non-textual nodes such as `BlockEmbed.imageType`. When an embed type is not handled by `embedBuilders` or `unknownEmbedBuilder`, Quill throws `UnimplementedError`. In Flutter release mode, this renders a blank grey `ErrorWidget`, causing 700+ notes containing images (e.g., "SDD Kit") to appear as an unclickable grey area.
Additionally, Quill paints selection highlight rectangles directly over the text layer (`_paintSelection` called after `paintChild`), requiring `selectionColor` to have sufficient alpha transparency so underlying text remains visible.

## Goals / Non-Goals

**Goals:**
- Provide a robust `NoteImageEmbedBuilder` registered in `QuillEditorConfig.embedBuilders` that renders local image files and network images with responsive constraints, rounded borders, and broken-image fallbacks.
- Provide a safe `unknownEmbedBuilder` fallback that prevents any unknown block embed from crashing the editor.
- Make selection highlights translucent (`selectionColor: const Color(0x66BFDBFE)`) so selected text remains crisp and legible.

**Non-Goals:**
- Implementing advanced image resizing handles or inline cropping tools (standard responsive display is sufficient).
- Changing note storage or Delta serialization formats.

## Decisions

1. **Custom `EmbedBuilder` Implementation (`NoteImageEmbedBuilder`)**:
   - Matches `key => BlockEmbed.imageType` (`'image'`).
   - Parses `embedContext.node.value.data` as string. If file starts with `http://` or `https://`, renders `Image.network`; otherwise renders `Image.file(File(data))`.
   - Applies `BoxConstraints(maxWidth: 800, maxHeight: 600)`, `ClipRRect(borderRadius: BorderRadius.circular(8))`, and subtle grey border (`Border.all(color: Color(0xFFE2E8F0))`).
   - In case of `FileSystemException` or file missing, displays a compact placeholder card `[图片附件未找到: filename]` with `Icons.broken_image_outlined`.
   - Alternatives considered: using third-party `flutter_quill_extensions`. Rejected to avoid bulky video/camera transitive dependencies and native bridge incompatibilities on macOS.

2. **Universal Fallback (`unknownEmbedBuilder`)**:
   - Registered on `QuillEditorConfig.unknownEmbedBuilder`.
   - Renders a clean chip or placeholder `[未知嵌入元素: type]` rather than throwing `UnimplementedError`.

3. **Semi-transparent Text Selection Styling**:
   - Set `selectionColor: const Color(0x66BFDBFE)` in `NoteEditor`'s `textSelectionTheme`.
   - Wrap the editor column or configure the title `TextField` so both the title and body editor share the same translucent highlight.

## Risks / Trade-offs

- **[Risk] High-resolution local images consuming large GPU memory**:
  → Mitigation: Use `cacheWidth` or standard Flutter image memory cache; constrain container size to sensible maximum dimensions.
- **[Risk] Broken image paths during migration**:
  → Mitigation: `Image.file` errorBuilder safely catches missing files and renders an unobtrusive placeholder card without interrupting note editing.
