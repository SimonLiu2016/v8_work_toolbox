## Context

See `proposal.md` — Why for the measured failure path. This section covers only what shapes the approach.

Relevant current state:

- `note_editor.dart:428` `_handlePaste()` already does the full bitmap path: `osascript` → `class PNGf` → `NoteStore.saveAttachment` → `_insertImageAtCursor(path)`. It has never executed (see proposal).
- `note_editor.dart:573` binds `⌘V`/`ctrl+V` to `_handlePaste` via `CallbackShortcuts`. This is dead code and will be removed.
- `AppFlowyEditor` (`appflowy_editor` 6.2.0) mounts `Focus(onKeyEvent: _onKeyEvent)` on the very `focusNode` the caller passes (`keyboard_service_widget.dart:127`). `_onKeyEvent` iterates `widget.commandShortcutEvents`, and returns `handled` on the first match — which stops dispatch before any outer `Shortcuts` is consulted.
- `AppFlowyEditor(commandShortcutEvents: ...)` is a public parameter; omitting it selects `standardCommandShortcutEvents`, which contains `...pasteCommands` (`pasteCommand`, `pasteTextWithoutFormattingCommand`) at `standard_block_components.dart:155`.
- The package's paste handler reads only `kTextPlain`; `AppFlowyClipboard.getData()` hard-codes `html: null`, so its `pasteHtml` branch is unreachable. Its `pastePlainText` and `_pasteCommandHandler` are **private** to the package.
- The primitives needed to reimplement plain-text pasting are public: `EditorCopyPaste.pasteSingleLineNode/pasteMultiLineNodes/deleteSelectionIfNeeded` (`copy_paste_extension.dart`, exported through `editor_component.dart`), `getDeltaAttributesInSelectionStart` (`text_commands.dart` → `command/transform.dart` → `editor.dart`), and `imageNode`/`paragraphNode` from core.
- Toolbar already has an insert-image action (`note_editor_toolbar.dart:94`) that goes `FilePicker` → `onSaveAttachment` → `NoteStore.saveAttachment` → `imageNode(url:)`. That is the path the pasted image must match.
- No `url_launcher` dependency; `package:http` is already a direct dependency. External URLs elsewhere are opened with `Process.run('open', [...])`.

## Goals / Non-Goals

**Goals:**
- Make `⌘V` and a toolbar button both insert a clipboard image, with storage and rendering identical to file-inserted images.
- Preserve plain-text pasting exactly when the paste command is taken over.
- Make every failure stage visible.

**Non-Goals:**
- Drag-and-drop of image files onto the editor (separate concern; the toolbar button already covers the file case).
- Batch paste of multiple images (clipboard bitmaps are single).
- Resizing or compressing large images — explicitly out of scope per the user.
- Routing image downloads through the application's proxy (decided below).

## Decisions

### Decision 1: Take over the editor's paste command rather than intercept above it

- **Choice**: pass an explicit `commandShortcutEvents` list = `standardCommandShortcutEvents` minus the two paste commands, plus our own `⌘V` handler. Dispatch then reaches us because we *are* the paste command.
- **Alternatives considered**:
  - Keep `CallbackShortcuts` and try to win ordering. Rejected: the package's `Focus.onKeyEvent` sits on the focus node itself and returns `handled`, so an outer `Shortcuts` is structurally unreachable. Ordering cannot be fixed from outside.
  - `AppFlowyKeyboardServiceInterceptor`. Rejected: it intercepts `TextEditingDeltaInsertion` (IME text insertion), not command shortcuts — wrong layer for `⌘V`.
  - Fork/patch the package. Rejected: a hosted dependency; every upgrade would need a re-pin and the change is not package-general.
- **Rationale**: the parameter is the package's own extension point; using it means no reliance on dispatch order and no fork.

### Decision 2: Implement plain-text pasting ourselves, from public primitives

- **Choice**: when the clipboard has no image, our handler performs the text paste: `deleteSelectionIfNeeded()` → URL/phone detection with `href` attribute insertion → split lines → `paragraphNode` → `pasteSingleLineNode`/`pasteMultiLineNodes`, inheriting `getDeltaAttributesInSelectionStart()`.
- **Alternatives considered**:
  - Delegate to the package's handler when there is no image. Rejected: `_pasteCommandHandler` and `pastePlainText` are private, so there is nothing to call. Keeping the package's `pasteCommand` *and* ours is also impossible — only one handler runs per matched command.
  - Insert raw text without URL/phone detection. Rejected: a visible regression; users who paste a link expect a link.
