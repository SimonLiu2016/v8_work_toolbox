## Context

See `proposal.md` — Why for the measured failure path. Relevant current state:

- `web_search_service.dart:393` Bing snippet regex is `b_lineclamp[01]`; live pages and `test/fixtures/bing_sample.html` both carry only `b_lineclamp2` (10 occurrences, 0 of `[01]`). Measured: `[01]` → 0 matches; `[012]` → all match.
- `web_search_service.dart:188` treats `results.isNotEmpty` as backend success, so unrelated results never trigger fallback. The chain is `Bing → DuckDuckGo → (SearXNG if enabled) → McpSearchBackend`.
- `ai_config.json` on this machine: the only MCP server `mcp_firecrawl` has `enabled: false`. `SearXngSearchBackend.isEnabled` has **no assignment anywhere in the project** and no UI entry, so it is inert.
- `ai_assistant_service.dart:198` `_buildSystemPrompt` contains no date. The model embedded `2024` in a query for a 2026-10-08 question.
- `AgentLoop.run` (`agent_loop.dart:94`) feeds `outcome.feedText` back verbatim; nothing in the loop judges relevance.
- Real-machine evidence is in `~/Library/Application Support/V8WorkToolbox/ai_assistant_history.json`: `web_search success` followed by ten calendar/almanac results with no snippets, and a reply claiming no network access.

## Goals / Non-Goals

**Goals:**
- Snippets reach the model again, and a test pins that.
- The assistant knows today's date.
- Unrelated results are surfaced as unrelated, not laundered into an answer.
- Stop charging the user for a disabled MCP backend.

**Non-Goals:**
- Replacing Bing / enabling SearXNG / adding a new search provider (infrastructure decision, separate).
- Switching from prompt+regex tool protocol to structured function calling (a rewrite of the tool contract, separate).
- Guaranteeing relevance detection accuracy — it is heuristic; the spec requires honesty, not omniscience.

## Decisions

### Decision 1: Widen the snippet regex; pin it with an assertion

- **Choice**: `b_lineclamp[01]` → `b_lineclamp[0-9]` (or an explicit `[0-4]`), and add `expect(results.every((r) => r.snippet.isNotEmpty))` — or at least a majority — to the existing "real sample" test.
- **Alternatives considered**:
  - Match on any `<p>` in the block. Rejected: grabs navigation and footer text; noise worse than the current silence.
  - Read the `data-rslinkclamp` attribute instead. Rejected: it is an attribute marker without the text; the text still lives in the `<p>`.
- **Rationale**: the sample fixture already proves the fix; the test's own name already promises snippets. The gap was an assertion, not a fixture.

### Decision 2: Date goes into the system prompt, not into each query

- **Choice**: add a line to `_buildSystemPrompt` such as `当前日期：2026-10-08（星期X）`.
- **Alternatives considered**:
  - Rewrite the user's query to inject "今天" → a concrete date. Rejected: mutating user input is surprising and breaks multi-turn quoting; giving the model the date lets it decide.
  - Pass it only in the first turn. Rejected: every turn re-sends the full system prompt, so it costs nothing to keep it.
- **Rationale**: the model already fabricates years to fill the gap; filling the gap is cheaper than repairing the fabrication.

### Decision 3: Relevance signal is computed and shown, not silently acted on

- **Choice**: after a search returns, compute a cheap overlap signal (query terms appearing in title+snippet of the top results). When the signal is clearly absent, prefix the fed-back tool result with an explicit note that the retrieval appears unrelated and instruct the model to say so. The UI badge stays `success` (the tool *did* succeed) — the distinction lives in the result the model reads.
- **Alternatives considered**:
  - Mark the badge failed when results look unrelated. Rejected: wrong on two counts — the tool did not fail, and our heuristic would be asserting authority it does not have.
  - Auto-retry with a rewritten query. Rejected: hides the failure and doubles latency; the model is better placed to reformulate.
- **Rationale**: the bug is a lie of omission (unrelated material presented as the answer's basis). The fix is to stop omitting.

### Decision 4: MCP backend leaves the search chain when MCP is not in play

- **Choice**: build the chain with `McpSearchBackend()` only when at least one MCP server is enabled.
- **Alternatives considered**:
  - Keep it and let cooldown absorb the cost. Rejected: that is the status quo — a failed request plus a cooldown entry per search, for a service the user turned off.
  - Remove it entirely. Rejected: it is a legitimate backend when MCP is on.
- **Rationale**: the chain should describe what can actually serve.

## Risks / Trade-offs

- **[Risk] Relevance heuristic false-positives** — a good result flagged unrelated, model then refuses to answer. → Mitigated by requiring a *clearly absent* signal (not a weak one) before annotating, and by still giving the model the results so it can disagree.
- **[Risk] Wider regex captures junk** from an unrelated `<p class="b_lineclamp…">` elsewhere in the block. → Bounded: matching is per-block (`b_algo`), and the parser already strips tags and trims. Test asserts against a real sample.
- **[Risk] Date in prompt is stale within a long-lived session.** → It is written per request (the prompt is rebuilt for each `chat` call), so staleness is bounded by the session, not the process.
- **[Risk] Removing the MCP backend changes chain ordering for users who enable MCP later.** → Order is unchanged when enabled; the only change is absence when disabled.

## Migration Plan

1. Fix the regex + assert snippets in `test/web_search_service_test.dart` (fixture already covers it).
2. Add the current date to the assistant's system prompt.
3. Add the relevance annotation to the search path and its instruction to the model.
4. Gate `McpSearchBackend()` on MCP being enabled.
5. Rollback: all changes are local to two files plus one test; no data or protocol change.

## Open Questions

- Whether the relevance signal should also be surfaced in the UI (e.g. a subdued note on the badge). Deferred: the spec's requirement is about what the model is told; a visual treatment is polish and can follow without changing behaviour.
- Whether to add SearXNG as an enabled-by-default Chinese-friendly backend. Deferred: it needs an enablement entry point and an availability decision; touching it here would conflate a bug fix with an infrastructure change.
