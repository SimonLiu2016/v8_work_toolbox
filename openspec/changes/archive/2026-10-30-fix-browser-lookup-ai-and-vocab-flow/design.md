## Context

See `proposal.md` — Why. This section covers only what shapes the approach.

Relevant current state:

- Three entry points dispatch the same deep link: `v8toolbox://lookup?text=…` — the bubble's "在桌面端打开" (`content.js:353`), "问 AI 深度解析" (`content.js:391`), and the right-click fallback (`background.js:48`).
- `AppDelegate.handleIncomingUrl` extracts only `text` and forwards it over `v8_work_toolbox/context_services` (`AppDelegate.swift:555`). No `mode` is parsed; there is no `vocab` host at all.
- `ContextServicesBridge.onLookup(String text)` → `main.dart` → `LookupWindowLauncher.open(text)` → `WindowController.create(arguments: 'lookup:<text>')` → child process `initState` → `_doLookup(text)` (dictionary first, unconditionally).
- `LookupPanelView` already has `_forceAi()` / `_forceDictionary()` / `_doLookup()` (`lookup_window.dart:143`). Only the last one is reachable from a deep link. `LookupCoordinator.forceAi` exists and is used by the in-window button.
- AI results are rendered with `Text(res.aiTranslation!)` at `lookup_window.dart:600`. `AppMarkdownView` is the established shared component — already used by the AI assistant, news briefings, disk reports, and notebook Q&A.
- Every sub-window is forced to `screen.visibleFrame` by `MainFlutterWindow.swift:33` inside `FlutterMultiWindowPlugin.setOnWindowCreatedCallback`. Measured: 1680×921 on a 1680×1050 logical display. This affects all five sub-window kinds, not just the lookup popover.
- Sub-window `arguments` prefixes are: `lookup:` (`lookup_window.dart:50`), `note:<id>` (`notebook_page.dart:1255`), `notebook`, `password-vault`, `ops-tool` (`registry.dart`).
- `VocabStore.insertFromDictionary` exists and takes pure word data; `existsWord` exists for the no-op case. No window needs to open for it.
- The vocabulary book is **not** currently refreshed when changed from another process — that is scoped to `refresh-vocab-book-on-window-focus` and deliberately excluded here.

## Goals / Non-Goals

**Goals:**
- A "ask AI" click reaches AI analysis without an intermediate dictionary result.
- A "add to vocabulary" click adds the word without opening a window.
- The lookup window renders AI analysis with the same Markdown component the rest of the app uses.
- Sub-windows open at sizes suited to their kind.

**Non-Goals:**
- Real-time cross-window refresh of the vocabulary book (separate change).
- Changing the `⌘D` hotkey path's cursor-following positioning — it already works.
- Restyling the lookup card, or improving dictionary/AI content quality.
- Discovering window sizes at runtime (e.g. from content): a declared table is enough and far simpler.

## Decisions

### Decision 1: Intent rides on the existing deep link as a parameter

- **Choice**: `v8toolbox://lookup?text=…&mode=ai`; absent or unrecognised `mode` means dictionary-first. New host `v8toolbox://vocab?text=…` for the add-only action.
- **Alternatives considered**:
  - A separate `lookup-ai` host. Rejected: it multiplies hosts for what is one intent with one parameter. `mode` also leaves room for future values without new surface.
  - Encoding intent in the text (e.g. a prefix). Rejected: fragile, and leaks the protocol into user-visible data.
- **Rationale**: backward compatible by construction — existing callers that omit `mode` keep exactly today's behaviour, which is what the right-click path and "open on desktop" want anyway.

### Decision 1a: A word added from the browser carries no definitions

- **Choice**: the vocab deep link stores the word alone (`definitions: []`, `examples: []`).
- **Alternatives considered**:
  - Look the word up on the way in so the entry is complete. Rejected twice over: it contradicts this change's own spec scenario ("without querying the dictionary"), and it would be near-useless here because the entry point is precisely the "not found in dictionary" case — a second dictionary lookup would most likely return nothing again.
  - Mark the entry "needs filling in" in the vocabulary book UI. Rejected for scope: it is a vocabulary-book UI improvement, not part of the deep-link fix, and this change already spans Dart/Swift/JS. Left as follow-up work.
- **Cost, accepted**: the vocabulary book will show entries with no definition until the user fills them in. That is the honest consequence of "add directly, don't look anything up" — the alternative is a silent dictionary call the user did not ask for.
- **Rationale**: the user's stated intent is "add this word now"; a complete entry is a different, slower request. A is the literal reading, and the cost is visible rather than hidden.

### Decision 2: vocab is a new host, not a mode of lookup