- **Cost, accepted**: we now own text-paste behaviour. The package's version carries a `// TODO remove this deletion after refactoring pasteHtmlIfAvailable` comment, so it is not stable ground either; our copy is testable, which theirs is not from outside.

### Decision 3: `⌘⇧V` behaves like the text branch of `⌘V`

- **Choice**: drop `pasteTextWithoutFormattingCommand` and let `⌘⇧V` fall through to the same handler (which inserts plain text anyway when there is no image).
- **Alternatives considered**: keeping a distinct plain-text-only variant. Rejected: the difference is "strip formatting from rich clipboard content", but the clipboard content we can read is text only (`html` is `null`), so there is no rich content to strip — the two commands would be identical in our implementation. Two identical commands is worse than one.

### Decision 4: Bitmap detection stays native, wrapped in a testable service

- **Choice**: new `ClipboardImageService` owns (a) the `osascript` `class PNGf` probe, (b) the image-URL detection and download, (c) a `@{1s}` timeout on each. The widget layer only orchestrates: get image → `saveAttachment` → insert → snackbar.
- **Alternatives considered**:
  - Read the bitmap via Flutter's `Clipboard.getData('image/png')`. Rejected on desktop: Flutter's clipboard API exposes text reliably but image data only partially across desktop platforms, whereas the existing `osascript` probe is proven on this machine (it produced a 46137-byte PNG from a live WeChat screenshot during exploration).
  - Put the `osascript` call inline in the widget. Rejected: it blocks the UI isolate for the duration of the call and cannot be unit-tested.
- **Rationale**: the probe is the part most likely to break (OS permissions, clipboard format changes); it must be replaceable and testable in isolation.

### Decision 5: Image URLs fetched directly, not through the app proxy

- **Choice**: download with a plain `http.get`, no proxy channel.
- **Rationale**: images are normally served from CDNs reachable without a proxy; sending them through mihomo adds latency for no benefit. Recorded in the spec as an explicit scenario so a future reader does not "fix" it into a bug report.

## Risks / Trade-offs

- **[Risk] Taking over paste regresses text pasting** (missed URL detection, lost selection attributes, wrong line splitting). → The spec states plain-text behaviour is preserved; tasks require a unit test mirroring the package's cases (multi-line, URL, phone, selection attributes, selection replacement) against our handler.
- **[Risk] The package upgrades and changes `standardCommandShortcutEvents` or removes the parameter.** → We filter by identity (`!= pasteCommand`), so a removed symbol is a compile error rather than a silent behaviour change; the toolbar button keeps working either way.
- **[Risk] `osascript` probe blocked by macOS permissions** (Automation consent). → Fails as a visible snackbar naming the clipboard step, not silence. Same consent model the project already relies on for AppleScript elsewhere.
- **[Risk] Downloading a URL from the clipboard is an SSRF-shaped action** (a webpage could put `http://192.168.x/…` on the clipboard). → Bounded by: user-initiated only, response must parse as a supported image type, size cap, and timeout. Recorded as accepted for a single-user local app; no credential-bearing requests are made.
- **[Risk] Our text paste duplicates package logic that may later get fixed upstream.** → Deliberate: the alternative is a private API we cannot call. Noted in Decision 2.

## Migration Plan

1. Add `ClipboardImageService` (probe + URL fetch + timeouts) with unit tests, independent of UI.
2. Take over the paste command in `note_editor.dart`; implement the text branch; remove the dead `CallbackShortcuts` binding.
3. Add the toolbar paste-image button.
4. Wire snackbar feedback for every failure stage.
5. Rollback: the changes are confined to `note_editor.dart`, `note_editor_toolbar.dart`, and the new service. No persisted data changes, so reverting the commits restores the previous behaviour exactly (including the broken paste).

## Open Questions

- Whether the toolbar button should read the clipboard once on hover to enable/disable itself. Deferrable: the spec defines what activating it does, not its idle state; a disabled-looking button that becomes live on hover is a later refinement.
- Whether to show a transient "saved" confirmation on success. Deferrable; a snackbar per paste may be noisier than the existing insert-image button, which shows nothing on success. Leaning toward silence on success, since the image appearing in the document is itself the feedback.
