## Why

Code blocks in the notebook editor currently lack line numbers, making it harder to read and navigate multi-line code snippets. Introducing a dedicated line numbers gutter enhances readability and gives the code block a professional, modern IDE appearance while keeping the copied and selected code clean.

## What Changes

- Add a sticky line numbers gutter (`Gutter`) to the left of the code block editor in `NoteCodeBlockComponentWidget`.
- Ensure line numbers dynamically update in real time based on hard newlines (`\n`) in the code.
- Align line numbers with code lines with pixel-level vertical baseline precision by sharing identical typography (`fontFamily: monospace`, `fontSize: 13`, `height: 1.5`).
- Ensure line numbers are rendered in a separate, non-selectable gutter so that dragging to select code or clicking the "Copy" button never includes line numbers.
- Provide horizontal scrolling for long lines to preserve code formatting and guarantee 1:1 line alignment with the gutter.
- Tapping on the gutter automatically requests focus on the code editor.

## Capabilities

### Modified Capabilities
- `notebook-editor`: Enhance code block rendering to include an aligned line numbers gutter without contaminating code selection or copy payloads.

## Impact

- `lib/tools/notebook/ui/components/note_code_block_component.dart`: Code block UI structure and line number calculations.
- `test/code_block_line_numbers_test.dart`: Unit and widget tests for line numbers calculation, rendering, and copy purity.
