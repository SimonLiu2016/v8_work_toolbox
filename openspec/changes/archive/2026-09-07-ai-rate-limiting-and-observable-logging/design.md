## Context

See `proposal.md` for motivation. Currently, `SmartDiskSlimmerPage` automatically initiates AI diagnosis upon scan completion without progress reporting, causing the button to spin indefinitely. Repeated user clicks run concurrent batch diagnoses. Furthermore, zero pacing delay between item diagnoses triggers gateway 429 (Too Many Requests) rate limits. Under the existing health model, 429 is treated as a severe failure that freezes the provider for 60 seconds. Finally, there is no structured logging of outbound prompts and incoming responses.

## Goals / Non-Goals

**Goals:**
- Eliminate background auto-diagnosis so that AI calls are only initiated upon explicit user intent.
- Ensure strict concurrency protection: only one batch diagnosis can run at any given moment.
- Add an 800ms pacing delay between items in `diagnoseBatch` to respect API rate limits.
- Differentiate 429 errors from server crashes: perform automatic 2-second backoff and retry, and prevent 429 from triggering a 60-second provider cooldown lock.
- Implement an observable, structured `AiLogger` that prints request details, status codes, latency, and response previews to the console.

**Non-Goals:**
- Creating a separate persistent database for log history.
- Changing disk scanner algorithms or candidate item data models.

## Decisions

### Decision 1: Explicit user-driven execution with mutex locking

**Choice**: Remove `_autoBatchDiagnoseIfNeeded()` from `SmartDiskSlimmerPage.initState()` / scan completion. In `_triggerManualBatchAi()`, check `if (_isBatchDiagnosing) return;` before proceeding.

**Rationale**: The user has full control over when tokens/bandwidth are consumed. Eliminates the false "endless spinning" perception on application startup.

### Decision 2: Batch pacing and single 429 backoff retry

**Choice**:
- In `diagnoseBatch()`, insert `await Future.delayed(const Duration(milliseconds: 800))` between items.
- In `AiService._chatAnthropic` and `_chatOpenAi`, if HTTP 429 is received, wait for `const Duration(milliseconds: 2000)` and retry once before failing.
- In `AiService._markProviderUnhealthy()`, if the error string contains `429`, do not transition the provider to `isHealthy: false` with 60s cooldown; log it as a transient rate-limit warning.

**Rationale**: AI provider rate limits are short-term sliding windows. An 800ms delay prevents bursting, and a 2000ms backoff gracefully resolves momentary rate limit spikes without disabling the provider for 60 seconds.

### Decision 3: Structured AiLogger for full observability

**Choice**: Introduce `AiLogger` in `lib/services/ai_logger.dart`:
- `logRequest({required String provider, required String protocol, required String url, required String model, required String promptSummary})`
- `logResponse({required int statusCode, required int durationMs, required String bodyPreview})`
- `logWarning(String message)`
- `logError(String message)`

Output format uses clean, structured box characters:
```
┌── [AI Request] ──────────────────────────────────────────
│ Provider: mimo | Protocol: anthropic | Model: mimo-v2.5-pro
│ URL: https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages
│ Prompt (185 chars): "你是一名 macOS 系统存储与文件架构专家..."
└──
┌── [AI Response] ─────────────────────────────────────────
│ Status: 200 OK | Duration: 1420ms
│ Body: {"id":"...","inferredApp":"...","safety":"safe",...}
└──
```

## Risks / Trade-offs

- **Batch execution time increases by 800ms per item** → For an 8-item batch, total pacing adds ~5.6 seconds. This is an intentional trade-off that completely prevents 429 rate limit errors and provider lockdown.
