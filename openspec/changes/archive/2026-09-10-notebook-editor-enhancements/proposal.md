## Why

The notebook tool interface currently has several usability and visual defects that limit editing productivity:
1. The top-left header overlaps with the native macOS window traffic lights (close/minimize/zoom).
2. The Quill editor toolbar inherits a dark background from the global theme, clashing starkly with the white note canvas.
3. Evernote mind map notes (36 existing notes) fail to display because their embedded SVG vector and JSON tree data are not properly handled.
4. Code blocks are rendered as plain unstyled monospaced text without language selection, syntax highlighting, line numbers, formatting, or one-click copy buttons.
5. Embedded images cannot be interactively selected, resized with drag handles, cut, copied, or pasted directly from the system clipboard.

## What Changes

- **Window Titlebar Clearance**: Adjust the left sidebar header padding to 30px top safe margin to sit gracefully below the native macOS traffic lights.
- **Unified Light Editor Theme**: Enforce a dedicated light theme on both `QuillSimpleToolbar` and the editing canvas, ensuring consistent typography, button highlights, and seamless paper aesthetics.
- **Mind Map Notes Support**: Extract SVG vector data and JSON outline nodes during import and markdown conversion, rendering vector SVG mind maps and interactive hierarchical outline cards.
- **Industry-Standard Code Blocks**: Implement a dedicated code block component using `flutter_highlight` featuring language selection (30+ languages), syntax highlighting, line numbers, one-click copy with feedback, and auto-formatting.
- **Interactive Image Manipulation**: Add interactive selection outlines, draggable corner/edge resize handles, percentage presets (25%, 50%, 75%, 100%, Auto), context menu actions (copy, cut, delete), and system clipboard image paste (Cmd+V).

## Capabilities

### Modified Capabilities
- `notebook-tool`: Adds requirements for window titlebar traffic light clearance, unified light editor styling, mind map note rendering, enhanced code blocks, and interactive image manipulation.

## Impact

- `lib/tools/notebook/ui/notebook_page.dart`: Adds top safe padding to avoid macOS traffic lights.
- `lib/tools/notebook/ui/note_editor.dart`: Enforces light theme across toolbar and canvas, integrates interactive image editor, mind map embed, and enhanced code block embed.
- `lib/tools/notebook/markdown_converter.dart`: Handles SVG data URLs and mind map tree nodes.
- `scripts/evernote_import.py`: Extracts inline SVG data URLs and mindmap JSON from ENML notes.
- `pubspec.yaml`: Adds `flutter_svg` if needed for vector graphics.
