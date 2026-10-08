## Context

See `proposal.md` — Why for the fault path. Relevant current state and constraints:

- `note_editor.dart:489` `_handlePaste` is the custom `⌘V` handler installed via `_buildCommandShortcutEvents()` (`:592`), which replaces the package's `pasteCommand` / `pasteTextWithoutFormattingCommand` in `standardCommandShortcutEvents` (filtered by identity, `:595`).
- `note_editor.dart:504` `_pasteClipboardImage()` returns `_PasteOutcome`, but only ever returns `handled` (`:529`) or `failed` (`:518`, `:533`). `_handlePaste:493` gates on `!= notAnImage`, so the text branch (`:550` `_pastePlainText`) is unreachable.
- `clipboard_image_service.dart:138` `readImage()` already reads the clipboard **text** at `:142` via the injectable `clipboardTextReader`, to test for an image URL or a local path — then discards it. `_pastePlainText` (`note_editor.dart:551`) reads the clipboard a second time through `Clipboard.getData`, bypassing the injectable reader.
- `_pastePlainText` forwards to the top-level `insertPlainTextPaste` (`:38`), which is `@visibleForTesting` and covered by 9 cases in `test/note_editor_paste_text_test.dart`. Those cases pass because the leaf function is correct; they never exercise the dispatcher that decides whether it is called at all.
- `note_editor.dart:603` returns `KeyEventResult.handled` unconditionally from the custom paste command.
- The package's own `pasteTextWithoutFormattingCommand` is filtered out with no replacement, so `⌘⇧V` currently does nothing (`tasks.md` 2.5 was never checked off).

## Goals / Non-Goals

**Goals:**
- Make the text fallback reachable, and keep it reachable — the dispatcher gets tests, not just the leaf.
- Remove the double clipboard read so the two branches cannot disagree and so the test double covers the text branch.
- Make the keystroke un-swallowed when we have nothing to insert.
- Fix the misleading comment and the unfulfilled `⌘⇧V` note.

