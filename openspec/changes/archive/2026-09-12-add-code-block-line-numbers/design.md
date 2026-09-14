## Context

See `proposal.md` - Why. The note editor utilizes `NoteCodeBlockComponentWidget` to render code blocks inline with a dark theme (`#0F172A`). Currently, only a single `TextField` is shown without line numbers.

## Goals / Non-Goals

**Goals:**
- Add a dedicated line numbers gutter to the left of the code editor.
- Guarantee that copying code (via copy button or cursor selection) contains 0 line numbers.
- Maintain vertical baseline alignment between gutter numbers and text lines.
- Support horizontal scrolling for long code lines with a fixed (sticky) gutter.
- Focus the code editor when tapping on the gutter.

**Non-Goals:**
- External dynamic syntax highlighting library integration (reserved for future enhancement).
- Per-line breakpoints or code folding.

## Decisions

### Decision 1: Dedicated Non-Selectable Gutter Column
Render the gutter as an independent `Container` to the left of the code `TextField` separated by a 1px border (`#334155`).
Because the gutter sits outside the `TextField` widget hierarchy, user drag selections and clipboard copy operations will never capture line numbers.

### Decision 2: Shared Typography Baseline
Define exact matching typography constants:
- `_fontSize = 13.0`
- `_lineHeight = 1.5`
- `_fontFamily = 'monospace'`
Both the gutter `Text` widget and the `TextField` will share these exact parameters and identical vertical padding (`top: 12, bottom: 12`) to ensure pixel-perfect baseline alignment.

### Decision 3: Dynamic Gutter Width and Right-Alignment
- Compute `_lineCount` from `'\n'.allMatches(_textCtrl.text).length + 1`.
- Right-align line number digits with an adaptive minimum width (`minWidth: 32` for <100 lines, auto-expanding for 100+ lines).

### Decision 4: Sticky Gutter with Horizontal Code Scrolling
- Keep the gutter fixed on the left.
- Wrap the code input area in a `SingleChildScrollView(scrollDirection: Axis.horizontal)` so long code lines scroll horizontally without breaking alignment or pushing the gutter offscreen.

## Risks / Trade-offs

- **[Risk] Font metric variance across platforms** → *Mitigation*: Explicitly set `height: 1.5` and standard fallback font list `['SF Mono', 'Menlo', 'Monaco', 'Courier New']`.
