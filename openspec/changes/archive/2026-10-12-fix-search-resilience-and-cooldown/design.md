## Context

See `proposal.md` for motivation. Currently:
- `BingSearchBackend` tries `candidateHosts` sequentially, but overwrites `lastError` with the last host's exception. When `cn.bing.com` redirects to `/` under an overseas proxy and returns 0 `b_algo` blocks, that error shadows whatever happened on `www.bing.com`.
- `DuckDuckGoSearchBackend` posts to `https://html.duckduckgo.com/html/`. Certain proxy exit IPs trigger Cloudflare/anti-bot HTTP 202 or challenge screens.
- `WebSearchService` maintains `_unhealthyUntil` with 60-second timeouts. If both backends fail once, subsequent searches in that minute fail immediately with "全部搜索后端处于冷却期，无可用后端".

## Goals / Non-Goals

**Goals:**
- Provide complete diagnostic visibility: aggregate errors from all attempted endpoints into the thrown exception so users and developers see exactly why each host failed.
- Handle redirects and browser header emulation in `BingSearchBackend` (add `User-Agent`, `Accept-Language`, `setlang=zh-Hans` parameter to prevent redirect loops and bot blocks).
- Enhance `DuckDuckGoSearchBackend` with GET query support and graceful handling/retry on 202.
- Implement progressive backoff and "probing pass-through" in `WebSearchService`: if all backends are marked unhealthy, instead of giving up immediately, clear or bypass cooldown for the primary backend so the user is never trapped in a dead state.

**Non-Goals:**
- Introducing external paid search API services (like Google Search API, Serper, etc.).
- Modifying UI layouts in the AI assistant message thread.

## Decisions

### Decision 1: Aggregated Endpoint Error Tracking in `BingSearchBackend`
- **Choice**: Collect `Map<String, String> endpointErrors = {}`. If all candidate endpoints fail, throw an `Exception` detailing all attempts: e.g. `Bing 全部端点均失败: [www.bing.com: Connection timeout (attempt 1 & 2), cn.bing.com: 未匹配到结果块]`.
- **Alternative considered**: Only return the last error. Rejected because it misleadingly points to `cn.bing.com` when `www.bing.com` failed for a different reason.

### Decision 2: Improved Browser Headers and Bing URL Parameters
- **Choice**:
  - Add query parameter `setlang=zh-Hans` and `cc=CN` or `cc=US` depending on host.
  - Set `maxRedirects = 5` and handle redirect responses if body is empty or non-200.
  - Emulate full modern browser headers (`Sec-Ch-Ua`, `Sec-Fetch-*`, `Accept-Language`).

### Decision 3: DuckDuckGo Fallback Resilience
- **Choice**: Support GET request `https://html.duckduckgo.com/html/?q=...` with standard query encoding and browser headers. If HTTP 202 is encountered, retry once after a short delay (e.g. 500ms) with a session cookie or fallback to Bing endpoint retry.

### Decision 4: Adaptive Cooldown in `WebSearchService`
- **Choice**:
  - Progressive backoff (e.g. 15s instead of fixed 60s for first failure).
  - If `candidateBackends` is empty (all in cooldown), do NOT fail immediately: log a warning, reset the cooldown of the highest priority configured backend (Bing), and attempt the query anyway. This guarantees the user is never permanently locked out when network conditions recover.

## Risks / Trade-offs

- [Search engine HTML scraping instability] → Mitigation: Dual-engine fallback (Bing + DuckDuckGo) + multiple Bing endpoints + clear actionable error reporting.
