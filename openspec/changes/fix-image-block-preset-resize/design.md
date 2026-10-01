## Context

See `proposal.md` — Why for the measured failure path. This section covers only what shapes the approach.

Relevant current state:

- `note_editor.dart:194` registers `ImageBlockKeys.type: ImageBlockComponentBuilder(showMenu: true, menuBuilder: …)` — the package's builder, which internally creates `ResizableImage`.
- `ResizableImage`'s state caches `widget.width` into `imageWidth` inside `initState` and never re-reads it (`resizable_image.dart` has no `didUpdateWidget`). The drag path mutates `imageWidth` directly and calls `setState`, so it works; the preset path writes the document tree, so it does not.
- `appflowy_editor` latest on pub.dev is 6.2.0 — the version already in use. No upstream fix exists.
- The package exposes enough public surface to write our own builder: `BlockComponentBuilder.build(BlockComponentContext)`, `BlockComponentContext.node`, and the `Node`/`Selection`/`Transaction` APIs. It does **not** expose a way to replace `ResizableImage`, give it a `key`, or subclass `ImageBlockComponentWidgetState` (`createState()` returns the concrete type).
- The existing overlay (`note_image_menu.dart`) is built by `menuBuilder` and writes `ImageBlockKeys.width` / `align` through `editorState.transaction.updateNode`. That mechanism is correct and stays.
- The overlay's `setWidth` uses `MediaQuery.of(context).size.width` — the **window** width, not the editor content width — while the drag path uses the state's pixel value. Both must be reconciled.
- `openspec/specs/notebook-editor`'s existing image scenario describes a "right-click context menu" and an "Auto" preset; the implementation is a hover overlay with four presets and no Auto. The delta corrects this.

## Goals / Non-Goals

**Goals:**
- Preset percentage choices visibly change the image width.
- Drag-to-resize keeps working, with the same feel as before.
- Presets and drag measure width against the same reference (editor content area).
- No schema or persisted-attribute change.

**Non-Goals:**
- Adding an "Auto" preset (never implemented; the spec text is corrected rather than the feature added).
- Image cropping, rotation, filters.
- Changing attachment or mind-map block rendering.
- Forking `appflowy_editor` or pinning a patched copy.

## Decisions

### Decision 1: Write our own image block component rather than work around the caching

- **Choice**: a new builder + widget + state under `lib/tools/notebook/ui/components/note_image_block_component.dart`, registered for `ImageBlockKeys.type`; `ImageBlockKeys.width` read fresh from `node.attributes` on every build, plus `didUpdateWidget` to resync the drag-in-progress state.
- **Alternatives considered**:
  - Force `ResizableImage` to rebuild by changing something in its ancestry. Rejected: its `key` is null and its tree position is fixed, so nothing reachable from outside changes its identity.
  - Reach `imageWidth` through `state.imageKey.currentState`. Rejected: that `GlobalKey` is attached to the wrapping `Padding`, not to `ResizableImage`.
  - Subclass `ImageBlockComponentWidgetState` and override `build`. Rejected: `createState()` returns the concrete type, and the state depends on package-private members (`SelectableMixin`, `BlockComponentConfigurable`, `imageKey`).
  - Upgrade the package. Rejected: 6.2.0 is already latest.
- **Rationale**: the defect is "a widget caches its input once", and the only durable fix is to own the widget. The public builder API exists precisely for replacing a block component.

### Decision 2: Reproduce drag-to-resize 1:1 instead of simplifying it

- **Choice**: copy the package's drag behaviour faithfully — two 5 px edge hot zones, handle visible only while hovered, live `moveDistance` preview during drag, commit on `onHorizontalDragEnd`, `max(minWidth, …)` floor of 30 px, and the `offset *= 2.0` correction when the image is centre-aligned.
- **Alternatives considered**:
  - A simplified drag (no live preview, or commit on every update). Rejected: a half-familiar drag is more irritating than none, and the user explicitly asked to keep drag.
  - Dropping drag and keeping only presets. Rejected: that removes an existing capability to fix a bug.
- **Cost, accepted**: ~60 lines of gesture handling that we now own, including the edge cases the package already solved. Documented in code with the reasons a future reader would otherwise "simplify" away.

### Decision 3: One reference width, shared by both paths

- **Choice**: measure against the editor content area — obtained from the block component's own `RenderBox` width, falling back to the `LayoutBuilder`/`MediaQuery` width of the content region. Both `setWidth(percentage)` (presets) and the drag commit use it.
- **Alternatives considered**:
  - Keep presets on `MediaQuery` and drag on its own value. Rejected: that is the current inconsistency, and it is why "drag to widest" and "100%" disagree.
  - Store a percentage in attributes instead of pixels. Rejected: it changes the persisted shape for existing notes, requiring a migration, for no user-visible gain.
- **Rationale**: the discrepancy is a real (if minor) defect; fixing it while we own the component costs nothing extra.

### Decision 4: Keep writing the same attributes

- **Choice**: `ImageBlockKeys.width` (double, pixels) and `ImageBlockKeys.align` (string) keep their current meaning; the overlay keeps using `transaction.updateNode`.
- **Rationale**: notes already stored with a `width` attribute must render at that width once presets work — that is precisely the point of the fix. A migration would also make the fix reversible only with data work.

## Risks / Trade-offs

- **[Risk] Our component diverges from the package's, so a package upgrade could leave us behind behaviour fixes.** → Accepted and inverted: we are already blocked by a bug the package has not fixed. Our copy is ~200 lines, reviewed, and covered by tests for the parts that do not need a live editor.
- **[Risk] Reimplementing drag reintroduces subtle bugs the package had already fixed** (e.g. the ×2 centre compensation). → The compensation and the 30 px floor are reproduced deliberately and called out in comments; a test pins the width arithmetic.
- **[Risk] Block selection / focus behaviour differs from the packaged image block.** → The packaged image block relies on `SelectableMixin` and `BlockSelectionContainer`, which are public (`src/render/selection/selectable.dart`, block components' selection container). Our widget keeps using `BlockSelectionContainer`; if selection proves to need the mixin, that is a follow-up rather than a silent loss.
- **[Risk] The overlay's own copy-path / delete actions touch `node`, which our widget also renders.** → Unchanged: `menuBuilder` still receives the live `widget.node` from our build, exactly as before.

## Migration Plan

1. Add `note_image_block_component.dart` with the builder + widget + state + resizable logic.
2. Switch `note_editor.dart`'s `ImageBlockKeys.type` registration to it; keep `showMenu` + `menuBuilder` wiring.
3. Repoint `note_image_menu.setWidth` at the shared content-area reference.
4. Verify by hand: presets change width, drag still resizes, and "drag to widest" ≈ "100%".
5. Rollback: the change is confined to one new file, one line of registration, and one function in the overlay. Reverting restores the packaged builder — including the broken presets, which is the known-previous state.

## Open Questions

- Whether our image block should also honour `ImageBlockKeys.height`. The package reads it but nothing writes it; out of scope here.
- Whether the same defect affects other block types that cache a `width`-like attribute. Not investigated — no other block in this project uses a cached dimension.