- **Choice**: `v8toolbox://vocab?text=…` performs the add directly and opens nothing.
- **Alternatives considered**:
  - `lookup?mode=vocab`. Rejected: it would reuse the lookup *window* pipeline to open a window that must immediately not-be-a-window. A separate host makes "no window" structural rather than a branch someone can delete.
- **Rationale**: the action has no UI at all; giving it its own host keeps that obvious at the call site.

### Decision 3: Each window declares its own size in Dart; the native callback stops sizing

- **Choice**: every sub-window's Dart entry point calls `windowManager.setSize(...)` with its own declared size during setup. `MainFlutterWindow.swift`'s creation callback keeps the styling (transparent titlebar, full-size content view, `isMovableByWindowBackground`) but no longer calls `setFrame(screen.visibleFrame)`. Declared sizes: `lookup:` 420×520, `note:` 900×650, `notebook` 1100×700, `ops-tool` 1200×800, `password-vault` 900×600.
- **Alternatives considered**:
  - A size table in `MainFlutterWindow.swift` keyed on arguments prefix. Rejected **because it cannot work**: the `onWindowCreatedCallback` receives only a `FlutterViewController`, and the package does not expose the window's `arguments` from it (`CustomWindow.init(configuration:)` accepts the config but never stores it; nothing on the resulting `NSWindow` carries it). The native side cannot know which kind of window it is sizing.
  - Remove the native `setFrame` and let every window be the package default 800×600. Rejected: the package default is itself a guess, and each window has a different density.
  - Put the size into the `arguments` string. Rejected: `WindowController.create` has no size parameter, so this would mean inventing a serialisation format both sides parse — for something Dart can just say directly.
- **Why the first draft was wrong, and how** (kept for the record): the original draft of this change chose the Swift table and rejected `windowManager.setSize` on the grounds that "windowManager's behaviour in child processes is a new unknown". That premise was false and checkable — `lookup_window.dart`'s `_setupWindowStyle()` already calls `windowManager.setAlwaysOnTop/setTitle/setTitleBarStyle` in the child process, four calls above where the size would go. The project itself was the counterexample; it should have been checked before the alternative was rejected.
- **Consequence, accepted**: with the native `setFrame` gone, a sub-window that declares no size falls back to the package default of 800×600 instead of today's full-screen. All five existing kinds declare a size, so nothing regresses; and 800×600 is a far more honest default for a future window than filling the screen.

### Decision 4: The lookup window takes an initial mode, defaults to dictionary

- **Choice**: `LookupWindowApp(initialQuery:, initialMode:)`; `LookupPanelView` runs `_doLookup` or `_forceAi` in `initState` based on it. Default `dict`.
- **Rationale**: all three code paths (`_doLookup`, `_forceAi`, `_forceDictionary`) already exist; the change is only which one a fresh window starts in.

## Risks / Trade-offs

- **[Risk] Words added from the browser have no definitions, so the vocabulary book shows sparse entries.** → Accepted per Decision 1a. Surfacing "needs filling in" in the vocabulary book is follow-up work, deliberately not folded into this change.
- **[Risk] A new sub-window kind opens at the package default because nobody declared a size.** → Mitigated by the spec scenario that pins the per-kind sizes, and by 800×600 being a defensible default now that it is no longer full-screen. Declaring a size is one line at the window's own entry point.
- **[Risk] `mode=ai` makes a network call the user didn't expect.** → Accepted: the user explicitly clicked "ask AI". `mode` is only ever set by that button.
- **[Risk] Rendering AI output as Markdown could break results that are plain prose with stray asterisks.** → Mitigated by the spec's second scenario: no Markdown constructs means identical rendering. `AppMarkdownView` already handles this for four other surfaces.
- **[Risk] The vocab deep link adds a duplicate when the user clicks twice.** → `existsWord` guard in the scenario; insertion is idempotent by word.

## Migration Plan

1. Add the deep-link parameters and host (`AppDelegate` → `ContextServicesBridge` → `main.dart` → `LookupPanelView`). Dictionary-first behaviour unchanged when `mode` is absent.
2. Switch the bubble's two buttons to the new deep links.
3. Swap the lookup window's AI block to `AppMarkdownView`.
4. Replace the unconditional `setFrame(screen.visibleFrame)` with the size table.
5. Rollback: all four steps are independent; reverting any one restores that surface's previous behaviour. No persisted data is touched.

## Open Questions

- Whether the popover should remember its last size instead of always opening at 420×520. Deferrable: the spec only pins the declared default; persistence would be a later refinement.
- Whether other sub-windows (e.g. a future search panel) should appear at popover size too. Deferrable — the table makes it a one-line addition.
