## Context

See `proposal.md` — Why for the fault path. Current state that shapes the approach:

- `local_dictionary_bridge.dart:192` resolves via `YoudaoService.lookupFull` (or the test-injected `_resolver`), then serialises **only** `result.allDefinitions` at `:206`. `DictionaryResult.meanings` — the grouped structure the desktop lookup panel (`lookup_window.dart:577`) and「存为笔记」(`:309`) both render — is discarded at this boundary.
- `content.js` therefore receives `{word, matched, phonetic, audioUrl, definitions}` and re-derives part of speech with `/^([a-z]+\.)\s*(.*)$/i` at `:449` (`content.js`). Examples are unreachable, not merely unrendered.
- Youdao's response for a single word carries `ec.word[].trs[]` (each `l.i` like `"adj. 短暂的；…"`), `blng_sents_part.sentence-pair[]` (3 bilingual examples), `simple`/`fanyi` fallbacks, and **no phrase field** (verified by walking every key of a real response: no `phrase`/`phrs`/`collocation`/`idiom` anywhere).
- `youdao_service.dart:117` attaches `examples` to `meanings[0]` only, from a `take(3)` list shared across all groups. That is a pre-existing quirk of the desktop path; it bounds how much the bubble can show, but does not block this change.
- Bubble is a 340px-wide card with `max-height: 220px` (`content.js`). It must stay usable: grouped POS + definitions + examples cannot all be shown at full length.
- Bridge response is consumed by `background.js:handleFetchDictionary` (which re-shapes it) and directly by `test/local_dictionary_bridge_test.dart:152` (which asserts the flat list). Both keep working if `definitions` is untouched and `meanings` is added.

## Goals / Non-Goals

**Goals:**
- The bubble receives and renders the grouped structure the bridge already has in hand.
- Backwards compatibility: flat `definitions` stays, and the bubble degrades to today's rendering when `meanings` is absent.
- Examples reach both the bubble and the vocabulary entry (the `addToVocab` path already accepts `examples`; `content.js` never sends them).
- Record the "no phrase data" fact where a future reader will look for it.

**Non-Goals:**
- Sourcing commonly-used phrases (no data source carries them; would need a new provider or AI).
- Fixing `youdao_service.dart`'s examples-on-first-group-only quirk or its hardcoded `take(3)`.
- Changing the desktop lookup panel,「存为笔记」, or the vocabulary schema.
- Phrase-specific part-of-speech labelling (the source has none for phrases; out of scope).

## Decisions

### Decision 1: Add a field, don't replace the flat list

- **Choice**: `/dictionary` gains `meanings` (`[{partOfSpeech, definitions, examples}]`); `definitions` stays byte-identical.
- **Alternatives considered**:
  - Return only `meanings` and let the client flatten. Rejected: breaks the installed extension and the existing test, with no upside — the flat list is genuinely useful to a simple client.
  - Return an HTML/markdown blob pre-rendered by the desktop app. Rejected: leaks presentation into the bridge, and the bubble's dark-mode styling lives in `content.js`.
- **Rationale**: the bridge's job is to carry the desktop data; presentation stays in the bubble.

### Decision 2: Bubble prefers `meanings`, falls back to flat

- **Choice**: `content.js` renders from `meanings` when present; otherwise the existing flat path unchanged.
- **Alternatives considered**:
  - Require `meanings` and show an error otherwise. Rejected: a stale desktop build (bridge older than extension, or vice versa) would turn every lookup into a failure for no reason. The extension is unpacked and reloads independently of the app.
  - Always render flat, add a separate "details" fetch. Rejected: a second round trip to fill what the first response already contains.
- **Rationale**: two versions of the two components will coexist on this machine during rollout.

### Decision 3: Examples shown bounded, not truncated mid-sentence

- **Choice**: show the group's examples when non-empty, capped by count (and clipped by the bubble's existing `max-height` scroll), with no "show more" affordance.
- **Alternatives considered**:
  - Collapse examples behind a toggle. Rejected: hidden-by-default means the reported problem ("例句没有") remains unremedied for the common case.
  - Show full text, let `max-height` scroll handle it. Rejected: the bubble's first screen would be examples, pushing definitions out of view — the reverse of the reported priority.
- **Rationale**: definitions stay primary; examples are visible without a click and bounded so they cannot dominate.

### Decision 4: Vocabulary write gains examples from the bubble's own data

- **Choice**: `content.js` keeps the resolved `examples` on `resolvedData` and passes them in the `addToVocab` message; `background.js` already forwards `examples`; the bridge already accepts it.
- **Alternatives considered**:
  - Let the bridge re-resolve when `examples` is missing (as it already does for `definitions` at `bridge:274`). Rejected: the bubble already has the data; re-resolving is a wasted lookup and makes the write depend on a source that may have changed.
- **Rationale**: the entry should carry what the user just saw.

### Decision 5: The phrase gap is documented in the spec, not worked around

- **Choice**: a scenario stating the bubble has no phrases section because the source has none, marked as a deliberate absence.
- **Alternatives considered**:
  - Add an "AI 常用短语" button. Rejected: violates `fast-dictionary-routing`'s "SHALL NOT automatically invoke slow AI completion", and would make every lookup slower to fix a cosmetic gap.
  - Say nothing. Rejected: this exact question was asked again after being investigated once; a silent gap invites repeat investigation.
- **Rationale**: the cheap fix is a durable note, and the note belongs in the capability the next reader will check.

## Risks / Trade-offs

- **[Risk] Bridge and extension drift during rollout** — extension updated but app not rebuilt, or vice versa. → Mitigated by Decision 2 (fallback) and Decision 1 (additive field). Rebuild + extension reload are both real-machine steps in the task list.
- **[Risk] Grouped data with an empty `partOfSpeech`** (phrases) renders as an unlabelled group and looks broken. → Accepted: it matches the desktop panel's behaviour for the same data; labelling is out of scope. The bubble renders the group's definitions normally.
- **[Risk] `examples` attached to the first group only** makes later groups look example-less. → Accepted as pre-existing desktop behaviour; noted in the spec's example scenario as "the dictionary result contains examples", not "each group's own examples".
- **[Risk] Extension is plain JS with no unit-test harness** — the render change is only covered by real-machine checks. → Task list includes explicit per-scenario manual verification, matching how the extension has always been verified (`add-notebook-clipboard-image-paste` 5.3–5.7 precedent).

## Migration Plan

1. Bridge: add `meanings` to `/dictionary`; keep `definitions` unchanged. Add a test asserting both.
2. Extension: `background.js` forwards `meanings` and `examples`; `content.js` renders grouped + examples with flat fallback, and passes examples to `addToVocab`.
3. Rollback: revert the four files; the response's extra field is ignored by the old extension, and the old bridge's response lacks `meanings`, which the new extension falls back on. No persisted data or schema change.

## Open Questions

- Where commonly-used phrases should come from, if wanted: a provider that carries them, or AI generation. Deferred — it changes the routing spec and the latency budget, so it is a separate decision, not a detail of this change.
- Whether `youdao_service` should attach examples per group instead of only to the first, and widen the `take(3)` cap (the payload also carries `auth_sents_part` with 6 authoritative sentences). Deferred: it changes the desktop panel and「存为笔记」too, which this change deliberately leaves alone.
