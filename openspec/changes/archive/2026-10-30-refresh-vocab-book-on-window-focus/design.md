## Context

See `proposal.md` — Why. This section covers only what shapes the approach.

Relevant current state:

- `VocabStore` (`lib/tools/vocab_book/services/vocab_store.dart`) is a plain singleton over Drift (`NoteStore.instance.db`). It has no notification mechanism — not a `ChangeNotifier`, no `ValueNotifier`.
- `VocabBookPage` (`lib/tools/vocab_book/ui/vocab_book_page.dart:39`) loads once in `initState`, then re-loads only after its own actions (add/edit/delete/filter at lines 230, 314, 338).
- The browser popover and the standalone lookup window run in **separate processes** (`desktop_multi_window`), sharing the same SQLite file. Cross-process notification would need a channel the app does not have.
- The app already uses `windowManager.addListener` with a `WindowListener` subclass (`main.dart:503`, `main.dart:511`) for sub-window focus and main-window close. So the focus hook is an established pattern, not new machinery.
- `window_manager` 0.4.x exposes `WindowListener.onWindowFocus()`.
- `ScheduledNewsService extends ChangeNotifier` and `SettingsStore.themeModeNotifier` show the project's in-process broadcast idioms — both useless across processes, which is why this change does not use them.

## Goals / Non-Goals

**Goals:**
- Words added from another process are visible when the user returns to the app.
- No visible flashing, no lost scroll position, no lost filter or selection.

**Non-Goals:**
- Real-time push across processes (needs a reverse EventChannel or a local notification endpoint; rejected on cost/benefit).
- Refreshing other tool pages — only the vocabulary book is in scope, though the pattern is repeatable. If more pages need it, the shared mechanism should be extracted then, not preemptively now.
- Polling, or a timer of any kind.
- Making `VocabStore` a `ChangeNotifier` — it would suggest in-process subscription solves this, and it does not.

## Decisions

### Decision 1: Refresh on window focus, not on a channel

- **Choice**: `VocabBookPage` attaches a `WindowListener` and re-queries in `onWindowFocus()`.
- **Alternatives considered**:
  - Reverse `EventChannel` (child process → native → main window). Rejected: the project has no such channel; building one for this is disproportionate, and it only buys latency nobody asked for.
  - A local HTTP notification endpoint (mirroring the dictionary bridge). Rejected: same reasoning, plus an always-on listener to keep alive.
  - Database polling. Rejected: burns cycles and introduces a delay, solving a problem the focus signal already solves for free.
  - `ChangeNotifier` on `VocabStore`. Rejected outright: it is process-local, so it cannot see the popover's write. It would make the fix *look* done while not being done.
- **Rationale**: "user switched back to the app" is exactly the moment the data matters, and it is already observable.

### Decision 2: Compare, and only rebuild on an actual change

- **Choice**: after the focus query, compare the new entries against what is displayed; only `setState` when they differ. The comparison is on entry identity + the fields the list displays.
- **Alternatives considered**:
  - Always `setState`. Rejected: forces a rebuild on every focus, which is visible as a flash if the list is loading, and needless work.
  - Compare only counts. Rejected: an edit from elsewhere (mastery level, tags) would not change the count and would not show.
- **Rationale**: the refresh must be invisible when there is nothing new, which is the common case.

### Decision 3: Refresh re-applies the current filter and keeps the selection

- **Choice**: the refresh path goes through the same query the current view uses (whatever filter is active), and the selected entry is tracked by id so it survives.
- **Rationale**: a refresh that resets the user's filter is worse than no refresh; the spec pins both.

## Risks / Trade-offs

- **[Risk] `onWindowFocus` fires more often than expected** (e.g. on every click in some window managers). → Mitigated by Decision 2: an extra query with no change costs one Drift read and no rebuild.
- **[Risk] The listener keeps the page alive or leaks.** → It is added and removed with the page's lifecycle (`initState`/`dispose`), matching `main.dart`'s existing `WindowListener` usage.
- **[Risk] The refresh races with the user's own edit in progress.** → The query is async and applied only if the page is still mounted; on a conflict the freshest write wins, which is the same behaviour as a manual re-entry.

## Migration Plan

1. Add the focus listener and the change-checked refresh to `VocabBookPage`.
2. Verify by hand: add a word from the popover, switch to the app, see it.
3. Rollback: one file, no persisted data, no API change — reverting restores the previous behaviour exactly.

## Open Questions

- Whether the same treatment should extend to the notebook and ops pages. Deferrable; the design notes the shared mechanism should be extracted when a second page needs it rather than now.
