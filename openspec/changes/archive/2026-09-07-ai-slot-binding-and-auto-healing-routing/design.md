## Context

See proposal.md for motivation. The current implementation uses a simple `Map<String, Map<String, String>>` in `AiConfigStore.slotBindings` mapping each slot name to a single `{providerId, model}` pair. `AiService.chat()` resolves the binding, looks up the provider, and makes one HTTP request — any failure is an unrecoverable exception that propagates to the business tool.

Key constraints:
- The app is a Flutter macOS desktop application (single-process, single-isolate for UI).
- `AiService` and `AiConfigStore` are singletons accessed synchronously by multiple tools.
- The existing `ai_config.json` format must remain backward-compatible (old single-binding configs must load without user intervention).
- Health probing must not add visible latency to normal (healthy) request paths.

## Goals / Non-Goals

**Goals:**
- Enable each slot to hold an ordered list of provider-model candidates with explicit priority
- Route requests through the candidate chain with automatic failover on failure
- Cache per-provider health state to avoid repeatedly hitting known-failed providers
- Return routing metadata alongside chat responses for optional UI transparency
- Display per-slot health status in the AI configuration page
- Seamlessly migrate legacy single-binding format on load

**Non-Goals:**
- Load balancing or round-robin across candidates (strictly priority-ordered failover)
- Background periodic health polling (health is assessed on-demand + cooldown cache)
- Streaming/SSE support changes (this change targets the existing request-response `chat()` API)
- Changes to `discoverModels()` or `testConnection()` flows
- Per-tool slot override (tools always use global slots; explicit provider pass-through is unchanged)

## Decisions

### Decision 1: Candidate list data structure

**Choice**: Replace `Map<String, Map<String, String>>` (`slotBindings`) with `Map<String, List<SlotCandidate>>` where `SlotCandidate` is a new value class holding `{providerId, model, priority}`.

**Rationale**: A dedicated typed class is safer than nested maps and supports future extensions (e.g., per-candidate weight or tags). The `priority` field is the list index (0 = highest), kept as an explicit int for serialization clarity.

**Alternative considered**: Keep the map structure with a list of maps — rejected because untyped maps are error-prone and harder to document.

### Decision 2: Health cache as in-memory map with TTL

**Choice**: Add `Map<String, ProviderHealthState>` to `AiService` (not persisted). `ProviderHealthState` holds `{isHealthy, lastCheckedAt, lastError}`. A provider is considered unhealthy for `cooldownDuration` (default 60s) after a failure. The cache lives in-memory only and resets on app restart.

**Rationale**: Persisting health state adds complexity with little benefit — on cold start, all providers are assumed healthy and will be re-validated on first use. In-memory-only avoids stale state from a previous session.

**Alternative considered**: Persist health state to disk — rejected because providers can recover between sessions and stale "unhealthy" flags would cause confusion. Also considered background heartbeat polling — rejected as over-engineering for a desktop app with infrequent AI requests.

### Decision 3: Failover within a single `chat()` call

**Choice**: `chat()` iterates candidates sequentially within a single invocation. On transport failure (timeout, connection refused) or API error (4xx/5xx), it marks the provider unhealthy, records the attempt, and moves to the next candidate. Content-level issues (empty response, unexpected format) are NOT treated as provider failures.

**Rationale**: Sequential in-call failover gives the caller a single `Future<ChatResult>` to await, keeping the API simple. Distinguishing transport/API errors from content issues prevents unnecessary failover when the provider is technically reachable but the model produces weak output.

**Alternative considered**: Return failure from `chat()` and let the caller retry with a different slot — rejected because it pushes routing complexity into every business tool.

### Decision 4: `ChatResult` structured return type

**Choice**: Change `chat()` return type from `Future<String>` to `Future<ChatResult>` where `ChatResult` contains `{text, usedProviderId, usedModel, routingTrace}`. `routingTrace` is `List<RouteAttempt>` with `{providerId, model, outcome, durationMs, error?}`.

**Rationale**: Returning a structured type lets callers optionally inspect routing info without breaking existing code. A `ChatResult.text` getter makes migration straightforward — callers that only need the text can use `result.text`.

**Alternative considered**: Keep returning `String` and log routing info — rejected because callers like Smart Disk Slimmer could meaningfully surface degradation to users. Also considered a separate `onRoute` callback — rejected as unnecessarily complex.

### Decision 5: Backward-compatible config migration

**Choice**: On `_load()`, detect whether `defaultSlots` values are maps (legacy) or lists (new format). If legacy, wrap each `{providerId, model}` into a single-element `[SlotCandidate]` and immediately `_save()` in the new format.

**Rationale**: One-time silent migration avoids the need for a separate migration tool or user action. The old format is unambiguously distinguishable (map vs list).

### Decision 6: UI — inline candidate list with drag-reorder

**Choice**: Replace the current side-by-side provider/model dropdowns per slot with a reorderable list (`ReorderableListView`) of candidate cards, each showing provider name + model + health indicator. An "Add Candidate" button opens a dialog to pick provider + model.

**Rationale**: Drag-reorder is the most intuitive UX for priority management. The per-candidate health dot (green/yellow/red) provides at-a-glance status.

## Risks / Trade-offs

- **Added latency on multi-failure paths** → Mitigated by health cooldown cache: unhealthy providers are skipped instantly, so latency only increases on the first failure detection. Worst case: N sequential timeouts (N = candidate count). Acceptable for a desktop app with typically 2-3 candidates.
- **Breaking change to `chat()` return type** → Mitigated by providing `ChatResult.text` for easy migration. All internal callers will be updated in this change. External callers (none currently) would need to adapt.
- **Config format change** → Mitigated by auto-migration on load. Downgrade to an older app version would not understand the new format, but this is a forward-only desktop app without rollback requirements.
- **Health cache memory** → Negligible: one entry per provider (typically < 10).

## Migration Plan

1. Update `AiConfigStore` data model and serialization with backward-compatible loading
2. Add `ProviderHealthState` and health cache to `AiService`
3. Refactor `chat()` to return `ChatResult` and implement failover loop
4. Add `SlotUnavailableException` structured error
5. Update `AiConfigPage` slots tab UI with candidate list + health indicators
6. Update all `chat()` callers (Smart Disk Slimmer) to use `ChatResult.text`
7. Manual verification: test with 2+ providers, primary failure, and config migration from legacy format