**Non-Goals:**
- Rewriting the plain-text insert itself (`insertPlainTextPaste`) — it is correct and tested; this change is about reaching it.
- Changing the three image sources (bitmap / URL / local path) or their failure taxonomy.
- Adding genuine URL/phone auto-linking. The taken-over command never linked (package's `maybeConvertToUrlOrPhone` is unreachable — `note_editor.dart:43-52` documents why), and this change preserves that.
- Right-click context-menu paste, drag-and-drop, multi-image paste (carried over from the prior change's non-goals).

## Decisions

### Decision 1: Fix the mapping at the dispatcher, not by reshaping the service's result type

- **Choice**: `readImage()`'s "no image at all" outcome becomes a distinct, named outcome in the mapping layer, so `_handlePaste` can tell "no image — go paste text" from "there was an image but it failed" (which keeps its snackbar). The generic `_PasteOutcome` no longer has to encode both, and the plumbing hands the already-read clipboard text to the text branch.
- **Alternatives considered**:
  - Repoint the existing `failed` arm to also mean "no image". Rejected: that is precisely the conflation that caused the bug. Keeping one value that means two things guarantees the same class of bug returns, and the next reader has no way to tell which arm they are in.
  - Rebuild `ClipboardImageResult` as a three-state sealed type (`image` / `noImage(clipboardText)` / `failure(reason)`). Rejected *for now* as it rewrites the service's public contract and forces churn across 20+ existing service tests, while the actual defect is one arm in the dispatcher. Recorded as a follow-up if a third paste concurrency concern appears (e.g. concurrent clipboard reads from the toolbar button and the shortcut).
  - Suppress the keystroke by returning `ignored` from the handler. Rejected: on macOS this is what lets the system beep or a parent handler act on a keystroke we already consumed; the cleaner contract is that we only claim the keystroke when we act on it. Applied in Decision 3.
- **Rationale**: the smallest change that removes the ambiguity rather than relocating it.

### Decision 2: Pass the clipboard text the service already read to the text branch

- **Choice**: the "no image" outcome carries the clipboard text that `readImage()` obtained (possibly null/empty), and `_pastePlainText` uses it instead of calling `Clipboard.getData` again.
- **Alternatives considered**:
  - Leave the second read in place. Rejected: it is a redundant platform-channel round trip, it silently escapes the injected `clipboardTextReader` test double (so the text branch is untestable through the dispatcher path), and it opens a window where the two reads disagree — the handler would paste text that was not what the image decision was based on.
  - Read the clipboard once at the top of `_handlePaste` and pass it down into the service. Rejected: it inverts the dependency (the widget starts knowing about clipboard formats) and makes every service test have to supply a clipboard it may not care about.
- **Rationale**: the data is already in hand; threading it through costs one field and buys both determinism and testability.

### Decision 3: Only claim the keystroke when the paste does something

- **Choice**: the custom command's handler returns `handled` after an action (image inserted, text inserted) and `ignored` when there was nothing to act on (no text, no image).
- **Alternatives considered**:
  - Always `handled`, as today. Rejected: it is how the previous version of this bug became invisible — an early `return` in our handler with `handled` outside it swallows the key without a trace.
  - Always `ignored` and let the system re-dispatch. Rejected: double-paste risk when a parent handler also handles `⌘V`.
- **Rationale**: aligns the keystroke's fate with whether we did anything, so "nothing happened" is at least visible to the user (system beep / no-op) rather than silently dropped. Note this is a macOS-level nicety, not a correctness requirement — covered by the "not swallowed" scenario in the spec.

### Decision 4: `⌘⇧V` maps to the same handler, as the prior change's Decision 3 intended

- **Choice**: the filtered `pasteTextWithoutFormattingCommand` is replaced by mapping `⌘⇧V` onto our own handler rather than being dropped.
- **Alternatives considered**:
  - Leave it dropped. Rejected: `tasks.md` 2.5 records the intent to route it to the same handler, and it is currently a dead keystroke — a user pressing `⌘⇧V` gets nothing, which reads as the same bug the user just reported.
  - Implement a distinct plain-text-only variant. Rejected: same reasoning as the prior Decision 3 — we can only read text from the clipboard (`html` is `null` in the package's clipboard data), so a "without formatting" variant would be byte-identical.
- **Rationale**: completes the prior change's stated intent; makes the two paste shortcuts behave consistently in both the image and text cases.

### Decision 5: The dispatcher gets its own tests, not more leaf tests

- **Choice**: add a test group that exercises `_handlePaste` end-to-end with three clipboard states — text only, bitmap, empty — asserting each of the three exits, plus that `⌘⇧V` reaches the same handler.
- **Alternatives considered**:
  - Only add a regression test for the reported symptom (text-only → inserted). Rejected: it would leave the other two exits and the `⌘⇧V` mapping unverified, and the prior change already showed that leaf-only coverage coexists happily with a dead dispatcher.
  - Test through the real widget tree and synthetic key events. Rejected for now: it needs a mounted `AppFlowyEditor` with a real focus node and `NoteStore` on disk; the injection points the service already exposes (`processRunner`, `clipboardTextReader`, `httpClientFactory`) let us test the dispatcher's decisions without that. Recorded as a possible later addition.
- **Rationale**: tests must sit at the layer where the bug was.

## Risks / Trade-offs

- **[Risk] Fixing the fallback changes paste behaviour for existing users** — text paste starts working where it silently did not. → This is the fix, not a regression; the prior behaviour was a defect since `d131b75`. The change to `insertPlainTextPaste` itself is zero.
- **[Risk] Threading clipboard text through the result invites a null-text edge case** (clipboard text reader returns null when the bitmap path succeeded). → The text branch is only reached when there is no image, and the "no image" outcome always comes from a path that read the text; the handler still treats null/empty as nothing-to-do and does not claim the keystroke.
- **[Risk] Returning `ignored` lets a parent handler double-handle the paste** in some future widget nesting. → The notebook editor is the only place this command list is installed; verified no outer `Shortcuts`/`CallbackShortcuts` wraps the editor (`lib/tools/notebook/` has none, per the investigation).
- **[Risk] The double-read removal changes `ClipboardImageService`'s shape**, touching 20+ service tests. → Either additive (carry the text on the existing no-image outcome) or a small query method; the three source branches and the failure taxonomy are untouched. Task 2 spells out which.
- **[Risk] Same class of bug recurs** — a dispatcher arm that never executes. → Mitigated structurally: the service no longer returns a value the mapping layer must remember to translate, and Decision 5's tests execute all three exits on every test run.

## Migration Plan

1. Adjust the service's no-image outcome to carry the clipboard text (small, additive).
2. Repoint the dispatcher's mapping so "no image" is its own arm; thread the text into the text branch.
3. Make the handler's `KeyEventResult` reflect whether it acted; map `⌘⇧V` to the same handler.
4. Add dispatcher tests for the three exits and `⌘⇧V`; run the full suite and compare the failure set against the pre-change baseline.
5. Fix the stale comment at `note_editor.dart:546` and the spec wording via the spec delta in this change.
6. Rollback: all edits are confined to `note_editor.dart` and `clipboard_image_service.dart`; no persisted data or schema change, so reverting restores the current behaviour exactly.

## Open Questions

- Whether `readImage()`'s result type should eventually become a proper three-state sealed type (Decision 1, second alternative). Deferred because nothing else concurrently reads the clipboard today; revisit when a second paste concurrency concern appears.
- Whether the dispatcher should also be covered by a widget-level test with real synthetic key events. Deferred; the injection-point tests cover the decisions, and a widget test adds a `NoteStore` dependency.
